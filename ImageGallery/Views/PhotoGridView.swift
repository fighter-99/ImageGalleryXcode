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
//  V3.6.52: 重构选中状态——3 Binding (selectedPhoto/selectedIDs/lastSelectedID) 合并为
//  1 Binding<SelectionState>；applyTapOutcome 收成 1 行；deletePhoto 用 selection.removing(_:)；
//  局部 isMultiSelect 重命名为 hasSelection（与 ContentView 的 count>1 区分）
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
    // V3.6.52: 3 个绑定（selectedPhoto/selectedIDs/lastSelectedID）合并为 1 个
    // SelectionState binding——单一真相源，消除 3 字段手工同步的 5+ 处易错点
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
    // V4.36.x: 工具栏筛选按钮 4 维（透传到 PhotoStats.filtered）
    let selectedFolderIDs: Set<UUID>
    let selectedTagIDs: Set<UUID>
    let selectedShapes: Set<PhotoShape>
    let filterMinRating: Int
    // V4.36.x: 工具栏筛选激活标记（空态文案感知）
    var isFilterActive: Bool {
        !selectedFolderIDs.isEmpty || !selectedTagIDs.isEmpty
            || !selectedShapes.isEmpty || filterMinRating > 0
    }
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
    // V4.9.0: 清空所有 filter (searchText + folder + tag + 所有 filter 状态)
    //   用于"无搜索结果"和"空 folder/tag"等空状态次 CTA——"查看全部"
    let onClearFilters: () -> Void
    // V4.9.3: 加载中状态（导入时 brief 闪烁——主 grid 显示 Shimmer 占位）
    let isImporting: Bool = false
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
        hasher.combine(filterUnfiled)
        hasher.combine(filterDuplicates)
        hasher.combine(filterRecent7Days)
        hasher.combine(filterLargeFiles)
        hasher.combine(filterInTrash)
        // V4.36.x: 工具栏筛选 4 维（Set 有标准 Hashable；任一变化触发重算）
        hasher.combine(selectedFolderIDs)
        hasher.combine(selectedTagIDs)
        hasher.combine(selectedShapes)
        hasher.combine(filterMinRating)
        return hasher.finalize()
    }

    private func recomputePhotos() {
        // V4.36.6: 抽到 PhotoStats.filtered static helper——List/Timeline 视图共用
        // V4.36.x: 增 4 参（工具栏筛选按钮）
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

    // ─── 列数 ───
    // V5.16: 删 columnCount 硬编码——V4.36.0 后无引用（masonry 布局不需要）

    // 多选模式
    // V3.6.52: 原 isMultiSelect (count > 0) 改名为 hasSelection
    //   与 ContentView 的 isMultiSelect (count > 1) 区分——前者供空状态抑制用，
    //   后者供 DetailPane 切换布局用
    private var hasSelection: Bool { selection.hasSelection }

    var body: some View {
        VStack(spacing: 0) {
            // V3.5.19：移除 multiSelectTopBar
            // 批量操作搬到详情面板的 MultiSelectDetailView 里了

            // V4.9.3: 加载中优先于空状态（导入时 brief Shimmer）
            if isImporting {
                loadingGrid
                    .transition(.opacity)
            } else if photos.isEmpty && !hasSelection {
                emptyState
                    // V3.6.43: 空状态 fade in/out（之前是突现）
                    .transition(.opacity)
            } else {
                contentView
                    // V3.6.43: 内容 fade in/out
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
        // V5.8: 砍"收藏"——侧边栏无收藏入口
        if filterUnfiled { return "待整理" }
        if filterDuplicates { return "重复图" }
        if filterRecent7Days { return "最近 7 天" }
        if filterLargeFiles { return "大图（>5MB）" }
        if filterInTrash { return "回收站" }  // V4.36.x: 统一为"回收站"
        return "全部"
    }

    private var emptyState: some View {
        // V3.6.9：用统一 EmptyStateView 组件
        // V4.9.0: 区分 3 种 empty 场景，提供主 + 次 CTA
        //   - 无图片（首次启动）→ 主"导入图片"
        //   - 空相册/标签 → 主"导入图片" + 次"查看全部"
        //   - 无搜索结果 → 主"清除搜索" + 次"查看全部"
        EmptyStateView(
            icon: emptyIcon,
            title: emptyText,
            subtitle: emptyHint,
            iconColor: Color.accentColor.opacity(0.6),
            primaryAction: emptyPrimaryAction.map {
                EmptyStateView.Action(
                    label: $0.label,
                    systemImage: $0.systemImage,
                    onTap: $0.onTap
                )
            },
            secondaryAction: emptySecondaryAction.map {
                EmptyStateView.Action(
                    label: $0.label,
                    systemImage: $0.systemImage,
                    onTap: $0.onTap
                )
            }
        )
    }

    /// V4.9.3: 加载中 Shimmer 占位 grid
    ///   场景: 导入时 brief 闪烁（SwiftData 还没返回 photos）
    ///   复用 V4.4.0 Shimmer modifier
    private var loadingGrid: some View {
        // 12 个 Shimmer 占位 cell（足够填满可见区域）
        let columns = [GridItem(.adaptive(minimum: thumbnailSize), spacing: Spacing.xs)]
        return LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Surface.cardBackground)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .modifier(Shimmer(duration: 1.2))
            }
        }
        .padding(Spacing.md)
    }

    /// V4.9.0: 主 CTA 配置（label + systemImage + onTap）
    private struct EmptyCTA {
        let label: String
        var systemImage: String? = nil
        let onTap: () -> Void
    }

    /// V4.9.0: 主 CTA——根据 empty 场景返回不同操作
    private var emptyPrimaryAction: EmptyCTA? {
        // 无搜索结果 → "清除搜索"（通过 onClearFilters 触发：清 searchText + 切回全部）
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return EmptyCTA(
                label: "清除搜索",
                systemImage: "xmark.circle",
                onTap: { onClearFilters() }
            )
        }
        // 首次启动（无任何 filter） → "导入图片"
        if emptyShowImport {
            return EmptyCTA(
                label: "导入图片",
                systemImage: "square.and.arrow.down",
                onTap: onImport
            )
        }
        return nil  // 其他场景无主 CTA（如回收站空、收藏空等）
    }

    /// V4.9.0: 次 CTA——切换到"全部" 视图
    ///   用于空相册/空标签/无搜索结果等"当前 filter 无结果但全部有图"场景
    private var emptySecondaryAction: EmptyCTA? {
        // 无搜索结果 → "查看全部"（回到全部视图）
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return EmptyCTA(
                label: "查看全部",
                onTap: { onClearFilters() }
            )
        }
        // folder/tag 模式空 → "查看全部"
        if folder != nil || tag != nil {
            return EmptyCTA(
                label: "查看全部",
                onTap: { onClearFilters() }
            )
        }
        return nil
    }

    private var emptyIcon: String {
        // V4.36.x: 工具栏筛选激活 → 漏斗 icon
        if isFilterActive { return "line.3.horizontal.decrease.circle" }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "magnifyingglass" }
        // V5.8: 砍"收藏"图标分支
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
        // V4.36.x: 工具栏筛选激活但无匹配
        if isFilterActive { return "没有匹配筛选的图片" }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "没有匹配的图片" }
        // V5.8: 砍"收藏"空状态文本
        if filterUnfiled { return "没有待整理的图片" }
        if folder != nil { return "这个文件夹是空的" }
        if tag != nil { return "没有带此标签的图片" }
        if filterDuplicates { return "没有重复的图片" }
        if filterRecent7Days { return "最近 7 天没有新图" }
        if filterLargeFiles { return "没有大于 5 MB 的图" }
        if filterInTrash { return "回收站是空的" }  // V3.6 NEW
        return "还没有图片"
    }

    private var emptyHint: String {
        // V4.36.x: 提示调整筛选条件
        if isFilterActive { return "尝试减少筛选条件或调整侧边栏" }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "试试其他关键词" }
        // V5.8: 砍"收藏"空状态提示
        if filterUnfiled { return "把图片移动到文件夹来整理" }
        if folder != nil { return "导入图片后会自动放到此文件夹" }
        if tag != nil { return "在图片详情中添加此标签" }
        if filterDuplicates { return "重复图会自动出现在这里" }
        if filterInTrash { return "删除的图片会出现在这里，\(TrashRetentionDays.defaultValue.rawValue) 天后自动永久清除" }  // V3.6 NEW
        return "拖入图片，或点击“导入图片”开始添加"
    }

    private var emptyShowImport: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty && !filterUnfiled
            && folder == nil && tag == nil && !filterDuplicates
            && !filterInTrash  // V3.6 NEW: 回收站空状态不显示导入按钮
        // V5.8: 砍!filterFavorites——dead
    }

    // ─── 根据视图模式切换 ───
    // V3.6.39: 加 .transition(.opacity) + .animation 让模式切换平滑
    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            photoGrid
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
    //   - 行内 cell 高度统一 = rowHeight（thumbnailSize）
    //   - cell 宽度 = rowHeight × photo.aspectRatio（变宽）
    //   - 行 reflow: MasonryMath.groupIntoRows 算好每行 cell 列表
    //   - LazyVStack of MasonryRow（每行 HStack 固定高）
    //   - 列宽固定 (cellSize) 公式全删——masonry 模式不需要
    //   - 缩略图大小 (thumbnailSize) 语义从"列宽"改"行高"——Settings 不动
    @ViewBuilder
    private var photoGrid: some View {
        GeometryReader { geo in
            // V5.16: 减左右 padding (24pt) 拿真可用宽
            let availableWidth = geo.size.width - 2 * Spacing.md
            let rowHeight: CGFloat = thumbnailSize  // 缩略图大小 = 行高
            let rowSpacing: CGFloat = Spacing.sm     // 8pt 垂直间距（Photos.app 比例）
            let cellSpacing: CGFloat = Spacing.md   // 12pt cell 间距

            // V4.37.1: 条件分支——isDateBased 时按日期分组，否则平铺
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
    //   段头 "今天" / "昨天" / "本周" / "本月" / "X 月" / "X 年"
    //   LazyVStack + 多组 MasonryRow（每个 group 一行集合）
    @ViewBuilder
    private func masonryDateGroupedLayout(
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat
    ) -> some View {
        let groups = PhotoStats.groupByDate(photos)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        DateSectionHeader(label: group.label, count: group.photos.count)
                        masonryRowsView(
                            photos: group.photos,
                            availableWidth: availableWidth,
                            rowHeight: rowHeight,
                            rowSpacing: rowSpacing,
                            cellSpacing: cellSpacing
                        )
                    }
                }
            }
            .padding()
            .animation(Animations.medium, value: photos.count)
        }
    }

    // V5.16: masonry 平铺布局（filename/size/custom 排序时用）
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
                    cellSpacing: cellSpacing
                )
            }
            .padding()
            .animation(Animations.medium, value: photos.count)
        }
    }

    // V5.16: 装箱 + 渲染多行 masonry——平铺/分组布局共用
    @ViewBuilder
    private func masonryRowsView(
        photos: [Photo],
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        cellSpacing: CGFloat
    ) -> some View {
        let items = photos.map { photo in
            MasonryMath.Item(
                id: photo.id,
                width: rowHeight * aspectRatio(of: photo),
                aspectRatio: aspectRatio(of: photo)
            )
        }
        let rows = MasonryMath.groupIntoRows(
            items: items,
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            spacing: cellSpacing
        )

        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                MasonryRowView(
                    itemIds: row.items.map(\.id),
                    itemWidths: row.items.map(\.width),
                    photos: photos,
                    rowHeight: rowHeight,
                    cellSpacing: cellSpacing,
                    selection: selection,
                    folders: folders,
                    allTags: allTags,
                    retentionDays: retentionDays,
                    deletePhoto: deletePhoto,
                    handleTap: handleTap,
                    onDoubleTap: onDoubleTap
                )
            }
        }
    }

    // V5.16: 单张照片宽高比（aspectRatio 为 0 或缺省时 fallback 1.0）
    private func aspectRatio(of photo: Photo) -> CGFloat {
        if photo.width > 0 && photo.height > 0 {
            return CGFloat(photo.width) / CGFloat(photo.height)
        }
        return 1.0
    }

    // V4.37.1: 抽出单 cell 渲染——masonryRowsView 共用
    // V5.16: 改签名 cellSize → cellWidth + rowHeight
    @ViewBuilder
    private func photoCell(_ photo: Photo, cellWidth: CGFloat, rowHeight: CGFloat) -> some View {
        PhotoThumbnailView(
            photo: photo,
            isInMultiSelect: selection.contains(photo.id),
            isActive: selection.singleSelectedID == photo.id,
            folders: folders,
            allTags: allTags,
            cellWidth: cellWidth,
            rowHeight: rowHeight,
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

    // 当前单选 ID（用于蓝色边框）
    // 当前单选 ID（用于蓝色边框）
    // V3.6.52: 改用 selection 上的派生属性（删除原 local 重复实现）

    // ─── 处理点击（V3.6.30：抽成 MultiSelectMath.handleTap 纯函数 thin wrapper；V3.6.52：glue 收成 1 行）───
    private func handleTap(_ photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        let modifier: ClickModifier = {
            if modifiers.contains(.command) { return .command }
            if modifiers.contains(.shift) { return .shift }
            return .plain
        }()
        // V3.6.52: 直接传当前 selection，不再手工 destructure 3 个字段
        let photoIDs = photos.map { $0.id }
        let outcome = MultiSelectMath.handleTap(
            state: selection,
            photoID: photo.id,
            modifier: modifier,
            photoIDs: photoIDs
        )
        // V3.6.52: applyTapOutcome 收成 1 行——seam 已包含 X2 行为
        // （.command / .shift 都设 selectedPhotoID = nil），消费者无需覆盖
        applyTapOutcome(outcome)
    }

    // ─── 应用 TapOutcome 到 @State（V3.6.52：从 7 行收成 4 行）───
    private func applyTapOutcome(_ outcome: TapOutcome) {
        switch outcome {
        case .singleSelect(let s), .toggleMultiSelect(let s), .rangeSelect(let s):
            selection = s
        }
    }

    // ─── 删除（V3.6：走 RecycleBinService.recycle，移到回收站；V3.6.52：selection.removing 替手写）───
    private func deletePhoto(_ photo: Photo) {
        RecycleBinService(storage: .shared, modelContext: modelContext).recycle(photo)
        selection = selection.removing(photo.id)
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

// V4.39.0: PhotoThumbnailView + CellContextMenuModifier 拆出到独立文件
//   PhotoGridView 1180 → 607 行（拆分第 1 步：按 struct 拆文件）
//   - PhotoThumbnailView.swift（单 cell 完整渲染，~466 行）
//   - CellContextMenuModifier.swift（cell 右键菜单，~102 行）
//   与 V4.10.0 ContentView 拆分模式延续——单文件 1000+ 行易踩 type-check timeout 坑

#Preview {
    PhotoGridView(
        selection: .constant(SelectionState()),
        folder: nil,
        tag: nil,
        searchText: "",
        // V5.8: 砍 filterFavorites
        filterUnfiled: false,
        filterDuplicates: false,
        filterRecent7Days: false,
        filterLargeFiles: false,
        filterInTrash: false,
        // V4.36.x: 工具栏筛选 4 维（Preview 用空值）
        selectedFolderIDs: [],
        selectedTagIDs: [],
        selectedShapes: [],
        filterMinRating: 0,
        retentionDays: 30,  // V3.6.6
        thumbnailSize: 170,
        sortOption: .importedAtDesc,
        onVisiblePhotosChange: { _ in },
        onImport: {},
        onBatchDelete: {},
        onClearMultiSelect: {},
        onDoubleTap: { _ in },
        onClearFilters: {},  // V4.9.0
        onExportComplete: { _ in }
    )
    .frame(width: 600, height: 400)
}

// MARK: - V5.16: MasonryRowView

/// V5.16: masonry 单行渲染——HStack + 固定行高 + 变 cell 宽
///   - 行内 cell 高度统一 = rowHeight（行底部齐）
///   - cell 宽度 = itemWidths[i]（MasonryMath 算好的具体值）
///   - 跨 cell 共享 selection/folders/tags 状态
private struct MasonryRowView: View {
    let itemIds: [UUID]
    let itemWidths: [CGFloat]
    let photos: [Photo]
    let rowHeight: CGFloat
    let cellSpacing: CGFloat
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    let deletePhoto: (Photo) -> Void
    let handleTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(Array(itemIds.enumerated()), id: \.element) { index, itemId in
                if let photo = photos.first(where: { $0.id == itemId }) {
                    cellContent(photo: photo, width: itemWidths[index])
                }
            }
        }
        .frame(height: rowHeight, alignment: .top)
    }

    @ViewBuilder
    private func cellContent(photo: Photo, width: CGFloat) -> some View {
        PhotoThumbnailView(
            photo: photo,
            isInMultiSelect: selection.contains(photo.id),
            isActive: selection.singleSelectedID == photo.id,
            folders: folders,
            allTags: allTags,
            cellWidth: width,
            rowHeight: rowHeight,
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
