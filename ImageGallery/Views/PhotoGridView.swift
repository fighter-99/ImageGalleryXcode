//
//  PhotoGridView.swift
//  ImageGallery
//
//  中间主显示区。展示图片网格，支持：
//  - 按文件夹/标签/收藏/待整理/重复图 筛选
//  - 按文件名/标签名/笔记搜索
//  - 瀑布流布局：每张图按原始宽高比显示
//  - 删除图片（右键 / 选中后 Delete 键）
//  - 多选：单击/⌘+点击/⇧+点击/⌘+A
//  - 顶部多选操作栏（已选 N 张 + 批量删除 + 取消）
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct PhotoGridView: View {
    // SwiftData
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.importedAt, order: .reverse) private var allPhotos: [Photo]
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]
    @Query(sort: \Tag.createdAt, order: .forward) private var allTags: [Tag]

    // 视图模式（启动记忆）
    @AppStorage("viewModeRaw") private var viewModeRaw: String = ViewMode.grid.rawValue
    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .grid }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    // 双向绑定
    @Binding var selectedPhoto: Photo?
    @Binding var selectedIDs: Set<UUID>
    @Binding var lastSelectedID: UUID?

    // 筛选条件
    let folder: Folder?
    let tag: Tag?
    let searchText: String
    let filterFavorites: Bool
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    // V3.6 NEW: 回收站筛选
    let filterInTrash: Bool
    // V3.6.6: 保留时长（用于缩略图剩余天数 badge）
    let retentionDays: Int
    let thumbnailSize: CGFloat
    let sortOption: SortOption

    // 通知父视图
    let onVisiblePhotosChange: ([Photo]) -> Void
    let onImport: () -> Void
    let onBatchDelete: () -> Void
    let onClearMultiSelect: () -> Void
    let onDoubleTap: (Photo) -> Void
    // 必须在最末尾（Swift init 顺序要求）
    let onExportComplete: (Int) -> Void

    // ─── 综合筛选 ───
    // V3.6.5：从 computed property 改为 @State 缓存 + filterSignature 失效
    // 原因：computed property 每次 body 求值都跑 9 遍 filter + 1 sort；且
    // `.onChange(of: photos)` 因为总是返回新数组（filter 链）会无限触发
    @State private var photos: [Photo] = []

    /// 全部 filter inputs 的 hash 签名
    /// 任何一个变化都触发 recomputePhotos（避免 N 个 onChange）
    /// 注意：只用 allPhotos.count 而非 allPhotos 本身，避免大数组 hash
    private var filterSignature: Int {
        var hasher = Hasher()
        hasher.combine(allPhotos.count)
        hasher.combine(allPhotos.first?.id)  // 引用变化 proxy
        hasher.combine(folder?.id)
        hasher.combine(tag?.id)
        hasher.combine(searchText)
        hasher.combine(sortOption)
        hasher.combine(filterFavorites)
        hasher.combine(filterUnfiled)
        hasher.combine(filterDuplicates)
        hasher.combine(filterRecent7Days)
        hasher.combine(filterLargeFiles)
        hasher.combine(filterInTrash)
        return hasher.finalize()
    }

    private func recomputePhotos() {
        var result = allPhotos

        if let folder = folder {
            result = result.filter { $0.folder?.id == folder.id }
        }
        if let tag = tag {
            result = result.filter { photo in photo.tags.contains { $0.id == tag.id } }
        }
        if filterFavorites {
            result = result.filter { $0.isFavorite }
        }
        if filterUnfiled {
            result = result.filter { $0.folder == nil }
        }
        if filterDuplicates {
            let hashCounts = Dictionary(grouping: allPhotos) { $0.fileHash }.mapValues { $0.count }
            result = result.filter { photo in
                guard let hash = photo.fileHash else { return false }
                return (hashCounts[hash] ?? 0) > 1
            }
        }
        // V2: 最近 7 天
        if filterRecent7Days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { $0.importedAt > cutoff }
        }
        // V2: 大图 > 5MB
        if filterLargeFiles {
            result = result.filter { $0.fileSize > 5_000_000 }
        }
        // V3.6: 回收站筛选（与 folder/tag 互斥——只有 .recentlyDeleted 时才进此分支）
        if filterInTrash {
            result = result.filter { $0.trashedAt != nil }
        } else {
            // 非回收站视图：永远排除已删项
            result = result.filter { $0.trashedAt == nil }
        }
        // V3.6.3：用 PhotoSearch 纯函数（含 folder.name 匹配，修复前只匹配 filename/note/tag）
        result = PhotoSearch.filter(result, query: searchText)
        // 排序（Eagle 化工具栏新增：覆盖 @Query 默认顺序）
        photos = sortOption.apply(to: result)
    }

    // ─── 列数 ───
    private var columnCount: Int {
        let t = thumbnailSize
        if t < 110 { return 5 }
        if t < 150 { return 4 }
        if t < 200 { return 3 }
        if t < 250 { return 3 }
        return 2
    }

    // 多选模式
    private var isMultiSelect: Bool { selectedIDs.count > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // V3.5.19：移除 multiSelectTopBar
            // 批量操作搬到详情面板的 MultiSelectDetailView 里了

            if photos.isEmpty && !isMultiSelect {
                emptyState
            } else {
                contentView
            }
        }
        .navigationTitle(navigationTitle)
        .onAppear {
            // V3.6.5：首次出现时算一次 photos（之前 photos 是 computed，每次 re-render 重算）
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
        // V3.6.5：filterSignature 变化时（任一 filter input）触发重算 + 通知父视图
        .onChange(of: filterSignature) { _, _ in
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
    }

    // （原 defaultTopBar 已删除：与系统顶栏的视图模式/导入按钮重复。
    //   Eagle 原则要求单一主工具栏。V3.0 工具栏优化时彻底合并。）


    // （原 titleText 已删除：与系统顶栏的 status "共 N 张" 重复信息。）

    private var navigationTitle: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "搜索：\(trimmed)" }
        if let folder = folder { return folder.name }
        if let tag = tag { return "#\(tag.name)" }
        if filterFavorites { return "收藏" }
        if filterUnfiled { return "待整理" }
        if filterDuplicates { return "重复图" }
        if filterRecent7Days { return "最近 7 天" }
        if filterLargeFiles { return "大图" }
        if filterInTrash { return "最近删除" }  // V3.6 NEW
        return "全部"
    }

    private var emptyState: some View {
        // V3.6.9：用统一 EmptyStateView 组件
        EmptyStateView(
            icon: emptyIcon,
            title: emptyText,
            subtitle: emptyHint,
            iconColor: Color.accentColor.opacity(0.6),
            action: emptyShowImport
                ? EmptyStateView.Action(
                    label: "导入图片",
                    systemImage: "square.and.arrow.down",
                    onTap: onImport
                )
                : nil
        )
    }

    private var emptyIcon: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "magnifyingglass" }
        if filterFavorites { return "star" }
        if filterUnfiled { return "tray" }
        if folder != nil { return "folder" }
        if tag != nil { return "tag" }
        if filterDuplicates { return "doc.on.doc" }
        if filterRecent7Days { return "clock.arrow.circlepath" }
        if filterLargeFiles { return "large.circle" }
        if filterInTrash { return "trash" }  // V3.6 NEW
        return "photo.on.rectangle.angled"
    }

    private var emptyText: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "没有匹配的图片" }
        if filterFavorites { return "还没有收藏的图片" }
        if filterUnfiled { return "没有待整理的图片" }
        if folder != nil { return "这个文件夹是空的" }
        if tag != nil { return "没有带此标签的图片" }
        if filterDuplicates { return "没有重复的图片" }
        if filterRecent7Days { return "最近 7 天没有新图" }
        if filterLargeFiles { return "没有大于 5MB 的图" }
        if filterInTrash { return "回收站是空的" }  // V3.6 NEW
        return "还没有图片"
    }

    private var emptyHint: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "试试其他关键词" }
        if filterFavorites { return "在图片详情中点击 ⭐ 收藏" }
        if filterUnfiled { return "把图片移动到文件夹来整理" }
        if folder != nil { return "导入图片后会自动放到此文件夹" }
        if tag != nil { return "在图片详情中添加此标签" }
        if filterDuplicates { return "重复图会自动出现在这里" }
        if filterInTrash { return "删除的图片会出现在这里，\(TrashRetentionDays.defaultValue.rawValue) 天后自动永久清除" }  // V3.6 NEW
        return "拖入图片，或点击\"导入图片\"开始添加"
    }

    private var emptyShowImport: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty && !filterFavorites && !filterUnfiled
            && folder == nil && tag == nil && !filterDuplicates
            && !filterInTrash  // V3.6 NEW: 回收站空状态不显示导入按钮
    }

    // ─── 根据视图模式切换 ───
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            photoGrid
        case .list:
            PhotoListView(
                photos: photos,
                selectedIDs: selectedIDs,
                singleSelectedID: singleSelectedID,
                onTap: handleTap,
                onDoubleTap: onDoubleTap
            )
        case .timeline:
            PhotoTimelineView(
                photos: photos,
                selectedIDs: selectedIDs,
                singleSelectedID: singleSelectedID,
                onTap: handleTap,
                onDoubleTap: onDoubleTap
            )
        }
    }

    // ─── 图片网格 ───
    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 60), spacing: 8),
                    count: columnCount
                ),
                spacing: 8
            ) {
                ForEach(photos) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        isInMultiSelect: selectedIDs.contains(photo.id),
                        isActive: singleSelectedID == photo.id,
                        folders: folders,
                        allTags: allTags,
                        cellHeight: thumbnailSize,
                        // V3.6.6: 传 retentionDays（用于显示剩余天数 badge）
                        retentionDays: retentionDays,
                        onDelete: { deletePhoto(photo) },
                        onTap: { handleTap(photo) },
                        onDoubleTap: { onDoubleTap(photo) }
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.6).combined(with: .opacity)
                    ))
                }
            }
            .padding()
            .animation(Animations.medium, value: photos.count)
        }
    }

    // 当前单选 ID（用于蓝色边框）
    private var singleSelectedID: UUID? {
        selectedIDs.count <= 1 ? (selectedIDs.first ?? selectedPhoto?.id) : nil
    }

    // ─── 处理点击 ───
    private func handleTap(_ photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            // ⌘+点击：toggle 多选
            if selectedIDs.contains(photo.id) {
                selectedIDs.remove(photo.id)
            } else {
                selectedIDs.insert(photo.id)
            }
            lastSelectedID = photo.id
            // ⌘+点击不改变 selectedPhoto
        } else if modifiers.contains(.shift) {
            // ⇧+点击：范围选择
            rangeSelect(to: photo.id)
            selectedPhoto = nil
        } else {
            // 普通单击：单选 + 清空多选
            selectedIDs = [photo.id]
            selectedPhoto = photo
            lastSelectedID = photo.id
        }
    }

    // ─── 范围选择 ───
    private func rangeSelect(to id: UUID) {
        guard let lastID = lastSelectedID,
              let lastIdx = photos.firstIndex(where: { $0.id == lastID }),
              let currentIdx = photos.firstIndex(where: { $0.id == id }) else {
            selectedIDs = [id]
            lastSelectedID = id
            return
        }
        let lower = min(lastIdx, currentIdx)
        let upper = max(lastIdx, currentIdx)
        let range = photos[lower...upper]
        selectedIDs = Set(range.map { $0.id })
        lastSelectedID = id
    }

    // ─── 删除（V3.6：走 RecycleBinService.recycle，移到回收站）───
    private func deletePhoto(_ photo: Photo) {
        RecycleBinService(storage: .shared, modelContext: modelContext).recycle(photo)
        selectedIDs.remove(photo.id)
        if selectedPhoto?.id == photo.id {
            selectedPhoto = nil
        }
    }


    // MARK: - 拖拽重排数学（V3.5.D P3：纯函数，便于单测）

    /// 计算拖拽重排的最终 source 集合和校正后的 destination。
    ///
    /// 行为：
    /// - 如果 `source` 恰好 1 项且被选中，**且还有其他选中项**，则展开为整组选中一起拖
    /// - 如果 `source` 恰好 1 项且被选中，**但没有其他选中项**（只有自己），则保持单张
    /// - 其他情况保持 `source` 不变
    ///
    /// destination 校正：SwiftUI 给的是原数组的下标，移除 source 之后下标会左移。
    /// `adjustedDest = destination - (sources 中 < destination 的数量)`，最后 clamp 到 `[0, photoCount - allSources.count]`
    ///
    /// - Parameters:
    ///   - photoCount: 网格里总图片数
    ///   - source: SwiftUI 传入的拖拽 source 索引集合
    ///   - destination: SwiftUI 传入的目标位置（基于原数组坐标系）
    ///   - isPhotoSelectedAt: 给定索引的图片是否被选中（用于多选展开判断）
    /// - Returns: `(allSources, adjustedDest)`
    static func computeDragReorder(
        photoCount: Int,
        source: IndexSet,
        destination: Int,
        isPhotoSelectedAt: (Int) -> Bool
    ) -> (allSources: IndexSet, adjustedDest: Int) {
        // Step 1: 决定实际要拖的 source 集合
        let allSources: IndexSet
        if source.count == 1, let draggedIndex = source.first, isPhotoSelectedAt(draggedIndex) {
            // 拖动的是某个被选中的项——检查是否还有其他选中项
            let allSelectedIndices = (0..<photoCount).filter { isPhotoSelectedAt($0) }
            if allSelectedIndices.count > 1 {
                allSources = IndexSet(allSelectedIndices)
            } else {
                allSources = source
            }
        } else {
            allSources = source
        }

        // Step 2: 校正 destination（左移 sources 中 < dest 的项数）
        let sourcesBeforeDest = allSources.filter { $0 < destination }.count
        var adjustedDest = destination - sourcesBeforeDest

        // Step 3: Clamp 到合法范围 [0, photoCount - allSources.count]
        let maxDest = max(0, photoCount - allSources.count)
        adjustedDest = min(max(0, adjustedDest), maxDest)

        return (allSources, adjustedDest)
    }
}

