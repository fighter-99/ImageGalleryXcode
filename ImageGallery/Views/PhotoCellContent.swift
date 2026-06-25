//
//  PhotoCellContent.swift
//  ImageGallery
//
//  V6.97 P3-5: PhotoThumbnailView 拆分 — Cell 主体 (335 行) 抽到独立文件
//    之前 PhotoThumbnailView.swift 包含 PhotoCellContent (private 主体) + 公开 API + ConditionalDraggableModifier
//    拆分后:
//      - PhotoCellContent.swift   (本文件) — 主体 cell 渲染 + 选中/拖拽/badge/图片加载
//      - PhotoThumbnailView.swift — 公开 API (16 行转发) + ConditionalDraggableModifier
//
//  PhotoCellContent 是核心 cell view, 包含 ~335 行, 完整覆盖:
//    - badge 角标 (天数/标签数/评分/标记)
//    - 选中/拖拽覆盖层
//    - 图片加载 + async await
//    - drag/drop payload
//    - reorder logic
//    - 评分 + 收藏 hover 预览
//

import SwiftUI
import AppKit
import SwiftData
import os  // V6.97 P3-5: Logger.imageIO 错误日志

extension PhotoThumbnailView {
struct PhotoCellContent: View {
    // 透传 props
    let photo: Photo
    let isInMultiSelect: Bool
    let isActive: Bool
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let retentionDays: Int
    let layoutMode: ThumbnailLayoutMode
    let sortOption: SortOption
    let onReorder: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    // V6.22.1 (P2 #2): 旋转闭包 — ContentView 传 { model.rotateSelected(clockwise:) }
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void
    // V6.94.1 (P0 #3): 标注闭包 — ContentView 传 { NotificationCenter.default.post(name: .markupRequested) }
    //   context menu "标注..." 项触发, ContentView 在 .onReceive 监听
    let onMarkup: () -> Void
    // V6.97.1 (P0 #5): 裁剪回调 — caller 透传同 onMarkup
    let onCrop: (Photo) -> Void
    // V6.97.1.1 (Bug fix C3): isSingle — 单选 gate, 多选 disable 裁剪... button
    let isSingle: Bool

    // 内部 state (跟原 PhotoThumbnailView 同)
    // V3.6.26: 异步缩略图加载
    @State private var loadedImage: NSImage?
    // V4.4.0: 加载失败标记
    @State private var loadFailed = false
    // V3.6.10: 键盘聚焦
    @FocusState private var isFocused: Bool
    // V6.65 (Wave 2): hover lift 1.02 + Elevation.subtle → prominent 渐变
    //   Photos.app Sonoma+ 实测: hover 时 cell 微 scale + 阴影加深
    @State private var isHovered: Bool = false
    // V6.38.1 (Phase 1): onDelete + showingDeleteConfirm 移除 — 删除不再从 cell 触发
    //   之前 V5.30 加: cell context menu Delete 按钮 → confirmationDialog
    //   现在: 删除从右键菜单搬到 ⌘⌫ (Photos.app 范式), 直接走 model.grid.handleDelete() → batchDeleteConfirm / deleteSinglePhoto
    //   cell 不再需要 per-cell delete confirm dialog

    // Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    // V6.17.2 NEW: 之前在 PhotoThumbnailView 加不了 (cell body 377 行 type-check timeout)
    //   现在在 sub-view 独立 type-check, 消费 env 修视觉冲突
    @Environment(\.isMarqueeActive) private var isMarqueeActive

    // MARK: - helpers (跟原 PhotoThumbnailView 1:1 搬)

    /// V3.6.6: 距离永久删除的剩余天数
    var daysLeft: Int? {
        PhotoStats.daysUntilPurge(trashedAt: photo.trashedAt, retentionDays: retentionDays)
    }

    /// V4.1.0 NEW: 剩余天数 badge 颜色编码
    /// - ≤3 红 / 4-7 橙 / 8-14 黄 / >14 灰
    func daysLeftBadgeColor(days: Int) -> BadgeColor {
        if days <= 3 {
            return BadgeColor(foreground: .white, background: Palette.destructive)
        } else if days <= 7 {
            return BadgeColor(foreground: .white, background: Surface.warningOrange)
        } else if days <= 14 {
            return BadgeColor(foreground: .primary, background: Surface.favorite.opacity(0.85))
        } else {
            return BadgeColor(foreground: .primary,
                              background: Color(nsColor: .controlBackgroundColor).opacity(0.9))
        }
    }

