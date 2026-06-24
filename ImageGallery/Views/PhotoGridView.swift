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
    // V6.17.0: 矩形圈选 state — 移到 PhotoGridView 内部 (cell frames 在 grid-local 坐标,
    //   gesture 跟 cell frames 同一坐标系才能 hit test)
    @Binding var isMarqueeActive: Bool
    @Binding var marqueeRect: CGRect?

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
    @Binding var thumbnailSize: CGFloat
    // V5.17: 缩略图布局模式 (3 选项)—— 由 ContentView.layoutMode 透传
    //   决定 MasonryMath 的 uniformWidth / stretchLastRow 二元组
    let layoutMode: ThumbnailLayoutMode
    let sortOption: SortOption

    // V5.60-6: 初始滚动位置 anchor (从 ContentView 传入)
    //   启动 onAppear 读这个值, 设给 @State scrollAnchorID
    //   触发 .scrollPosition(id:) 自动 scrollTo
    let scrollAnchorPhotoID: String?
    // V5.61-1: 滚动位置变化时回调——写回 model.scrollAnchorPhotoID (UserDefaults 持久化)
    //   PhotoGridView 无 model 引用, 通过 closure 透传
    let onScrollAnchorChange: (String) -> Void

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
    // V5.39.7 NEW: 重排回调 (customOrder 拖拽重排后调, 触发 recomputePhotos 重算 grid)
    let onReorder: () -> Void
    // V6.22.1 (P2 #2): 旋转回调 — caller (ContentView) 传 model.rotateSelected closure
    let onRotate: (Photo, Bool) -> Void
    // V6.94.1 (P0 #3): 标注回调 — caller (ContentView) 传 NotificationCenter.post(.markupRequested) closure
    let onMarkup: () -> Void
    // V6.97.1 (P0 #5): 裁剪回调 — caller 透传同 onMarkup
    let onCrop: (Photo) -> Void
    // V6.97.1.1 (Bug fix C3): isSingle — 单选 gate, 多选 disable 裁剪... button
    let isSingle: Bool

    // ─── 综合筛选 ───
    // V3.6.5: 从 computed property 改为 @State 缓存 + filterSignature 失效
    @State private var photos: [Photo] = []
    // V5.39.7: 重排刷新 trigger——拖拽重排后增 UUID, .onChange 触发 recomputePhotos
    //   @Model 对象的 sortOrder 字段已变, 但 @State photos 是引用快照
    //   需 trigger 变更触发 .onChange → recomputePhotos 重 fetch + 重排
    //   此 trigger 必须是 PhotoGridView 内部 @State, 因为 caller (ContentView)
    //   无法直接调 recomputePhotos (private); @State 在同 struct 闭包内可直接改
    @State private var reorderRefreshTrigger = UUID()
    // V5.32: 缓存 groupByDate 结果——之前 masonryDateGroupedLayout 每次 body render 都重算
    //   O(n log n) 复杂度 (iterate + bucket + sort groups + sort photos in groups)
    //   1000 张图 × 每次 render 滚动 = 1000+ 次重算, 浪费
    //   改: recomputePhotos() 同步算好, masonryDateGroupedLayout 直接读 cachedDateGroups
    //   仅 sort 是 .importedAt* 时 (masonryDateGroupedLayout 路径) 实际用——非 date sort 不读
    @State private var cachedDateGroups: [DateGroup] = []
    // V6.38.2 (P0 perf): computeCellFrames cache — GeometryReader 内 O(n) 重算避免
    //   之前每次 GeometryReader 求值 (window resize / zoom / sidebar 显隐 / view mode 切换)
    //   都跑 1000+ photos + GridLayout.computeRows + CGRect alloc = ~3000 ops
    //   现在 cache hit: O(1). Invalidation: layout 参数 + photos.count + cachedDateGroups.count 变化
    @State private var cachedCellFrames: [CellFrame] = []
    @State private var cachedCellFramesKey: Int = 0
    @State private var cellFramesCacheValid: Bool = false
    // V5.61-1: 滚动位置——.scrollPosition(id:) 绑定, SwiftUI 自动追踪顶部可见 item
    //   onAppear 初始化为 scrollAnchorPhotoID (从 ContentView 传, 来自 model.UserDefaults)
    //   onChange 自动回调 onScrollAnchorChange 写回 model
    @State private var scrollAnchorID: String? = nil
    // V5.61-1: 防止 onChange 写入 loop——onAppear 初始化后会触发一次, 用 flag 跳过首次
    @State private var hasRestoredInitialScroll: Bool = false

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
        // V5.32: 同步缓存 date groups——避免 body 每 render 重算 O(n log n)
        //   masonryDateGroupedLayout 直接读 cachedDateGroups
        cachedDateGroups = PhotoStats.groupByDate(photos)
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
                    onClearFilters: onClearFilters,
                    // V6.08: 回收站空状态副提示用 live retentionDays (之前写死 30)
                    retentionDays: retentionDays
                )
                .transition(.opacity)
            } else {
                contentView
                    .transition(.opacity)
            }
        }
        // V3.6.39: 触发视图模式切换的 transition 动画
        .animation(Animations.standard, value: viewMode)
        // V3.6.43: 触发空状态切换的 transition 动画
        .animation(Animations.standard, value: photos.isEmpty && !hasSelection)
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
        // V5.39.7: 拖拽重排后触发重算
        //   masonryRowsView 内部 onReorder 闭包会增 reorderRefreshTrigger
        //   → 此 .onChange 触发 → recomputePhotos 重 fetch + 重排 (新 sortOrder 生效)
        .onChange(of: reorderRefreshTrigger) { _, _ in
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
        // 监听 GridViewModel 数据变更 (删除/移动/评分等) → 立即刷新 visible photos
        .onReceive(NotificationCenter.default.publisher(for: .gridModelDidChange)) { _ in
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
    }

    private var navigationTitle: String {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return Copy.gridTitleSearch(trimmed) }
        if let folder = folder { return folder.name }
        if let tag = tag { return "#\(tag.name)" }
        // V5.8: 砍"收藏"——侧边栏无收藏入口
        if filterUnfiled { return Copy.sidebarUnfiled }
        if filterDuplicates { return Copy.sidebarDuplicates }
        if filterRecent7Days { return Copy.gridTitleRecent7Days }
        if filterLargeFiles { return Copy.gridTitleLargeFiles }
        if filterInTrash { return "回收站" }  // V4.36.x: 统一为"回收站"
        return Copy.sidebarAll
    }

    // ─── 根据视图模式切换 ───
    // V3.6.39: 加 .transition(.opacity) + .animation 让模式切换平滑
    // V5.28: 删 V5.23 top fade gradient (误判为 Photos 风格)
    //   - 之前我以为 Photos.app Library 顶部有 fade, 实际无
    //   - Photos 实际: grid 顶 cell 与 toolbar 硬接
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            photoGrid
                // V5.25: 平滑密度切换动画——spring animation 在 thumbnailSize 变化时
                //   spring response 0.3 + damping 0.8: 快速但不"弹"
                .animation(Animations.interactive, value: thumbnailSize)
                .transition(.opacity)
        case .list:
            PhotoListView(
                photos: photos,
                selection: selection,
                searchText: searchText,
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
    // V5.16 + V5.41: masonry 重构——macOS Photos.app "Days/Library" 真版 (justified row 布局)
    //   - 行内 cell 高度统一 = rowHeight (thumbnailSize)
    //   - cell 宽度 = rowHeight × photo.aspectRatio (变宽)
    //   - 行 reflow: MasonryMath.groupIntoRows 算好每行 cell 列表
    //   - LazyVStack of MasonryRow (每行 HStack 固定高)
    // V5.29: 接入 GridLayout.computeRows (model 层纯函数)
    // V5.39.2: grid 左右侧栏间距——避免 thumbnails 贴 sidebar/status bar
    //   之前 V5.28 edge-to-edge (无 padding)——cell 直接顶到侧栏边缘
    //   用户反馈"缩略图和左右侧栏距离太近, 视觉压迫"
    //   16pt 横向 padding: cell 距侧栏 16pt 留白, 视觉舒适
    //   同步从 availableWidth 减 2×16pt, cell 实际宽度按 padded area 算
    private let gridHorizontalPadding: CGFloat = 16

    @ViewBuilder
    private var photoGrid: some View {
        GeometryReader { geo in
            // V5.39.2: 减 2 × gridHorizontalPadding——cell 算的 availableWidth 是 padded area
            //   配合下面 masonryFlatLayout / masonryDateGroupedLayout 的 .padding(.horizontal, ...)
            //   让 cell 视觉上落在缩进后的容器内, 不溢出
            let availableWidth = geo.size.width - 2 * gridHorizontalPadding
            let rowHeight: CGFloat = thumbnailSize  // 缩略图大小 = 行高
            // V5.19: rowSpacing 8pt → 16pt, cellSpacing 12pt → 20pt
            // V5.27: 20pt → 8pt, 16pt → 8pt——macOS Photos Library 节奏
            // V5.28: 8pt → 4pt——更紧凑的 Photos.app 实际 (2-3pt 太紧, 4pt 折衷)
            // V5.37: 4pt → 8pt——User 反馈'行与行之间没有间距'
            // 均匀网格间距 6pt——比之前 12/8 更紧凑，左右/上下一致，视觉更精致
            //   Photos.app / Lightroom 用 4-6pt 均匀间距，创建 uniform 网格节奏
            let rowSpacing: CGFloat = 6
            let cellSpacing: CGFloat = 6

            // V6.17.0: 算 cell frames — 给矩形圈选 hit test 用
            //   用同一套 layout params (cellSize/cellSpacing/rowSpacing/padding)
            //   跟下方 masonryRowsView 计算完全一致, frame 位置精准
            let cellFrames = computeCellFrames(
                availableWidth: availableWidth,
                rowHeight: rowHeight,
                rowSpacing: rowSpacing,
                cellSpacing: cellSpacing,
                gridPadding: gridHorizontalPadding
            )

            // V4.37.1: 条件分支——isDateBased 时按日期分组, 否则平铺
            Group {
                if sortOption.isDateBased {
                    masonryDateGroupedLayout(
                        availableWidth: availableWidth,
                        gridHorizontalPadding: gridHorizontalPadding,
                        rowHeight: rowHeight,
                        rowSpacing: rowSpacing,
                        cellSpacing: cellSpacing,
                        // V6.17.0.3: cell frames 透传到 masonry 内挂 gesture + overlay
                        cellFrames: cellFrames
                    )
                } else {
                    masonryFlatLayout(
                        availableWidth: availableWidth,
                        gridHorizontalPadding: gridHorizontalPadding,
                        rowHeight: rowHeight,
                        rowSpacing: rowSpacing,
                        cellSpacing: cellSpacing,
                        // V6.17.0.3: cell frames 透传到 masonry 内挂 gesture + overlay
                        cellFrames: cellFrames
                    )
                }
            }
            // V6.17.0: 矩形圈选 gesture 挂 photoGrid 根 — 跟 cell frames 同坐标系
            //   用 .local (GeometryReader 内), 跟 cellFrames 完全对齐
            //   V6.17.0.3: gesture + overlay 都搬进 masonryFlatLayout/masonryDateGroupedLayout
            //     内的 VStack — 之前挂 Group 跟 cell frames 不同 space (Group 是 GeometryReader
            //     空间, VStack 是 photoGrid named space), rect 跟 overlay 不同步 → 视觉滞后
            //     而且 gesture 触发时 sidebar 的 List(selection:) 也并行识别 (simultaneousGesture
            //     不挡), 拖到 sidebar 区域时 sidebar 选中被改 — "影响侧边栏" BUG
            //   现在 gesture + overlay 都在 VStack 上 (photoGrid space + VStack bounds):
            //     - rect 跟 cell frames 完全同 space → 视觉精准
            //     - gesture 限定在 VStack bounds 内 → 不会跟 sidebar 串扰
        }
    }

    // V6.17.0: 计算 cell 在 photoGrid 命名 coord space 的 frame — 给 marquee hit test 用
    //   V6.17.0.1 fix: 改用 photoGrid named space (挂 VStack/LazyVStack)
    //     之前 V6.17.0 用 gridPadding offset (y 从 gridPadding 开始), scroll 之后 rect 跟
    //     cellFrames 对不上 (rect 在 visible area, cellFrames 在 content)
    //     现在 y 从 0 开始 (photoGrid space = VStack 局部, 顶部是 (0,0))
    //   x 用 gridPadding 是因为 VStack 有 .padding(.horizontal, gridHorizontalPadding)
    //     (16pt), cell 在 VStack space 里的 x 实际从 16 开始
    //   跟 masonryRowsView 用同一 GridLayout, 保证位置完全一致
    //   支持 date grouped (带 section header) + flat 两种 layout
    // V6.102: 抽到 GridLayoutEngine (Views/Grid/GridLayoutEngine.swift)
    //   - cache check 在这里, 算逻辑在 engine — PhotoGridView 保留 @State cache 字段
    //   - V6.38.2 + V6.59 cache 行为完全保留
    private func computeCellFrames(
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat,
        gridPadding: CGFloat
    ) -> [CellFrame] {
        let input = GridLayoutEngine.Input(
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            cellSpacing: cellSpacing,
            gridPadding: gridPadding,
            photos: photos,
            cachedDateGroups: cachedDateGroups,
            layoutMode: layoutMode,
            sortOption: sortOption
        )
        // V6.102: cache check — Input.cacheKey hash 跟 V6.38.2 cellFramesCacheKey 等价
        let key = input.cacheKey
        if cellFramesCacheValid && key == cachedCellFramesKey {
            return cachedCellFrames
        }

        let result = GridLayoutEngine.compute(input)

        // V6.38.2: 写 cache — cache state 仍在 PhotoGridView @State (cache 行为不变)
        cachedCellFrames = result
        cachedCellFramesKey = key
        cellFramesCacheValid = true
        return result
    }

    // V5.16: masonry 日期分组布局
    // V5.23: sticky date header——用 Section + pinnedViews: [.sectionHeaders]
    @ViewBuilder
    private func masonryDateGroupedLayout(
        availableWidth: CGFloat,
        gridHorizontalPadding: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat,
        cellFrames: [CellFrame]  // V6.17.0.3: 给 LazyVStack 内 gesture + overlay 用
    ) -> some View {
        let groups = cachedDateGroups  // V5.32: 缓存, 不再每 render 重算 O(n log n)

        // V5.61-1: 改用 .scrollPosition(id:) 自动追踪——比 V5.60-6 的 ScrollViewReader 干净
        //   SwiftUI 自动把顶部可见 item id 写到 $scrollAnchorID
        //   onChange 回调 onScrollAnchorChange 写回 model (UserDefaults 持久化)
        //   onAppear 首次设 scrollAnchorID = scrollAnchorPhotoID 触发恢复
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
                            // V6.12.12: 砍 .square 后只剩 .squareFit
                            //   现在 always true (所有 mode 都显示 caption)
                            //   保留判断形式方便未来加 mode 时直接改这里
                            showDateCaption: false,  // V6.22.7: 永远不显示日期 caption (用户要求)
                            // V5.39.7: 透传排序 + 重排回调 (拖拽重排依赖)
                            sortOption: sortOption,
                            onReorder: onReorder
                        )
                    } header: {
                        // V5.56: Key Photo 段头代表图——每组 1 张 32×32 缩略图
                        // 镜像 Photos.app 真版: 段头左侧 1 张小图, 标识该日期组
                        // 内联 representative 选取 (group.photos 已按 importedAt 降序):
                        //   1. 优先非 trashed (避免代表图指向回收站)
                        //   2. fallback group.photos.first (即使全 trashed 也显示某张)
                        // V6.11: 全 trashed 时返 nil (跟 ContentViewModel.representativePhoto 对齐)
                        //   之前 ?? group.photos.first fallback 返 trashed photo 显示灰缩略图
                        //   nil 让 DateSectionHeader 走 text-only 分支 (line 39 init)
                        let representative = group.photos.first(where: { !$0.isInTrash })
                        DateSectionHeader(label: group.label, count: group.photos.count, representative: representative)
                            // V5.60-6: 给 header 加 id — .scrollPosition(id:) 锚定 DateGroup.id
                            .id(group.id)
                    }
                }
            }
            // V5.39.2: grid 左右缩进——整组缩进 (包括 DateSectionHeader)
            //   与 cell 容器一致缩进, 视觉上 date header 和 cell 对齐
            .padding(.horizontal, gridHorizontalPadding)
            // V6.17.0.1: photoGrid coord space 挂 LazyVStack — 跟 cell frames 同空间
            .coordinateSpace(.photoGrid)
            // V6.17.2: 透传 isMarqueeActive 到 cell — sub-view @Environment 消费
            //   圈选时 .draggable 返 nil, 修 "cell drag preview 跟 marquee rect 同时显示" 视觉冲突
            .environment(\.isMarqueeActive, isMarqueeActive)
            // V6.17.0.3: gesture + overlay 都搬进 LazyVStack (在 ScrollView 内)
            //   之前在 Group (外面) 跟 cell frames 不同 space → 视觉滞后
            //   现在都在 photoGrid space, rect 跟 cell 精准对齐
            //   LazyVStack bounds 限定 gesture — 不会延伸到 sidebar (BUG1 修)
            .marqueeSelectionGesture(
                isMarqueeActive: $isMarqueeActive,
                marqueeRect: $marqueeRect,
                selection: $selection,
                cellFrames: cellFrames
            )
            .overlay {
                if let rect = marqueeRect {
                    // V6.22.9: 删 count — "已选 N 张" 误导用户以为实时选中
                    BoxSelectionOverlay(rect: rect)
                }
            }
            .animation(Animations.standard, value: photos.count)
        }
        // V6.17.0.4: 圈选激活时禁 ScrollView 滚动 — 避免 content 跟 mouse 错位
        .scrollDisabled(isMarqueeActive)
        // V5.61-1: .scrollPosition(id: $scrollAnchorID) 自动追踪顶部可见 item
        .scrollPosition(id: $scrollAnchorID)
        // V5.61-1: onChange 写回 model (auto-save)——SwiftUI 每次滚动变化都触发
        //   hasRestoredInitialScroll 防止 onAppear 初始化时覆盖 model (loop guard)
        .onChange(of: scrollAnchorID) { _, new in
            guard hasRestoredInitialScroll else { return }
            if let new {
                onScrollAnchorChange(new)
            }
        }
        .onAppear {
            // V5.61-1: 初始恢复——设 scrollAnchorID 触发 .scrollPosition(id:) 自动 scrollTo
            if let anchor = scrollAnchorPhotoID {
                scrollAnchorID = anchor
            }
            hasRestoredInitialScroll = true
        }
    }

    // V5.16: masonry 平铺布局 (filename/size/custom 排序时用)
    @ViewBuilder
    private func masonryFlatLayout(
        availableWidth: CGFloat,
        gridHorizontalPadding: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat,
        cellFrames: [CellFrame]  // V6.17.0.3: 给 VStack 内 gesture + overlay 用
    ) -> some View {
        // V5.61-1: 改用 .scrollPosition(id:)——同 date grouped 模式
        //   masonryRowsView 内部用 ForEach 渲染 Photo, swiftUI 自动找 .id 锚点
        // V6.17.0.4: .scrollDisabled(isMarqueeActive) — 圈选激活时 ScrollView 不滚动
        //   之前同时拖 scroll + marquee → content 跟着 scroll 动, rect (在 content 空间) 跟
        //   mouse (在 screen 空间) 错位 → 视觉滞后 / 准确度差
        //   disable scroll 后, content 不动, rect 跟 mouse 1:1 对齐
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masonryRowsView(
                    photos: photos,
                    availableWidth: availableWidth,
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    cellSpacing: cellSpacing,
                    // V5.18: 平铺视图无日期 header 也无 caption
                    showDateCaption: false,
                    // V5.39.7: 透传排序 + 重排回调
                    sortOption: sortOption,
                    onReorder: onReorder
                )
            }
            // V5.39.2: grid 左右缩进 16pt
            .padding(.horizontal, gridHorizontalPadding)
            // V6.17.0.1: photoGrid coord space 挂 VStack — 跟 cell frames 同空间
            //   跟 .padding 一起挂 (named space 覆盖 VStack + padding 的整体)
            .coordinateSpace(.photoGrid)
            // V6.17.2: 透传 isMarqueeActive 到 cell — sub-view @Environment 消费
            //   圈选时 .draggable 返 nil, 修视觉冲突
            .environment(\.isMarqueeActive, isMarqueeActive)
            // V6.17.0.3: gesture + overlay 都搬进 VStack — 之前在 Group (外面),
            //   rect 跟 overlay 不同 space → 视觉滞后
            //   现在都在 photoGrid space, rect 跟 cell 精准对齐
            //   VStack bounds 限定 gesture — 不会延伸到 sidebar (V6.17.0.3 BUG1 修)
            .marqueeSelectionGesture(
                isMarqueeActive: $isMarqueeActive,
                marqueeRect: $marqueeRect,
                selection: $selection,
                cellFrames: cellFrames
            )
            .overlay {
                if let rect = marqueeRect {
                    // V6.22.9: 删 count — "已选 N 张" 误导用户以为实时选中
                    BoxSelectionOverlay(rect: rect)
                }
            }
            .animation(Animations.standard, value: photos.count)
        }
        // V6.17.0.4: 圈选激活时禁 ScrollView 滚动 — 避免 content 跟 mouse 错位
        .scrollDisabled(isMarqueeActive)
        // V5.61-1: masonryRowsView 内部 Photo 渲染用 .id(photo.id) 锚定
        .scrollPosition(id: $scrollAnchorID)
        .onChange(of: scrollAnchorID) { _, new in
            guard hasRestoredInitialScroll else { return }
            if let new {
                onScrollAnchorChange(new)
            }
        }
        .onAppear {
            if let anchor = scrollAnchorPhotoID {
                scrollAnchorID = anchor
            }
            hasRestoredInitialScroll = true
        }
    }

    // V5.29: masonryRowsView 接入 GridLayout (纯函数) + PhotoGridLayoutView (渲染)
    //   - 之前: 80 行 (内嵌 groupIntoRows + LazyVStack + MasonryRowView 调用)
    //   - 现在: 20 行 (GridLayout + PhotoGridLayoutView)
    // V5.35: .square 模式 cell 大小动态算——填满 availableWidth
    //   - 之前 (V5.34-1): 固定 cellSize = rowHeight (200pt), 大量右侧空白
    //   - Photos.app Library 真版: cellSize = (availableWidth - (n-1)*spacing) / n, 严格填满
    //   - .masonry / .masonryStretch 模式: 仍用原 rowHeight (aspect-based 宽度)
    @ViewBuilder
    private func masonryRowsView(
        photos: [Photo],
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat,
        // V5.18: date caption 开关
        showDateCaption: Bool,
        // V5.39.7: 透传排序模式 (决定 .dropDestination 是否启用) + 重排回调
        //   @escaping 必加——closure 跨 View body 调用, Swift 要求显式标
        sortOption: SortOption,
        onReorder: @escaping () -> Void
    ) -> some View {
        // V6.12.12: 砍 .square 后只剩 .squareFit, actualRowHeight 永远是 SquareLayout.cellSize
        //   (V5.35 动态算填满宽, 之前 .masonry 才用 rowHeight 直接传)
        let actualRowHeight: CGFloat = SquareLayout.cellSize(
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            cellSpacing: cellSpacing
        )
        let layout = GridLayout(
            availableWidth: availableWidth,
            rowHeight: actualRowHeight,  // V5.35: 动态算的 cellSize
            cellSpacing: cellSpacing,
            layoutMode: layoutMode
        )
        let rows = layout.computeRows(from: photos)
        // V5.39.1: 去掉内层 ScrollView——之前 masonryRowsView 包了 ScrollView { PhotoGridLayoutView },
        //   与外层 masonryFlatLayout 的 ScrollView 嵌套, 导致 LazyVStack spacing 被吞 (row 间无视觉间距)
        //   改为直接返回 PhotoGridLayoutView, 由外层 ScrollView 统一滚动
        // V5.39.7: 内部 onReorder 闭包——增 reorderRefreshTrigger 触发 .onChange → recomputePhotos
        //   @State 在同 struct 闭包内可直接修改 (SwiftUI 关键洞察)
        //   caller (ContentView) 的 onReorder 透传到这里被忽略——此内部闭包才是真正的 trigger
        let internalReorder: () -> Void = {
            self.reorderRefreshTrigger = UUID()
        }
        PhotoGridLayoutView(
            rows: rows,
            rowSpacing: rowSpacing,
            cellSpacing: cellSpacing,
            showDateCaption: showDateCaption,
            photos: photos,
            // V5.39.7: 透传到 PhotoGridLayoutView → PhotoRowView → PhotoThumbnailView
            //   在 photos 之后, selection 之前——SwiftUI call site 顺序约束
            sortOption: sortOption,
            onReorder: internalReorder,
            // V5.46: 透传布局模式 (决定 .fill vs .fit letterbox)
            layoutMode: layoutMode,
            selection: selection,
            folders: folders,
            allTags: allTags,
            retentionDays: retentionDays,
            onTap: handleTap,
            onDoubleTap: onDoubleTap,
            // V6.22.1 (P2 #2): 旋转回调 — 透传 ContentView 传的 { model.rotateSelected(clockwise:) }
            onRotate: onRotate,
            // V6.94.1 (P0 #3): 标注回调 — 透传 ContentView 传的 { NotificationCenter.post(.markupRequested) }
            onMarkup: onMarkup,
            onCrop: onCrop,
            isSingle: isSingle
        )
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
        case .singleSelect(let s), .toggleMultiSelect(let s), .rangeSelect(let s), .deselect(let s):
            selection = s
        }
    }
    // V6.38.1 (Phase 1): 删 deletePhoto(_:) — 之前 cell context menu Delete → onDelete 闭包
    //   现在删除走 ⌘⌫ → ContentView.onDelete → model.grid.handleDelete() → batchDeleteConfirm / deleteSinglePhoto
    //   cell 不再需要 per-photo delete 入口

}