// ─── 单个缩略图 ───
struct PhotoThumbnailView: View {
    let photo: Photo
    let isInMultiSelect: Bool  // 是否在多选集合中
    let isActive: Bool          // 是否是当前单选激活（蓝色边框）
    let folders: [Folder]
    let allTags: [Tag]
    let cellHeight: CGFloat
    // V3.6.6: 保留时长（用于显示 trash 视图下的剩余天数 badge）
    let retentionDays: Int
    let onDelete: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme  // V3.6.14: 暗色适配 trash opacity
    @State private var showingDeleteConfirm = false
    @State private var isHovered = false
    // V3.6.10: 按压反馈（@GestureState 在 gesture 结束时自动 reset）
    @GestureState private var isPressed: Bool = false
    // V3.6.10: 键盘聚焦状态（SwiftUI 默认 focus ring，但 macOS 上系统不显示时手动加）
    @FocusState private var isFocused: Bool
    // V3.6.26: 异步缩略图加载状态（避免主线程阻塞）
    @State private var loadedImage: NSImage?

    /// V3.6.6: 距离永久删除的剩余天数（nil = 未在回收站）
    private var daysLeft: Int? {
        PhotoStats.daysUntilPurge(trashedAt: photo.trashedAt, retentionDays: retentionDays)
    }

