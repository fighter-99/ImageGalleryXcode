//
//  PhotoThumbnailView.swift
//  ImageGallery
//
//  V4.36.0: 接受 cellSize (column width) + 内部按 photoAspectRatio 算 cellHeight
//    旧 cellHeight 固定 170pt → 竖向照片上下留白 / 横向照片左右留白
//    新 cellHeight = cellSize / aspectRatio → image 完全填满 cell 无留白
//
//  V5.16: 改 cellSize → cellWidth + rowHeight（masonry 外部算好）
//    旧公式 cellHeight = cellSize / aspectRatio → 行底部参差（截图 23）
//    新 row 高度统一 = rowHeight，cell 宽度 = rowHeight × photo.aspectRatio
//    MasonryRow 算好每行 cell 宽传入——行内 cell 高齐
//
//  V4.39.0: 从 PhotoGridView.swift 拆出独立文件
//    PhotoGridView 1180 → 580 行（V4.10.0 ContentView 拆分模式延续）
//    PBXFileSystemSynchronizedRootGroup 自动同步——无需改 pbxproj
//
//  整个文件是单个缩略图 cell 的完整渲染：图片 + 选中视觉 + 收藏星标 +
//  回收站天数 badge + 多选 ✓ + contextMenu + 拖拽 + tooltip + hover 缩放
//
//  V6.17.2: 抽 cell 主体 (body + state + env + helpers) 到 PhotoCellContent sub-view
//    解决 V6.17.1 known limitation: 圈选时 cell .draggable 跟 marquee rect 同时显示
//    sub-view 单独 type-check, 加 @Environment(\.isMarqueeActive), 圈选时 .draggable 返 nil
//    视觉冲突彻底修
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - V6.17.2: 抽 cell 主体到 PhotoCellContent sub-view
//
//  解 V6.17.1 known limitation (圈选时 cell .draggable 跟 marquee rect 同时显示)
//  之前: body 377 行 + 多个 modifier chain → SwiftUI type-check timeout
//  之前: 不能加 @Environment(\.isMarqueeActive) (V6.17.1 注释 line 64-67)
//  现在: 主体 377 行移到独立 private struct, 单独 type-check 不超时
//  现在: sub-view 加 @Environment(\.isMarqueeActive), 圈选时 .draggable 返 nil
//
//  调用方: PhotoThumbnailView 退化为 17 行纯转发
//  Env 传播: PhotoGridView 2 个 layout 注入 .environment(\.isMarqueeActive, ...)
//  行为变化: 圈选时 cell 不再 .draggable (visual conflict 消失)
private struct PhotoCellContent: View {
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
    let onDelete: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    // V6.22.1 (P2 #2): 旋转闭包 — ContentView 传 { model.rotateSelected(clockwise:) }
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void

    // 内部 state (跟原 PhotoThumbnailView 同)
    // V3.6.26: 异步缩略图加载
    @State private var loadedImage: NSImage?
    // V4.4.0: 加载失败标记
    @State private var loadFailed = false
    // V3.6.10: 键盘聚焦
    @FocusState private var isFocused: Bool
    // V5.30: showingDeleteConfirm 跟 .confirmationDialog 一起搬 sub-view
    @State private var showingDeleteConfirm = false

    // Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    // V6.17.2 NEW: 之前在 PhotoThumbnailView 加不了 (cell body 377 行 type-check timeout)
    //   现在在 sub-view 独立 type-check, 消费 env 修视觉冲突
    @Environment(\.isMarqueeActive) private var isMarqueeActive

    // MARK: - helpers (跟原 PhotoThumbnailView 1:1 搬)

    /// V3.6.6: 距离永久删除的剩余天数
    private var daysLeft: Int? {
        PhotoStats.daysUntilPurge(trashedAt: photo.trashedAt, retentionDays: retentionDays)
    }

    /// V4.1.0 NEW: 剩余天数 badge 颜色编码
    /// - ≤3 红 / 4-7 橙 / 8-14 黄 / >14 灰
    private func daysLeftBadgeColor(days: Int) -> BadgeColor {
        if days <= 3 {
            return BadgeColor(foreground: .white, background: Palette.destructive)
        } else if days <= 7 {
            return BadgeColor(foreground: .white, background: Color.orange)
        } else if days <= 14 {
            return BadgeColor(foreground: .primary, background: Surface.favorite.opacity(0.85))
        } else {
            return BadgeColor(foreground: .primary,
                              background: Color(nsColor: .controlBackgroundColor).opacity(0.9))
        }
    }

    // MARK: - V5.39.7: 拖拽重排 helpers

