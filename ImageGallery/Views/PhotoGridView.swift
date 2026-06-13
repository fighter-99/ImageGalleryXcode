//
//  PhotoGridView.swift
//  ImageGallery
//
//  中间主显示区。展示图片网格, 支持:
//  - 按文件夹/标签/收藏/待整理/重复图 筛选
//  - 按文件名/标签名/笔记搜索
//  - 瀑布流布局: 每张图按原始宽高比显示
//  - 删除图片 (右键 / 选中后 Delete 键)
//  - 多选: 单击/⌘+点击/⇧+点击/⌘+A
//
//  V3.6.52: 重构选中状态——3 Binding 合并为 1 Binding<SelectionState>
//  V5.29: 拆出 4 个 view (PhotoGridEmptyState/LoadingState/RowView/LayoutView)
//    - 838 行 → ~250 行 (仅保留调度 + 状态管理)
//    - layout 算法用 GridLayout.computeRows (model 层, 纯函数)
//    - cell 渲染用 PhotoRowView (单行, 接收 GridRow)
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

    // 视图模式 (启动记忆)
    @AppStorage("viewModeRaw") private var viewModeRaw: String = ViewMode.grid.rawValue
    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .grid }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    // 双向绑定
    // V3.6.52: 3 个绑定合并为 1 个 SelectionState binding——单一真相源
    @Binding var selection: SelectionState

    // 筛选条件
    let folder: Folder?
    let tag: Tag?
    let searchText: String
    // V5.8: 砍 filterFavorites——V5.7 砍 .favorites 侧边栏后 dead
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    // V3.6 NEW: 回收站筛选
    let filterInTrash: Bool
    // V4.36.x: 工具栏筛选按钮 4 维 (透传到 PhotoStats.filtered)
    let selectedFolderIDs: Set<UUID>
    let selectedTagIDs: Set<UUID>
    let selectedShapes: Set<PhotoShape>
    let filterMinRating: Int
    // V4.36.x: 工具栏筛选激活标记 (空态文案感知)
    var isFilterActive: Bool {
        !selectedFolderIDs.isEmpty || !selectedTagIDs.isEmpty
            || !selectedShapes.isEmpty || filterMinRating > 0
    }
    // V3.6.6: 保留时长 (用于缩略图剩余天数 badge)
    let retentionDays: Int
    let thumbnailSize: CGFloat
    // V5.17: 缩略图布局模式 (3 选项)—— 由 ContentView.layoutMode 透传
    //   决定 MasonryMath 的 uniformWidth / stretchLastRow 二元组
    let layoutMode: ThumbnailLayoutMode
    let sortOption: SortOption

    // 通知父视图
    let onVisiblePhotosChange: ([Photo]) -> Void
    let onImport: () -> Void
    let onBatchDelete: () -> Void
    let onClearMultiSelect: () -> Void
    let onDoubleTap: (Photo) -> Void
    // V4.9.0: 清空所有 filter (searchText + folder + tag + 所有 filter 状态)
    //   用于"无搜索结果"和"空 folder/tag"等空状态次 CTA——"查看全部"
    let onClearFilters: () -> Void
    // V4.9.3: 加载中状态 (导入时 brief 闪烁——主 grid 显示 Shimmer 占位)
    let isImporting: Bool = false
    // 必须在最末尾 (Swift init 顺序要求)
    let onExportComplete: (Int) -> Void

    // ─── 综合筛选 ───
    // V3.6.5: 从 computed property 改为 @State 缓存 + filterSignature 失效
    @State private var photos: [Photo] = []

    /// 全部 filter inputs 的 hash 签名
    /// 任何一个变化都触发 recomputePhotos (避免 N 个 onChange)
    /// 注意: 只用 allPhotos.count 而非 allPhotos 本身, 避免大数组 hash
    private var filterSignature: Int {
        var hasher = Hasher()
        hasher.combine(allPhotos.count)
        hasher.combine(allPhotos.first?.id)  // 引用变化 proxy
        hasher.combine(folder?.id)
        hasher.combine(tag?.id)
        hasher.combine(searchText)
        hasher.combine(sortOption)
        hasher.combine(filterUnfiled)
        hasher.combine(filterDuplicates)
        hasher.combine(filterRecent7Days)
        hasher.combine(filterLargeFiles)
        hasher.combine(filterInTrash)
        // V4.36.x: 工具栏筛选 4 维 (Set 有标准 Hashable; 任一变化触发重算)
        hasher.combine(selectedFolderIDs)
        hasher.combine(selectedTagIDs)
        hasher.combine(selectedShapes)
        hasher.combine(filterMinRating)
        return hasher.finalize()
    }

    private func recomputePhotos() {
        // V4.36.6: 抽到 PhotoStats.filtered static helper——List/Timeline 视图共用
        photos = PhotoStats.filtered(
            allPhotos,
            folder: folder,
            tag: tag,
            searchText: searchText,
            sortOption: sortOption,
            // V5.8: 砍 filterFavorites
            filterUnfiled: filterUnfiled,
            filterDuplicates: filterDuplicates,
            filterRecent7Days: filterRecent7Days,
            filterLargeFiles: filterLargeFiles,
            filterInTrash: filterInTrash,
            selectedFolderIDs: selectedFolderIDs,
            selectedTagIDs: selectedTagIDs,
            selectedShapes: selectedShapes,
            minRating: filterMinRating
        )
    }

    // 多选模式
    // V3.6.52: 原 isMultiSelect (count > 0) 改名为 hasSelection
    //   与 ContentView 的 isMultiSelect (count > 1) 区分——前者供空状态抑制用,
    //   后者供 DetailPane 切换布局用
    private var hasSelection: Bool { selection.hasSelection }

    var body: some View {
        VStack(spacing: 0) {
            // V4.9.3: 加载中优先于空状态 (导入时 brief Shimmer)
            if isImporting {
                PhotoGridLoadingState(thumbnailSize: thumbnailSize)
                    .transition(.opacity)
            } else if photos.isEmpty && !hasSelection {
                PhotoGridEmptyState(
                    searchText: searchText,
                    folder: folder,
                    tag: tag,
                    filterUnfiled: filterUnfiled,
                    filterDuplicates: filterDuplicates,
                    filterRecent7Days: filterRecent7Days,
                    filterLargeFiles: filterLargeFiles,
                    filterInTrash: filterInTrash,
                    isFilterActive: isFilterActive,
                    onImport: onImport,
                    onClearFilters: onClearFilters
                )
                .transition(.opacity)
            } else {
                contentView
                    .transition(.opacity)
            }
        }
        // V3.6.39: 触发视图模式切换的 transition 动画
        .animation(Animations.medium, value: viewMode)
        // V3.6.43: 触发空状态切换的 transition 动画
        .animation(Animations.medium, value: photos.isEmpty && !hasSelection)
        // V4.9.3: 触发 loading 状态切换的 transition 动画
        .animation(Animations.quick, value: isImporting)
        .navigationTitle(navigationTitle)
        .onAppear {
            // V3.6.5: 首次出现时算一次 photos
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
        // V3.6.5: filterSignature 变化时 (任一 filter input) 触发重算 + 通知父视图
        .onChange(of: filterSignature) { _, _ in
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
    }

    private var navigationTitle: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "搜索: \(trimmed)" }
        if let folder = folder { return folder.name }
        if let tag = tag { return "#\(tag.name)" }
        // V5.8: 砍"收藏"——侧边栏无收藏入口
        if filterUnfiled { return "待整理" }
        if filterDuplicates { return "重复图" }
        if filterRecent7Days { return "最近 7 天" }
        if filterLargeFiles { return "大图(>5MB)" }
        if filterInTrash { return "回收站" }  // V4.36.x: 统一为"回收站"
        return "全部"
    }

    // ─── 根据视图模式切换 ───
    // V3.6.39: 加 .transition(.opacity) + .animation 让模式切换平滑
    // V5.23: 加 top fade gradient (macOS Photos 风格)
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            photoGrid
                // V5.25: 平滑密度切换动画——spring animation 在 thumbnailSize 变化时
                //   spring response 0.3 + damping 0.8: 快速但不"弹"
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: thumbnailSize)
                .overlay(alignment: .top) {
                    // V5.23: top fade gradient——24pt 高度
                    LinearGradient(
                        colors: [Color.clear, Color(nsColor: .windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                    .allowsHitTesting(false)
                }
                .transition(.opacity)
        case .list:
            PhotoListView(
                photos: photos,
                selection: selection,
                onTap: handleTap,
                onDoubleTap: onDoubleTap
            )
            .transition(.opacity)
        case .timeline:
            PhotoTimelineView(
                photos: photos,
                selection: selection,
                onTap: handleTap,
                onDoubleTap: onDoubleTap
            )
            .transition(.opacity)
        }
    }

    // ─── 图片网格 ───
    // V5.16: masonry 重构——Photos.app "Aspect Ratio" 视图风格
    //   - 行内 cell 高度统一 = rowHeight (thumbnailSize)
    //   - cell 宽度 = rowHeight × photo.aspectRatio (变宽)
    //   - 行 reflow: MasonryMath.groupIntoRows 算好每行 cell 列表
    //   - LazyVStack of MasonryRow (每行 HStack 固定高)
    // V5.29: 接入 GridLayout.computeRows (model 层纯函数)
    @ViewBuilder
    private var photoGrid: some View {
        GeometryReader { geo in
            // V5.16: 减左右 padding (24pt) 拿真可用宽
            let availableWidth = geo.size.width - 2 * Spacing.md
            let rowHeight: CGFloat = thumbnailSize  // 缩略图大小 = 行高
            // V5.19: rowSpacing 8pt → 16pt, cellSpacing 12pt → 20pt
            // V5.27: 20pt → 8pt, 16pt → 8pt——macOS Photos Library 节奏
            let rowSpacing: CGFloat = Spacing.sm     // 8pt
            let cellSpacing: CGFloat = 8

            // V4.37.1: 条件分支——isDateBased 时按日期分组, 否则平铺
            Group {
                if sortOption.isDateBased {
                    masonryDateGroupedLayout(
                        availableWidth: availableWidth,
                        rowHeight: rowHeight,
                        rowSpacing: rowSpacing,
                        cellSpacing: cellSpacing
                    )
                } else {
                    masonryFlatLayout(
                        availableWidth: availableWidth,
                        rowHeight: rowHeight,
                        rowSpacing: rowSpacing,
                        cellSpacing: cellSpacing
                    )
                }
            }
        }
    }

    // V5.16: masonry 日期分组布局
    // V5.23: sticky date header——用 Section + pinnedViews: [.sectionHeaders]
    @ViewBuilder
    private func masonryDateGroupedLayout(
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat
    ) -> some View {
        let groups = PhotoStats.groupByDate(photos)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        masonryRowsView(
                            photos: group.photos,
                            availableWidth: availableWidth,
                            rowHeight: rowHeight,
                            rowSpacing: rowSpacing,
                            cellSpacing: cellSpacing,
                            // V5.18: 日期分组视图显示拍摄日期 caption
                            // V5.25: 改为 layoutMode != .square——.square (Library 视图) 无 caption
                            showDateCaption: layoutMode != .square
                        )
                    } header: {
                        DateSectionHeader(label: group.label, count: group.photos.count)
                    }
                }
            }
            .padding()
            .animation(Animations.medium, value: photos.count)
        }
    }

    // V5.16: masonry 平铺布局 (filename/size/custom 排序时用)
    @ViewBuilder
    private func masonryFlatLayout(
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masonryRowsView(
                    photos: photos,
                    availableWidth: availableWidth,
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    cellSpacing: cellSpacing,
                    // V5.18: 平铺视图无日期 header 也无 caption
                    showDateCaption: false
                )
            }
            .padding()
            .animation(Animations.medium, value: photos.count)
        }
    }

    // V5.29: masonryRowsView 接入 GridLayout (纯函数) + PhotoGridLayoutView (渲染)
    //   - 之前: 80 行 (内嵌 groupIntoRows + LazyVStack + MasonryRowView 调用)
    //   - 现在: 20 行 (GridLayout + PhotoGridLayoutView)
    @ViewBuilder
    private func masonryRowsView(
        photos: [Photo],
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat,
        // V5.18: date caption 开关
        showDateCaption: Bool
    ) -> some View {
        let layout = GridLayout(
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            cellSpacing: cellSpacing,
            layoutMode: layoutMode
        )
        let rows = layout.computeRows(from: photos)
        ScrollView {
            PhotoGridLayoutView(
                rows: rows,
                rowSpacing: rowSpacing,
                cellSpacing: cellSpacing,
                showDateCaption: showDateCaption,
                photos: photos,
                selection: selection,
                folders: folders,
                allTags: allTags,
                retentionDays: retentionDays,
                onDelete: deletePhoto,
                onTap: handleTap,
                onDoubleTap: onDoubleTap
            )
            .padding()
        }
    }

    // ─── 处理点击 (V3.6.30: 抽成 MultiSelectMath.handleTap 纯函数 thin wrapper) ───
    private func handleTap(_ photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        let modifier: ClickModifier = {
            if modifiers.contains(.command) { return .command }
            if modifiers.contains(.shift) { return .shift }
            return .plain
        }()
        // V3.6.52: 直接传当前 selection, 不再手工 destructure 3 个字段
        let photoIDs = photos.map { $0.id }
        let outcome = MultiSelectMath.handleTap(
            state: selection,
            photoID: photo.id,
            modifier: modifier,
            photoIDs: photoIDs
        )
        applyTapOutcome(outcome)
    }

    // ─── 应用 TapOutcome 到 @State (V3.6.52: 从 7 行收成 4 行) ───
    private func applyTapOutcome(_ outcome: TapOutcome) {
        switch outcome {
        case .singleSelect(let s), .toggleMultiSelect(let s), .rangeSelect(let s):
            selection = s
        }
    }

    // ─── 删除 (V3.6: 走 RecycleBinService.recycle, 移到回收站) ───
    private func deletePhoto(_ photo: Photo) {
        RecycleBinService(storage: .shared, modelContext: modelContext).recycle(photo)
        selection = selection.removing(photo.id)
    }

    // MARK: - 拖拽重排数学 (V3.5.D P3: 纯函数, 便于单测)

    /// 计算拖拽重排的最终 source 集合和校正后的 destination。
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

        // Step 2: 校正 destination (左移 sources 中 < dest 的项数)
        let sourcesBeforeDest = allSources.filter { $0 < destination }.count
        var adjustedDest = destination - sourcesBeforeDest

        // Step 3: Clamp 到合法范围 [0, photoCount - allSources.count]
        let maxDest = max(0, photoCount - allSources.count)
        adjustedDest = min(max(0, adjustedDest), maxDest)

        return (allSources, adjustedDest)
    }
}

#Preview {
    PhotoGridView(
        selection: .constant(SelectionState()),
        folder: nil,
        tag: nil,
        searchText: "",
        filterUnfiled: false,
        filterDuplicates: false,
        filterRecent7Days: false,
        filterLargeFiles: false,
        filterInTrash: false,
        selectedFolderIDs: [],
        selectedTagIDs: [],
        selectedShapes: [],
        filterMinRating: 0,
        retentionDays: 30,
        thumbnailSize: 170,
        layoutMode: .masonryStretch,
        sortOption: .importedAtDesc,
        onVisiblePhotosChange: { _ in },
        onImport: {},
        onBatchDelete: {},
        onClearMultiSelect: {},
        onDoubleTap: { _ in },
        onClearFilters: {},
        onExportComplete: { _ in }
    )
    .frame(width: 600, height: 400)
}