    /// V3.6.10: 缩略图 hover 时显示的 tooltip（文件名 + 尺寸 + 文件大小）
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

    /// V3.6.10: 当前缩放比例（按压 > 选中 > hover > 默认）
    private var currentScale: CGFloat {
        if isPressed { return 0.95 }              // 按下：缩 5%
        if isActive { return 1.015 }              // 单选：轻微放大
        if isHovered && !isInMultiSelect { return 1.02 }  // hover：放大 2%
        return 1.0
    }

    private var aspectRatio: CGFloat {
        if photo.width > 0 && photo.height > 0 {
            return CGFloat(photo.width) / CGFloat(photo.height)
        }
        return 1.0
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 图片（垂直居中 + 按原比例）
            // V3.6.8: trash 视图下加灰度 + 降低不透明度，让"已删除"感更强
            // V3.6.14: 暗色下 opacity 0.65（暗背景下半透明不会"黑掉"）
            // V3.6.26: 改用 .task + 异步加载，主线程不阻塞
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if let nsImage = loadedImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .saturation(photo.isInTrash ? 0.05 : 1)
                            .opacity(photo.isInTrash ? (colorScheme == .dark ? 0.65 : 0.55) : 1)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(Palette.cellEmpty)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // V3.6.26: 异步加载缩略图（缓存命中立即返回；未命中后台线程解码）
            // .task 在 view 出现时触发，photo.id 变化时重新加载
            .task(id: photo.id) {
                loadedImage = await ImageLoader.loadImageAsync(
                    at: photo.fileURL,
                    maxPixelSize: 600
                )
            }

            // 多选蒙层
            if isInMultiSelect {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Palette.selectionOverlayMulti)
            }

