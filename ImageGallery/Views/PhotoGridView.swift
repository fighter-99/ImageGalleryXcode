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
    let thumbnailSize: CGFloat
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
    // V5.39.6 NEW: 拖入导入回调——从 Finder 拖文件 / 文件夹到 grid 直接导入
    //   macOS 用户习惯从 Finder 拖文件到 app (跟 Photos.app 行为一致)
    //   onImport 走 NSOpenPanel; onDropImport 走 NSItemProvider (拖拽), 互不冲突
    //   必须放在 exportComplete 之后, onReorder 之前——SwiftUI call site 顺序约束
    let onDropImport: ([URL]) -> Void
    // V5.39.7 NEW: 重排回调 (customOrder 拖拽重排后调, 触发 recomputePhotos 重算 grid)
    let onReorder: () -> Void

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
        // V5.39.7: 拖拽重排后触发重算
        //   masonryRowsView 内部 onReorder 闭包会增 reorderRefreshTrigger
        //   → 此 .onChange 触发 → recomputePhotos 重 fetch + 重排 (新 sortOrder 生效)
        .onChange(of: reorderRefreshTrigger) { _, _ in
            recomputePhotos()
            onVisiblePhotosChange(photos)
        }
        // V5.39.6: 拖入导入——从 Finder 拖文件 / 文件夹到 grid 任何位置直接导入
        //   .dropDestination 是 SwiftUI 14+ 新 API, 替代 .onDrop(of:)
        //   - URL.self: 只接收 file URL (图片文件 / 包含图片的文件夹)
        //   - action: 闭包收到 [URL] (Finder 拖的多选 / 文件夹递归) + 落点坐标
        //   - 返回 true 表示接受 drop (false = 拒绝, 系统会显示禁止图标)
        //   - onDropImport 是 ContentView 注入的回调, 走 ImageImporter.importURLs
        //   - 整个 body VStack 都接受 drop (空态时也能拖入导入)——符合 Photos.app UX
        .dropDestination(for: URL.self) { urls, _ in
            onDropImport(urls)
            return true
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
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: thumbnailSize)
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
            // V5.39.1: 8pt → Spacing.md (12pt) + 去掉内层 ScrollView, 行间隙终于可见
            //   之前 cell letterbox 透明 (V5.27) + 内层 ScrollView 吞掉 LazyVStack spacing,
            //   即使 8pt 也是看不出来. 12pt 更明显 + cell 加 4% primary tint
            //   (从 V5.21 0.04 white tint 沿用, 略浅) 让 cell 边缘可见 → row gap 视觉清晰
            let rowSpacing: CGFloat = Spacing.md    // V5.39.1: 8 → 12 (Spacing.md)
            let cellSpacing: CGFloat = 8            // V5.37: 4 → 8 保持

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
    private func computeCellFrames(
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat,
        gridPadding: CGFloat
    ) -> [CellFrame] {
        let cellSize = SquareLayout.cellSize(
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            cellSpacing: cellSpacing
        )
        var result: [CellFrame] = []
        // date header 高度 (DateSectionHeader 32pt key photo + label + Spacing.xl gap)
        // V5.56: DateSectionHeader 32pt; LazyVStack spacing 是 Spacing.xl
        // V6.17.0: 32 + 4 (header padding) + Spacing.xl (section gap) = 估算
        //   简化估算: 实际渲染可能有 padding 微差, V1 接受 ±5pt 误差
        let dateHeaderHeight: CGFloat = 32 + 4 + Spacing.xl

        if sortOption.isDateBased {
            // V5.32: 缓存, 不再每 render 重算
            let groups = cachedDateGroups
            // V6.17.0.1: y 从 0 开始 (photoGrid space 顶部)
            var y: CGFloat = 0
            for group in groups {
                y += dateHeaderHeight
                let rows = GridLayout(
                    availableWidth: availableWidth,
                    rowHeight: cellSize,
                    cellSpacing: cellSpacing,
                    layoutMode: layoutMode
                ).computeRows(from: group.photos)
                for row in rows {
                    // V6.17.0.1: x 从 gridPadding 开始 (VStack 有 horizontal padding 16pt)
                    var x: CGFloat = gridPadding
                    for item in row.items {
                        result.append(CellFrame(
                            id: item.id,
                            frame: CGRect(x: x, y: y, width: item.width, height: row.rowHeight)
                        ))
                        x += item.width + cellSpacing
                    }
                    y += row.rowHeight + rowSpacing
                }
            }
        } else {
            let items = photos.map { photo in
                PhotoGridItem(
                    id: photo.id,
                    aspectRatio: GridLayout.aspectRatio(of: photo),
                    width: 0
                )
            }
            let rows = GridLayout(
                availableWidth: availableWidth,
                rowHeight: cellSize,
                cellSpacing: cellSpacing,
                layoutMode: layoutMode
            ).computeRows(from: items)
            // V6.17.0.1: y 从 0 开始
            var y: CGFloat = 0
            for row in rows {
                // V6.17.0.1: x 从 gridPadding 开始
                var x: CGFloat = gridPadding
                for item in row.items {
                    result.append(CellFrame(
                        id: item.id,
                        frame: CGRect(x: x, y: y, width: item.width, height: row.rowHeight)
                    ))
                    x += item.width + cellSpacing
                }
                y += row.rowHeight + rowSpacing
            }
        }
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
                            showDateCaption: layoutMode != .squareFit,
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
                    // count = 当前 rect 内的 cell 数 (跟 hit test 同逻辑, 视觉一致)
                    let count = cellFrames.filter { cell in
                        let centerX = cell.frame.midX
                        let centerY = cell.frame.midY
                        return rect.contains(CGPoint(x: centerX, y: centerY))
                    }.count
                    BoxSelectionOverlay(rect: rect, count: count)
                }
            }
            .animation(Animations.medium, value: photos.count)
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
                    // count = 当前 rect 内的 cell 数 (跟 hit test 同逻辑, 视觉一致)
                    let count = cellFrames.filter { cell in
                        let centerX = cell.frame.midX
                        let centerY = cell.frame.midY
                        return rect.contains(CGPoint(x: centerX, y: centerY))
                    }.count
                    BoxSelectionOverlay(rect: rect, count: count)
                }
            }
            .animation(Animations.medium, value: photos.count)
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
            onDelete: deletePhoto,
            onTap: handleTap,
            onDoubleTap: onDoubleTap
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
        isMarqueeActive: .constant(false),
        marqueeRect: .constant(nil),
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
        layoutMode: .squareFit,  // V6.12.12: .square 砍了, Preview 默认 .squareFit
        sortOption: .importedAtDesc,
        scrollAnchorPhotoID: nil,  // V5.60-6: Preview 不需要 anchor
        onScrollAnchorChange: { _ in },  // V5.61-1: Preview no-op
        onVisiblePhotosChange: { _ in },
        onImport: {},
        onBatchDelete: {},
        onClearMultiSelect: {},
        onDoubleTap: { _ in },
        onClearFilters: {},
        onExportComplete: { _ in },
        onDropImport: { _ in },
        onReorder: {}
    )
    .frame(width: 600, height: 400)
}