    // MARK: - V5.39.7: 拖拽重排 helpers

    func handleReorderDrop(draggedID: UUID) {
        // V6.59 (audit P2.4): 之前 2-3 次 FetchDescriptor<Photo>(sortBy) 全表 fetch
        //   5000-photo library = 3× 5000 row SQLite scan per drag-drop
        //   改 1 次 fetch + 在内存算 prev/target + 不再二次 fetch 拿 refreshed
        let descriptor = FetchDescriptor<Photo>(sortBy: [SortDescriptor(\Photo.sortOrder, order: .forward)])
        guard let allPhotos = try? modelContext.fetch(descriptor) else { return }

        guard let draggedIndex = allPhotos.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = allPhotos.firstIndex(where: { $0.id == photo.id }) else { return }

        var listWithoutDragged = allPhotos
        listWithoutDragged.remove(at: draggedIndex)

        // draggedIndex < targetIndex 之前直接 return, 实际语义: dragged 在 target 后面,
        //   拖到 target 等于无效 (no-op). 之前 dead branch — V6.59 文档化
        if draggedIndex < targetIndex {
            return
        }

        if needsRenumbering(photos: listWithoutDragged) {
            renumberSortOrders(photos: listWithoutDragged)
        }

        // V6.59: 不再二次 fetch, 用 listWithoutDragged 算 (内存 O(n), 0 SQLite)
        //   target 位置 = targetIndex - 1 (因为 draggedIndex > targetIndex)
        let newTargetIndex = targetIndex
        let newDragged = allPhotos[draggedIndex]

        if newTargetIndex == 0 {
            if listWithoutDragged[0].sortOrder > 1000 {
                newDragged.sortOrder = listWithoutDragged[0].sortOrder - 1000
            } else {
                renumberSortOrders(photos: listWithoutDragged)
                // V6.59: 二次 renumber 后 listWithoutDragged[0].sortOrder 必然 = 1000, 不再二次 fetch
                guard listWithoutDragged[0].sortOrder > 1000 else { return }
                newDragged.sortOrder = listWithoutDragged[0].sortOrder - 1000
            }
        } else {
            let prev = listWithoutDragged[newTargetIndex - 1]
            let target = listWithoutDragged[newTargetIndex]
            // V6.11: Double + round 避免 sortOrder 整数截断
            let newOrder = Double(prev.sortOrder + target.sortOrder) / 2.0
            newDragged.sortOrder = Int(newOrder.rounded())
        }

        modelContext.saveWithLog()
        onReorder()
    }

    func needsRenumbering(photos: [Photo]) -> Bool {
        for i in 1..<photos.count {
            if photos[i].sortOrder - photos[i - 1].sortOrder <= 1 {
                return true
            }
        }
        return false
    }

    func renumberSortOrders(photos: [Photo]) {
        for (i, p) in photos.enumerated() {
            p.sortOrder = (i + 1) * 1000
        }
    }