            // 收藏星标
            if photo.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
            }

            // V3.6.6: 回收站剩余天数 badge（仅 trash 视图下显示）
            // topLeading 不与右上角的多选 ✓ / 左上角的 star 冲突
            if let days = daysLeft, photo.isInTrash {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(days)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(days <= 3 ? .white : .primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        days <= 3
                        ? Color.orange
                        : Color(nsColor: .controlBackgroundColor).opacity(0.9)
                    )
                )
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // 多选 ✓ 圆点
            if isInMultiSelect {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(
                        Circle().fill(.background).padding(3)
                    )
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background(Palette.cellBackground)
        .cornerRadius(Radius.md)
        .clipped()
        // V3.1：1pt 微妙边框（暗色下也能看清缩略图边界）
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Surface.cardBorder, lineWidth: 1)
        }
        // 边框：单选激活显示蓝色边框（V3.1：4pt → 3pt，更克制）
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    isActive ? Palette.selectionBorder : Color.clear,
                    lineWidth: isActive ? 3 : 0
                )
        }
        // 多选选中显示蓝色蒙层 + 边框
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(
                    isInMultiSelect ? Palette.selectionBorder : Color.clear,
                    lineWidth: isInMultiSelect ? 2 : 0
                )
        }
        // V3.6.10: 按压 scale (0.95) > 选中 (1.015) > hover (1.02) > 默认
        // 优先级：isPressed > isActive > isHovered
        .scaleEffect(currentScale)
        // V3.1：用 Elevation 阴影系统
        //   resting：subtle（始终有微弱阴影，浮起感）
        //   hover：strong（明显浮起）
        .shadow(
            color: isHovered ? Elevation.strong.color : Elevation.subtle.color,
            radius: isHovered ? Elevation.strong.radius : Elevation.subtle.radius,
            x: 0,
            y: isHovered ? Elevation.strong.y : Elevation.subtle.y
        )
        .animation(Animations.standard, value: isActive)
        .animation(Animations.standard, value: isHovered)
        .animation(Animations.press, value: isPressed)
        .animation(Animations.quick, value: isInMultiSelect)
        .animation(Animations.quick, value: isFocused)
        // hover 检测（仅用于缩放动画）
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())  // 让空白处也响应点击
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        // V3.6.10: 按压检测（DragGesture(minimumDistance: 0) + @GestureState）
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
        // V3.6.10: 键盘聚焦绑定（方向键导航时高亮）
        .focused($isFocused)
        .focusable(true)
        .focusEffectDisabled(false)  // 启用 macOS 系统 focus ring
        // V3.6.10: hover tooltip（文件名 + 尺寸 + 文件大小）
        .help(tooltipText)
        // 拖拽：支持内部文件夹移动（V3.5.20 修复崩溃）
        .onDrag {
            let provider = NSItemProvider()

            // V3.5.19 修复 NSException：
            // 1. 提前捕获所有值（photo 是 SwiftData @Model，deferred 访问失效对象会崩）
            // 2. 用 registerDataRepresentation 替代 registerObject
            //    （registerObject 提供对象，loadDataRepresentation 要数据，两者不兼容会抛 NSException）
            //
            // V3.5.20 修复：删除 registerFileRepresentation
            // 原因：.openInPlace 模式下系统会在 drop 时主动访问文件，文件不可访问时崩溃
            // 现在只注册 "public.text" UUID 数据供 Sidebar 文件夹 drop 使用
            // Finder 导出改用 context menu "导出" 按钮（如未来需要再加）
            let photoUUID = photo.id.uuidString
            let uuidData = photoUUID.data(using: .utf8) ?? Data()

            // UUID 数据（Sidebar 文件夹接收 → 移动到文件夹）
            // 跟 SidebarView 的 loadDataRepresentation(forTypeIdentifier: "public.text") 匹配
            provider.registerDataRepresentation(
                forTypeIdentifier: "public.text",
                visibility: .all
            ) { completion in
                completion(uuidData, nil)
                return Progress()
            }

            return provider
        }
        .contextMenu {
            Menu {
                Button {
                    photo.folder = nil
                    try? modelContext.save()
                } label: {
                    Label("移出文件夹", systemImage: "tray")
                }
                if !folders.isEmpty {
                    Divider()
                }
                ForEach(folders) { folder in
                    Button {
                        photo.folder = folder
                        try? modelContext.save()
                    } label: {
                        if photo.folder?.id == folder.id {
                            Label(folder.name, systemImage: "checkmark")
                        } else {
                            Text(folder.name)
                        }
                    }
                }
            } label: {
                Label("移动到文件夹", systemImage: "folder")
            }

            Menu {
                ForEach(allTags) { tag in
                    Button {
                        toggleTag(tag, on: photo)
                    } label: {
                        if photo.tags.contains(where: { $0.id == tag.id }) {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
            } label: {
                Label("管理标签", systemImage: "tag")
            }

            Divider()

            Button {
                photo.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(
                    photo.isFavorite ? "取消收藏" : "收藏",
                    systemImage: photo.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "确定要删除这张图片吗？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("图片将从图库中移除，文件也会被永久删除。")
        }
    }

    private func toggleTag(_ tag: Tag, on photo: Photo) {
        if let index = photo.tags.firstIndex(where: { $0.id == tag.id }) {
            photo.tags.remove(at: index)
        } else {
            photo.tags.append(tag)
        }
        try? modelContext.save()
    }
}

#Preview {
    PhotoGridView(
        selectedPhoto: .constant(nil),
        selectedIDs: .constant([]),
        lastSelectedID: .constant(nil),
        folder: nil,
        tag: nil,
        searchText: "",
        filterFavorites: false,
        filterUnfiled: false,
        filterDuplicates: false,
        filterRecent7Days: false,
        filterLargeFiles: false,
        filterInTrash: false,
        retentionDays: 30,  // V3.6.6
        thumbnailSize: 170,
        sortOption: .importedAtDesc,
        onVisiblePhotosChange: { _ in },
        onImport: {},
        onBatchDelete: {},
        onClearMultiSelect: {},
        onDoubleTap: { _ in },
        onExportComplete: { _ in }
    )
    .frame(width: 600, height: 400)
}