    private func handleReorderDrop(draggedID: UUID) {
        let descriptor = FetchDescriptor<Photo>(sortBy: [SortDescriptor(\Photo.sortOrder, order: .forward)])
        guard let allPhotos = try? modelContext.fetch(descriptor) else { return }
        guard let draggedIndex = allPhotos.firstIndex(where: { $0.id == draggedID }) else { return }
        let _ = allPhotos[draggedIndex]  // V6.17.2: 实际不需要 draggedPhoto 引用 (后续 re-fetch)

        guard let targetIndex = allPhotos.firstIndex(where: { $0.id == photo.id }) else { return }

        var listWithoutDragged = allPhotos
        listWithoutDragged.remove(at: draggedIndex)

        if draggedIndex < targetIndex {
            return
        }

        if needsRenumbering(photos: listWithoutDragged) {
            renumberSortOrders(photos: listWithoutDragged)
        }

        let descriptor2 = FetchDescriptor<Photo>(sortBy: [SortDescriptor(\Photo.sortOrder, order: .forward)])
        guard let refreshed = try? modelContext.fetch(descriptor2),
              let newTargetIndex = refreshed.firstIndex(where: { $0.id == photo.id }),
              let newDragged = refreshed.first(where: { $0.id == draggedID }) else { return }

        if newTargetIndex == 0 {
            if refreshed[0].sortOrder > 1000 {
                newDragged.sortOrder = refreshed[0].sortOrder - 1000
            } else {
                renumberSortOrders(photos: refreshed)
                guard let refreshed2 = try? modelContext.fetch(descriptor2),
                      let newTargetIndex2 = refreshed2.firstIndex(where: { $0.id == photo.id }),
                      let newDragged2 = refreshed2.first(where: { $0.id == draggedID }),
                      newTargetIndex2 == 0,
                      refreshed2[0].sortOrder > 1000 else { return }
                newDragged2.sortOrder = refreshed2[0].sortOrder - 1000
            }
        } else {
            let prev = refreshed[newTargetIndex - 1]
            let target = refreshed[newTargetIndex]
            // V6.11: Double + round 避免 sortOrder 整数截断
            let newOrder = Double(prev.sortOrder + target.sortOrder) / 2.0
            newDragged.sortOrder = Int(newOrder.rounded())
        }

        modelContext.saveWithLog()
        onReorder()
    }

    private func needsRenumbering(photos: [Photo]) -> Bool {
        for i in 1..<photos.count {
            if photos[i].sortOrder - photos[i - 1].sortOrder <= 1 {
                return true
            }
        }
        return false
    }

    private func renumberSortOrders(photos: [Photo]) {
        for (i, p) in photos.enumerated() {
            p.sortOrder = (i + 1) * 1000
        }
    }

    /// V3.6.10: hover tooltip
    private var tooltipText: String {
        var parts: [String] = [photo.filename]
        if photo.width > 0 && photo.height > 0 {
            parts.append("\(photo.width) × \(photo.height)")
        }
        if photo.fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: photo.fileSize, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private var selectionState: CellSelectionState {
        if isActive { return .single }
        if isInMultiSelect { return .multi }
        return .none
    }

    private var aspectRatio: CGFloat {
        if photo.width > 0 && photo.height > 0 {
            return CGFloat(photo.width) / CGFloat(photo.height)
        }
        return 1.0
    }

    // V3.7.2 (P3.1.2): multi-drag helper
    /// V6.17.2: 圈选时返 nil 禁 .draggable, 否则正常 makeDragPayload
    ///   之前 V6.17.1 stub, 现在 sub-view 拿到 @Environment 实际用
    private func currentDragPayload() -> PhotoDragItem? {
        isMarqueeActive ? nil : makeDragPayload()
    }

    private func makeDragPayload() -> PhotoDragItem {
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
    private var dragCount: Int {
        if selection.selectedIDs.contains(photo.id) {
            return selection.selectedIDs.count
        }
        return 1
    }

    /// V3.6.51: cell 选中视觉的单一 overlay
    @ViewBuilder
    private var cellSelectionOverlay: some View {
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
                    .background(Circle().fill(.background).padding(3))
                    .padding(6)
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
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if let nsImage = loadedImage {
                        // V5.34: .fit → .fill——回 Photos.app Library 真版
                        // V6.12.12: 砍 .square 模式后只剩 .squareFit——永远 .fit (letterbox 不裁切)
                        Image(nsImage: nsImage)
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
                    } else {
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fill)
                            .shimmer()
                    }
                }
                // V5.98: 选中 overlay 贴 image
                .overlay(cellSelectionOverlay)
                .animation(Animations.standard, value: selectionState)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // V6.12.7: cell 背景永远透明 (opacity 0), 避免「浅框」幽灵
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Surface.elevated)
                    .opacity(0)
            )
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
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PhotoCellContent.innerCellPadding)
        .frame(width: cellWidth, height: rowHeight)
        .clipped()
        // V3.6.51: 单一 .animation 驱动所有选中状态过渡
        .animation(Animations.springGentle, value: isFocused)
        .contentShape(Rectangle())  // 让空白处也响应点击
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .focused($isFocused)
        .focusable(true)
        .focusEffectDisabled(true)  // V4.4.6: 禁用系统 focus ring
        .help(tooltipText)
        // 拖拽：V6.17.2 改 currentDragPayload() — 圈选时返 nil (修视觉冲突)
        //   V3.6.33: 迁移到 .draggable(URL) 现代 API
        //   V3.6.34: capture @Model 属性到 local 避免 background thread 访问
        //   V5.39.7: 改 .draggable(PhotoDragItem) — Finder 导出 + in-app 重排共用
        .draggable(currentDragPayload() ?? makeDragPayload()) {
            // 拖动预览: 96pt 缩略图 + 阴影 + accent 描边 (V3.6.42 "被拿起"感)
            // V3.7.2: 多选时 preview 加 "共 N 张" badge
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .fill(Palette.cellBackground)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.thumb)
                                .strokeBorder(Surface.accentEmphasis, lineWidth: 1.5)
                        )
                    if let nsImage = capturedPreviewImage {
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
                    Text("共 \(dragCount) 张")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .rotationEffect(.degrees(1))
        }
        // V5.39.7: 拖入重排 — dropDestination 常驻, 仅 customOrder 模式接受 drop
        .dropDestination(for: PhotoDragItem.self) { items, _ in
            guard sortOption == .customOrder else { return false }
            guard let draggedItem = items.first else { return false }
            guard draggedItem.photoID != photo.id else { return false }
            handleReorderDrop(draggedID: draggedItem.photoID)
            return true
        }
        // V3.6.37: 抽 contextMenu 到独立 view (类型检查)
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
            showingDeleteConfirm: $showingDeleteConfirm,
            onDelete: onDelete,
            // V6.22.1 (P2 #2): 旋转闭包 — 转发到 CellContextMenuModifier
            //   Cell 自身不持有 model, 走 context 调用 PhotoCellContent → ContentView → model
            //   ContentView 在 cell 上挂 onRotateLeft/Right (跟 onDelete 同 pattern)
            onRotateLeft: onRotateLeft,
            onRotateRight: onRotateRight
        ))
        .confirmationDialog(
            Copy.deleteConfirmTitle,
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(Copy.delete, role: .destructive) {
                onDelete()
            }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(Copy.deletePhotoConfirm)
        }
    }

    // MARK: - V5.19/27/6.12.8/11/6.12.12: 内 cell padding (4pt, Photos 真版)
    //   之前 2pt → 4pt: .square 模式 image 圆角 + 选中框 visibility 改善
    static let innerCellPadding: CGFloat = 4
}