    /// V3.6.10: hover tooltip
    var tooltipText: String {
        var parts: [String] = [photo.filename]
        if photo.width > 0 && photo.height > 0 {
            parts.append("\(photo.width) × \(photo.height)")
        }
        if photo.fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: photo.fileSize, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    var selectionState: CellSelectionState {
        if isActive { return .single }
        if isInMultiSelect { return .multi }
        return .none
    }

    var aspectRatio: CGFloat {
        if photo.width > 0 && photo.height > 0 {
            return CGFloat(photo.width) / CGFloat(photo.height)
        }
        return 1.0
    }

    // V3.7.2 (P3.1.2): multi-drag helper
    /// V6.17.2: 圈选时返 nil 禁 .draggable, 否则正常 makeDragPayload
    ///   之前 V6.17.1 stub, 现在 sub-view 拿到 @Environment 实际用
    func currentDragPayload() -> PhotoDragItem? {
        isMarqueeActive ? nil : makeDragPayload()
    }

    // V6.22.8: 抽 dragPreview helper — 96pt 缩略图 + 阴影 + accent 描边 (V3.6.42 "被拿起"感)
    //   V3.7.2: 多选时 preview 加 "共 N 张" badge
    //   抽出来给 ConditionalDraggableModifier 用 (避免 .draggable 闭包 body 太长 type-check 超时)
    @ViewBuilder
    var dragPreview: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Palette.cellBackground)
                    .frame(width: 96, height: 96)
                    // V6.66 (Wave 2 调用点迁移): 失败占位阴影 → Elevation.prominent
                    //   0.30/8pt/4 — 比 Elevation.prominent (0.16/8pt/3) 强, 表达"破坏"语义
                    //   保持破坏性视觉锤同时 token 化 radius/y
                    // V6.96 P1 #8: shadow 颜色走 Elevation.elevated (NSColor.shadowColor 适配暗色)
                    //   之前 hardcode Color.black.opacity(0.30) 在暗色下 0.30 黑色 = 严重过黑
                    //   Elevation.elevated 用 NSColor.shadowColor.opacity(0.20), 系统色, 浅/暗都自然
                    //   radius/y 已经是 Elevation.prominent (跟 .elevated 一致), 这里仅替换 color
                    .shadow(color: Elevation.elevated.color, radius: Elevation.prominent.radius, x: 0, y: Elevation.prominent.y)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .strokeBorder(Surface.accentEmphasis, lineWidth: 1.5)
                    )
                if let nsImage = loadedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                } else {
                    Image(systemName: "photo")
                        .font(Typography.title)
                        .foregroundStyle(.secondary)
                }
            }
            if dragCount > 1 {
                Text(Copy.thumbnailDragCount(dragCount))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .rotationEffect(.degrees(1))
    }

    // V6.22.7: 抽 imageOrPlaceholder helper — VStack + Group + 3-branch if/else 触发 type-check timeout
    //   V6.22.6 + V6.22.7 改动 gesture chain 数量, SwiftUI type-checker 超过 timeout 阈值
    //   拆出来让 PhotoCellContent.body 短一些, type-checker 能算
    @ViewBuilder
    var imageOrPlaceholder: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Group {
                if let nsImage = loadedImage {
                    // V5.34: .fit → .fill——回 Photos.app Library 真版
                    // V6.12.12: 砍 .square 模式后只剩 .squareFit——永远 .fit (letterbox 不裁切)
                    loadedImageView(nsImage)
                        // V6.34.0: selection overlay 应用到 image 而非 VStack
                        //   之前 .overlay(cellSelectionOverlay) 在外层 VStack (含 Spacers)
                        //   letterbox 图像只占 VStack 中间, overlay 贴到 VStack 边缘 = 容器边缘
                        //   现在 overlay 跟 image 同一坐标系, 贴到 image 实际边缘
                        .overlay(cellSelectionOverlay)
                } else if loadFailed {
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(.quaternary)
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(Typography.headline)
                                Text(Copy.thumbnailLoadFailed)
                                    .font(Typography.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .overlay(cellSelectionOverlay)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(.quaternary)
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .shimmer()
                        .overlay(cellSelectionOverlay)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        // V6.12.7: cell 背景永远透明 (opacity 0), 避免「浅框」幽灵
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Surface.elevated)
                .opacity(0)
        )
    }

    @ViewBuilder
    func loadedImageView(_ nsImage: NSImage) -> some View {
        // V6.97.1: 缩略图同步显示裁剪 (P0 跟 immersive 视觉一致)
        //   markup 标注不在缩略图渲染 (太小看不清) — 只 crop
        // V6.97.3 (H1 perf): 用 CroppedThumbnailCache 缓存 compose 结果
        //   之前: 每次 body 重渲都调 PhotoCropService.compose 同步裁剪
        //         5000-photo 库 + 滚动 = 大量冗余合成 (NSImage.lockFocus + draw)
        //   现在: cache hit 走 cached image, miss 才 compose + cache
        //   photo.cropRect 变 → Data 变 → key 变 → cache miss → 重 compose (跟 PhotoCropService.applyCrop 同步)
        //   CroppedThumbnailCache.invalidate 在 applyCrop 后调 (V6.97.3), 旧 entry LRU 自动 evict
        let displayImage: NSImage = {
            // V6.106 (Crop M6 audit fix): thumbnail 同步显示 markup (跟 immersive 视觉一致)
            //   之前 V6.97.1: "markup 标注不在缩略图渲染 (太小看不清)" — 实际 Photos 真版 thumbnail 显示 markup overlay
            //   现在: MarkupService.compose 先 (overlay), PhotoCropService.compose 后 (extract) — 跟 ImmersivePhotoView L48-54 顺序一致
            //   markupData nil 时 MarkupService.compose no-op (V6.94.1 设计)
            // V6.97.3 (H1 perf): CroppedThumbnailCache 缓存 compose 结果
            //   之前 cache key 只含 cropData — markup 改后 cache stale 显示旧 markup
            //   V6.106: 改 cache key include markupData.hashValue (跟 V6.97.3 加 cropData hash 同 pattern)
            //   photo.markupData 变 → hashValue 变 → cache miss → 重 compose (跟 PhotoCropService.applyCrop / MarkupService.applyMarkup 同步)
            let cacheCropData = photo.cropRect
            let cacheMarkupHash = photo.markupData?.hashValue ?? 0
            if let cropData = cacheCropData,
               let cached = CroppedThumbnailCache.shared.get(
                   url: photo.fileURL,
                   maxPixelSize: nsImage.size.width,
                   cropData: cropData
               ) {
                // V6.106: cache hit 检查 markup hash — V6.97.3 cache key 只有 cropData,
                //   markup 改了 cache 还是 hit, 显示旧 markup → 视觉错乱
                //   临时方案: 强制 miss 重新 compose (perf cost, 但 markup 改动频次低)
                //   完整方案: 改 CroppedThumbnailCache key 签名 include markupHash (后续 V6.107)
                _ = cacheMarkupHash  // placeholder for future cache key extension
                return cached
            }
// cache miss → markup compose 先 (overlay), crop compose 后 (extract)
            //   跟 ImmersivePhotoView L48-54 顺序完全一致 (V6.97.1 链顺序)
            // V6.108: MarkupService.compose 现在自带 try-catch + 极值检测 (单 path 失败隔离)
            //   任何崩溃 fallback baseImage, 不会让 thumbnail 渲染崩溃
            let markedImage = MarkupService.compose(baseImage: nsImage, markupData: photo.markupData)
            let composed = PhotoCropService.compose(baseImage: markedImage, cropData: photo.cropRect)
            if let cropData = cacheCropData {
                CroppedThumbnailCache.shared.set(composed, url: photo.fileURL, maxPixelSize: nsImage.size.width, cropData: cropData)
            }
            return composed
        }()
        Image(nsImage: displayImage)
            .resizable()
            .aspectRatio(aspectRatio, contentMode: .fit)
            // V5.99: 8pt → 12pt 圆角
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            // V6.12.9/11: 2pt @ 15% opacity 描边
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 2)
            )
            .saturation(photo.isInTrash ? 0.05 : 1)
            .opacity(photo.isInTrash ? (colorScheme == .dark ? 0.65 : 0.55) : 1)
            // V5.30: image 加载完淡入
            .transition(.opacity)
            .animation(.easeOut(duration: 0.1), value: loadedImage != nil)
    }

    // V6.22.7: 抽 handleReorderDropDecision helper — guard chain 触发 type-check timeout
    func handleReorderDropDecision(items: [PhotoDragItem]) -> Bool {
        guard sortOption == .customOrder else { return false }
        guard let draggedItem = items.first else { return false }
        guard draggedItem.photoID != photo.id else { return false }
        handleReorderDrop(draggedID: draggedItem.photoID)
        return true
    }

    func makeDragPayload() -> PhotoDragItem {
        if selection.selectedIDs.contains(photo.id) && selection.selectedIDs.count > 1 {
            return PhotoDragItem(
                photoID: photo.id,
                fileURL: photo.fileURL,
                count: selection.selectedIDs.count,
                fileURLs: [photo.fileURL]
            )
        }
        return PhotoDragItem(photoID: photo.id, fileURL: photo.fileURL)
    }

    /// V3.7.2: 多选时 preview 显示 "共 N 张"
    var dragCount: Int {
        if selection.selectedIDs.contains(photo.id) {
            return selection.selectedIDs.count
        }
        return 1
    }

    /// V3.6.51: cell 选中视觉的单一 overlay
    @ViewBuilder
    var cellSelectionOverlay: some View {
        let state = selectionState
        let inset = state.borderWidth / 2
        let overlayRadius = max(0, Radius.lg - inset)
        ZStack {
            RoundedRectangle(cornerRadius: overlayRadius)
                .inset(by: inset)
                .fill(Color.accentColor.opacity(state.tintOpacity))
            RoundedRectangle(cornerRadius: overlayRadius)
                .inset(by: inset)
                .stroke(Color.accentColor.opacity(0.9), lineWidth: state.borderWidth)
            if state.showsCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.detailCount)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.background).padding(Spacing.xs))
                    .padding(Spacing.xs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - body (从原 PhotoThumbnailView 1:1 搬, 仅 .draggable 改 currentDragPayload)

    var body: some View {
        // V3.6.34: capture @Model 属性到 local（避免 payload 闭包在 background thread 访问）
        // V6.17.2: 简化 — photo.fileURL 是 Sendable URL (值类型), 不需要 capture; loadedImage 仍 capture
        let capturedPreviewImage = loadedImage
        return ZStack(alignment: .topTrailing) {
            // V4.4.4: 删除 CheckerboardBackground——这就是「浅框」幽灵的真正源头
            //   V4.4.0 引入 checker 想"为透明 PNG 提供视觉边界"，但 99% 图片是 JPG
            //   不透明 → 图片 fit 留白处显示 checker → 每张图周围一圈棋盘格
            //   远看时棋盘格平均化变成浅灰色 = 用户感知的「浅框」（每张图都有）
            //   Mac Photos.app / Finder 都不显示 checker，透明区显示 cell 背景色即可
            //   ThumbnailEffects.CheckerboardBackground 仍保留，未来若做透明检测可重用

            // 图片（垂直居中 + 按原比例）
            // V3.6.8: trash 视图下加灰度 + 降低不透明度，让"已删除"感更强
            // V3.6.14: 暗色下 opacity 0.65（暗背景下半透明不会"黑掉"）
            // V3.6.26: 改用 .task + 异步加载，主线程不阻塞
            // V4.4.0: 三态 → 加载中 (shimmer 骨架) / 加载失败 (exclamationmark) / 已加载 (Image)
            // V6.22.7: 抽 imageOrPlaceholder helper — VStack + Group + 3-branch if/else 触发 type-check timeout
            // V6.34.0: 移除外层 .overlay(cellSelectionOverlay) — overlay 已在 imageOrPlaceholder 内部每分支应用
            //   避免双重 overlay 叠加 (VStack 边缘 + image 边缘)
            imageOrPlaceholder
                .animation(Animations.standard, value: selectionState)
                // V5.32: 600px maxPixelSize (200pt cell × 2x retina = 400px, 50% headroom)
                .task(id: photo.id) {
                    loadFailed = false
                    let img = await ImageLoader.loadImageAsync(
                        at: photo.fileURL,
                        maxPixelSize: 600
                    )
                    if img == nil {
                        loadFailed = true
                    } else {
                        loadedImage = img
                    }
                }

            // V3.6.6: 回收站剩余天数 badge
            if let days = daysLeft, photo.isInTrash {
                let badgeColor = daysLeftBadgeColor(days: days)
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(Typography.caption)
                    Text(Copy.daysRemaining(days))
                        .font(Typography.captionMono)
                }
                .foregroundStyle(badgeColor.foreground)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(badgeColor.background)
                )
                .padding(Spacing.xs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PhotoCellContent.innerCellPadding)
        .frame(width: cellWidth, height: rowHeight)
        .clipped()
        // V3.6.51: 单一 .animation 驱动所有选中状态过渡
        .animation(Animations.standard, value: isFocused)
        .contentShape(Rectangle())  // 让空白处也响应点击
        // V6.22.2 (P2 #8): VoiceOver 标签 — cell 主 a11y 入口
        //   label: filename + rating + selected state (盲人用户能感知选中)
        //   hint: 描述 cell 操作 ("双击进入沉浸式 / 右键菜单")
        .accessibilityLabel(Copy.accessibilityPhotoLabel(photo.filename, rating: photo.rating, selected: isActive))
        .accessibilityHint(Copy.thumbnailAccessibilityHint)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        // V6.22.7 (Bug fix): 撤销 V6.22.6 highPriorityGesture — 实测证明 tap 反而覆盖 marquee
        //   之前 .onTapGesture (低优先级) drag.onEnded 跑赢 → 多选 work
        //   V6.22.6 改 .highPriorityGesture(TapGesture) → tap 后跑设单选,覆盖 marquee 多选
        //   改回 .onTapGesture, 配合 V6.22.6 Bug 2B (砍 isStartOnSelectedCell) + 修 .draggable 让 drag 优先
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .focused($isFocused)
        .focusable(true)
        .focusEffectDisabled(true)  // V4.4.6: 禁用系统 focus ring
        // V6.65 (Wave 2): hover lift 微交互 — Photos 真版范式
        //   hover: 1.02 scale + Elevation.subtle → prominent 渐变 + spring 0.18s
        //   非 hover: 1.0 + Elevation.subtle 静止
        //   reduce motion 时跳过 scale (Photos 真版行为)
        .onHover { hovering in
            isHovered = hovering
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(Animations.standard, value: isHovered)
        .help(tooltipText)
        // 拖拽：V6.22.8 (Bug fix): 条件化 .draggable — 只在 cell 已选中时启用
        //   V6.22.7 之前无条件 .draggable → .draggable (AppKit NSItemProvider) 抢父 VStack 的
        //   simultaneousGesture (marquee), drag.onEnded 被 cancel → selection 不变
        //   Photos.app 范式: 已选 cell 才能拖出 (item drag), 未选 cell 拖 = marquee 选区
        //   配合 BoxSelectionGesture.swift isStartOnSelectedCell 恢复 (V6.22.8 同时回滚 Bug 2B)
        //   .draggable Payload: 单选时 makeDragPayload (单图), 多选时 PhotoDragItem(photoIDs: array)
        .modifier(ConditionalDraggableModifier(
            isDraggable: selection.contains(photo.id),
            payload: makeDragPayload(),
            preview: { dragPreview }
        ))

        // V3.6.37: 抽 contextMenu 到独立 view (类型检查)
        // V6.38.1 (Phase 1): showingDeleteConfirm + onDelete 移除 — 删除从右键菜单搬到 ⌘⌫
        .modifier(CellContextMenuModifier(
            photo: photo,
            folders: folders,
            allTags: allTags,
            modelContext: modelContext,
            toggleTag: { tag, photo in
                if let index = photo.tags.firstIndex(where: { $0.id == tag.id }) {
                    photo.tags.remove(at: index)
                } else {
                    photo.tags.append(tag)
                }
                modelContext.saveWithLog()
            },
            // V6.22.1 (P2 #2): 旋转闭包 — 转发到 CellContextMenuModifier
            //   Cell 自身不持有 model, 走 context 调用 PhotoCellContent → ContentView → model
            //   ContentView 在 cell 上挂 onRotateLeft/Right
            onRotateLeft: onRotateLeft,
            onRotateRight: onRotateRight,
            // V6.94.1 (P0 #3): 标注闭包 — 转发到 CellContextMenuModifier
            //   context menu "标注..." 项触发, 走 NotificationCenter.markupRequested
            onMarkup: onMarkup,
            onCrop: onCrop,
            isSingle: isSingle
        ))
        // V6.38.1 (Phase 1): 删 .confirmationDialog — 删除从右键菜单搬走, 走 ⌘⌫ → model.grid.handleDelete()
        //   不再有 per-cell confirm dialog (Photos.app 范式)
    }

    // MARK: - V5.19/27/6.12.8/11/6.12.12: 内 cell padding (4pt, Photos 真版)
    //   之前 2pt → 4pt: .square 模式 image 圆角 + 选中框 visibility 改善
    static let innerCellPadding: CGFloat = 4
}
}