// MARK: - V6.17.2: nested types 提升到 file-scope (供 PhotoCellContent 引用)
//   之前 nested in PhotoThumbnailView, 跨 sub-view 不行

/// V4.1.0: 剩余天数 badge 颜色 (V3.6.51 重构后)
struct BadgeColor {
    let foreground: Color
    let background: Color
}

/// V3.6.51: 重构——选中状态机 (V5.17 border=0 → V5.26 1.5pt → V5.27 0 → V5.28 1.5pt → V5.99.2 3pt)
enum CellSelectionState {
    case none
    case single
    case multi

    /// V5.99.2: 3pt 跟 macOS Photos 真版接近, 4 边都明显
    var borderWidth: CGFloat {
        switch self {
        case .none:   return 0
        case .single: return 3
        case .multi:  return 3
        }
    }

    /// V5.99.2: 0.15/0.22 — 深色图片选中态可见
    var tintOpacity: Double {
        switch self {
        case .none:   return 0
        case .single: return 0.15
        case .multi:  return 0.22
        }
    }

    var showsCheckmark: Bool {
        self == .multi
    }
}

// MARK: - PhotoThumbnailView 公开 API (退化为 17 行纯转发)
//   V6.17.2: 之前 800 行 (含 377 行 body), 现在 body 退化为 1 行转发
//   保留所有 stored properties + @Binding (call site 兼容) + 4 个 @Environment
//   V5.28 dead state (currentScale) 已删
struct PhotoThumbnailView: View {
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
    let onDelete: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    // V6.22.1 (P2 #2): 旋转闭包 — ContentView 传 { model.rotateSelected(clockwise:) }
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    // V6.17.2: 之前 line 64-67 注释 "V6.17.2 留" 已实现, @Environment 加在 sub-view
    //   wrapper 不需要 isMarqueeActive (它不消费, 只是转发)

    var body: some View {
        PhotoCellContent(
            photo: photo,
            isInMultiSelect: isInMultiSelect,
            isActive: isActive,
            selection: selection,
            folders: folders,
            allTags: allTags,
            cellWidth: cellWidth,
            rowHeight: rowHeight,
            retentionDays: retentionDays,
            layoutMode: layoutMode,
            sortOption: sortOption,
            onReorder: onReorder,
            onDelete: onDelete,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            // V6.22.1 (P2 #2): 旋转闭包 (cell 自己没 model, 转发到 caller)
            onRotateLeft: onRotateLeft,
            onRotateRight: onRotateRight
        )
    }
}
