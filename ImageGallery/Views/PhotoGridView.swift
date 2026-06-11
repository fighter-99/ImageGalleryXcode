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
    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 60), spacing: 12),
                    count: columnCount
                ),
                // V4.23.0: 完整 Photos 风格——增 grid spacing
                //   旧 8pt → 12pt (Spacing.md)：cell 之间更明显分隔
                //   配合 cell 完全透明 + image clip 圆角，视觉简洁
                spacing: 12
            ) {
                ForEach(photos) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        isInMultiSelect: selection.contains(photo.id),
                        isActive: selection.singleSelectedID == photo.id,
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
        // V3.6.32: 撤销 V3.6.28 R2 的所有 UI 接入
        // 原因：simultaneousGesture(DragGesture) 在 macOS 26.5 上仍抢占 cell 的 .onDrag，
        // 即使 minimumDistance: 24 也不行。同时 onGeometryChange 给每个 cell 加了 .background
        // GeometryReader 路径上的 performance 开销（每次 scroll 都更新 cellFrames）。
        // BoxSelectionMath + BoxSelectionMathTests 保留为 dormant
        // 等未来找到不跟 cell .onDrag 抢的方法再启用
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
    // V4.4.0 NEW: Reduced Motion 适配——禁用 hover scale / 选中 scale 等动画
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeleteConfirm = false
    @State private var isHovered = false
    // V3.6.10: 键盘聚焦状态（SwiftUI 默认 focus ring，但 macOS 上系统不显示时手动加）
    @FocusState private var isFocused: Bool
    // V3.6.26: 异步缩略图加载状态（避免主线程阻塞）
    @State private var loadedImage: NSImage?
    // V4.4.0 NEW: 加载失败标记——区分"还在加载"vs"加载失败"
    @State private var loadFailed = false

    /// V3.6.6: 距离永久删除的剩余天数（nil = 未在回收站）
    private var daysLeft: Int? {
        PhotoStats.daysUntilPurge(trashedAt: photo.trashedAt, retentionDays: retentionDays)
    }

    /// V4.1.0 NEW: 剩余天数 badge 颜色编码
    /// - ≤3 天：红色（危险，永久删除迫近）
    /// - 4-7 天：橙色（提醒）
    /// - 8-14 天：黄色（注意）
    /// - >14 天：灰色（正常）
    private struct BadgeColor {
        let foreground: Color
        let background: Color
    }

    private func daysLeftBadgeColor(days: Int) -> BadgeColor {
        if days <= 3 {
            // V4.22.0: 暗色模式审计——badge 红/黄/橙硬编码改 token
            //   .red → Palette.destructive (已有 Surface.destructive 桥接)
            //   .orange → 保留 (无 token, 一次性使用)
            //   .yellow → Surface.favorite (已有 token)
            return BadgeColor(foreground: .white, background: Palette.destructive)
        } else if days <= 7 {
            // V4.22.0: 暗色模式审计——badge 颜色 token 化
            //   警告色保留 Color.orange (无 token, 一次性使用)
            return BadgeColor(foreground: .white, background: Color.orange)
        } else if days <= 14 {
            return BadgeColor(foreground: .primary, background: Surface.favorite.opacity(0.85))
        } else {
            // V4.22.0: 暗色模式审计——背景已用 .controlBackgroundColor 系统色
            //   自动适配亮/暗模式——保留
            return BadgeColor(foreground: .primary,
                              background: Color(nsColor: .controlBackgroundColor).opacity(0.9))
        }
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

    /// V3.6.51: 重构——选中状态机
    /// 之前 isActive 和 isInMultiSelect 两个独立 bool 各自驱动 3-4 个 modifier，
    /// 多个独立动画叠加产生'双层边框'错觉（用户多次反馈'先浅框再深蓝'）
    /// 现在统一为单一 CellSelectionState enum，单一来源
    enum CellSelectionState {
        case none       // 默认
        case single     // isActive 单选
        case multi      // isInMultiSelect 多选

        var borderWidth: CGFloat {
            switch self {
            case .none:   return 0      // 一直绘制 lineWidth=0 时不显示
            case .single, .multi: return 3  // 单选和多选都用 3pt（视觉一致）
            }
        }

        var borderColor: Color {
            switch self {
            case .none:   return .clear
            case .single, .multi: return Palette.selectionBorder
            }
        }

        var showsCheckmark: Bool {
            self == .multi
        }
    }

    private var selectionState: CellSelectionState {
        if isActive { return .single }
        if isInMultiSelect { return .multi }
        return .none
    }

    /// V4.4.3: 选中态时 hover shadow 让位（避免选中后 shadow 形成「浅框」）
    ///   hover shadow（Elevation.strong, radius 12pt）只在 hover-未选中时显示
    ///   选中态已用 accent 边框指示，无需 shadow 再"喊一遍"
    private var shadowShowsHover: Bool {
        isHovered && !isActive && !isInMultiSelect
    }

    /// V3.6.35: 当前缩放比例（按压 scale 撤销，hover > 选中 > 默认）
    /// V3.6.47: scale priority 修——选中 1.025 > hover 1.02
    ///   之前选中 1.015 < hover 1.02，点击 cell 反而变小（反 UX）
    /// V4.4.0: Reduced Motion 时所有 scale 强制 1.0（accessibility）
    private var currentScale: CGFloat {
        if reduceMotion { return 1.0 }            // V4.4.0: accessibility
        // V4.1.0 C: hover 从 1.025 → 1.01（更微妙——"凸起"而非"放大"）
        if isActive { return 1.015 }              // 单选：放大 1.5%（之前 2.5%）
        if isHovered && !isInMultiSelect { return 1.01 }  // hover：放大 1%
        return 1.0
    }

    /// V3.6.51: cell 选中视觉的单一 overlay（之前散在 3 个 overlay modifier）
    /// - 边框（单选 + 多选共用 lineWidth=3、Palette.selectionBorder，opacity 0/1）
    /// - ✓ checkmark（仅 multi）
    /// 不再有多选时的 selectionOverlayMulti 染色（V3.6.50 之前反复被误读为"淡色框"）
    /// V4.4.0: cornerRadius 从 Radius.md (8pt) → Radius.thumb (6pt)
    /// V4.4.1: `.stroke` → `.strokeBorder` 修「浅框」幽灵
    ///   `.stroke(lineWidth: 3)` 是 center-aligned——外侧 1.5pt 飞出 cell 圆角范围
    ///   在直线段 vs 圆角处厚度不一致（圆角处变薄、直线段变厚），且飞出部分
    ///   在 grid spacing 上显成"细蓝边"。
    ///   `.strokeBorder` 完全在 path 内绘制 → 边框完全在 cell 内，无飞出无几何错位
    @ViewBuilder
    private var cellSelectionOverlay: some View {
        let state = selectionState
        ZStack {
            RoundedRectangle(cornerRadius: Radius.thumb)
                .strokeBorder(state.borderColor, lineWidth: state.borderWidth)
            if state.showsCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.background).padding(3))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    private var aspectRatio: CGFloat {
        if photo.width > 0 && photo.height > 0 {
            return CGFloat(photo.width) / CGFloat(photo.height)
        }
        return 1.0
    }

    var body: some View {
        // V3.6.34: capture @Model 属性到 local（避免 payload 闭包在 background thread 访问）
        //   详见 .draggable 注释
        let capturedFileURL = photo.fileURL
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
                        // V4.23.0: 完整 Photos 风格——image 加 .clipShape 圆角
                        //   之前 cell .cornerRadius 是无意义修饰（image 自身无圆角）
                        //   现在圆角仅给 image clip，cell 自身完全透明
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                            .saturation(photo.isInTrash ? 0.05 : 1)
                            .opacity(photo.isInTrash ? (colorScheme == .dark ? 0.65 : 0.55) : 1)
                    } else if loadFailed {
                        // V4.4.0: 加载失败——明确指示 + 灰底
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.title3)
                                    Text("加载失败")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                    } else {
                        // V4.4.0: 加载中——shimmer 骨架替静态 photo icon
                        //   滚动到新位置时不再"灰图标闪烁"
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .shimmer()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // V3.6.26: 异步加载缩略图（缓存命中立即返回；未命中后台线程解码）
            // V4.4.0: 加载失败时 set loadFailed=true（loadImageAsync 返回 nil 视为失败）
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

            // V4.4.0: 删除 isInMultiSelect 时的 16% accent 蒙层
            //   V3.6.51 注释说"删了"但代码仍在；选中状态靠 cellSelectionOverlay
            //   的 3pt accent 边框 + checkmark 角标已足够，无需整图染色

            // 收藏星标
            if photo.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
            }

            // V3.6.6: 回收站剩余天数 badge（仅 trash 视图下显示）
            // V4.1.0: 颜色编码——≤3 红 / 4-7 橙 / 8-14 黄 / >14 灰
            // topLeading 不与右上角的多选 ✓ / 左上角的 star 冲突
            if let days = daysLeft, photo.isInTrash {
                let badgeColor = daysLeftBadgeColor(days: days)
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(days)")
                        .font(.caption.monospacedDigit())
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

            // 多选 ✓ 圆点
            // V3.6.38: 加 .animation 触发 transition（之前 transition 写了但没 animation 所以不生效）
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
        // V3.6.45: 选中（isInMultiSelect）用 standard（0.2s easeInOut）——springGentle 0.35s 太慢
        //   多选点击是高频操作，spring 反弹感在选择场景下反而像'卡顿'
        .animation(Animations.standard, value: isInMultiSelect)
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        // V4.4.5: cell 背景 controlBackgroundColor → windowBackgroundColor
        //   ↑ 终于找到「浅框」真正源头——cell 背景比窗口背景浅一档
        //   旧 Palette.cellBackground = Surface.elevated = controlBackgroundColor ≈ #2C2C2C
        //   窗口背景 windowBackgroundColor ≈ #1E1E1E
        //   每个 cell 在深窗口上 = 浅灰圆角矩形 = 用户感知的「浅框」
        //   现在 cell 与窗口同色，cell 容器感完全消失，只剩"漂浮的图片"
        //   视觉分隔靠 grid spacing（间距本身）+ cornerRadius clip（图片圆角）
        //   这是 Mac Photos.app 标准做法
        //
        // V4.23.0: 完整 Photos 风格——删 cell 背景 + 删 cell 圆角
        //   ↑ 进一步推到 Photos.app 真正的"无背景卡片"风格
        //   cell 完全透明——无 background、无 cornerRadius（image 自身圆角已够）
        //   视觉分隔仅靠 grid spacing (Spacing.sm 8pt) + image clip 圆角 (Radius.thumb 6pt)
        //   对比 V4.4.5 半 Photos 风格：V4.4.5 cell 仍与窗口同色"圆角矩形"
        //   V4.23.0 cell 完全透明——只剩"漂浮的圆角图片"
        //   删 .clipped() (原为与 .cornerRadius 配合)——image 自身 clip 足够
        // V3.6.51: 重构——单一 cellSelectionOverlay 取代之前散在 3 个 overlay modifier
        //   之前：3pt 单选 border（独立 modifier） + 2pt 多选 border（独立 modifier）
        //        + 多选 selectionOverlayMulti 染色（用户多次反馈的'淡色框'，V3.6.50 没真删干净）
        //   现在：单一 overlay 由 selectionState enum 驱动，单一 .animation(value: selectionState)
        //   状态切换时所有视觉元素（边框 + ✓）一起淡入淡出，无'先后'错觉
        //   V3.6.51 也彻底删除 selectionOverlayMulti 染色（16% accent 太显眼被读成'浅框'）
        .overlay(cellSelectionOverlay)
        // V3.6.35: 缩放优先级 选中 (1.025) > hover (1.02) > 默认
        //   按压 0.95 scale 撤销（避免跟 .draggable 抢事件）
        .scaleEffect(currentScale)
        // V4.4.2: 删除 resting shadow——这就是「浅框」幽灵的真正源头
        //   V3.1 引入「始终浮起感」: resting Elevation.subtle (radius=2, y=1, opacity=0.08)
        //   但 shadow 在 cell 四周扩散 2pt，在浅色 grid 间距上呈现为"一圈淡色光晕"
        //   = 用户感知的「浅框」（每个 cell 都有，无论选中与否）
        //
        // V4.4.3: hover shadow 与选中态互斥——「选中后的浅框」真凶
        //   用户点击 cell = 必然 hover → 选中后 isHovered=true → Elevation.strong
        //   shadow（12pt radius + 0.20 opacity）在 accent 边框周围扩散 12pt
        //   = 用户感知的「选中后出现的浅框」
        //   设计原则：选中已用 accent 边框明确指示，shadow 是 hover 反馈，
        //   选中时让 shadow 让位（!isActive && !isInMultiSelect 才显示）
        .shadow(
            color: shadowShowsHover ? Elevation.strong.color : .clear,
            radius: shadowShowsHover ? Elevation.strong.radius : 0,
            x: 0,
            y: shadowShowsHover ? Elevation.strong.y : 0
        )
        // V3.6.51: 单一 .animation 驱动所有选中状态过渡（之前 3 个独立 modifier）
        .animation(Animations.standard, value: selectionState)
        .animation(Animations.springGentle, value: isHovered)
        .animation(Animations.springGentle, value: isFocused)
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
        // V3.6.10: 键盘聚焦绑定（方向键导航时高亮）
        // V4.4.6: focusEffectDisabled(false) → true ——「点击后浅框」真凶
        //   旧 V3.6.10 显式启用系统 focus ring 给键盘导航视觉
        //   但鼠标点击也会触发 focus → 系统淡蓝发光环显示在 cell 周围
        //   = 用户看到的「点击后的浅框」
        //   选中状态已用 3pt accent strokeBorder 明确指示，再叠 focus ring 是双重视觉
        //   键盘导航可用 selectionState (selectedIDs/singleSelectedID) 体现，无需系统 ring
        .focused($isFocused)
        .focusable(true)
        .focusEffectDisabled(true)  // V4.4.6: 禁用系统 focus ring
        // V3.6.40: hover 动画升级 .standard → .springGentle（按压更"Q弹"感）
        // scaleEffect(currentScale) 在前面
        // animation 之前是 Animations.standard，现改 spring
        // 删除重复 .animation 块
        // V3.6.10: hover tooltip（文件名 + 尺寸 + 文件大小）
        .help(tooltipText)
        // 拖拽：支持内部文件夹移动 + 拖到 Finder 导出原图
        // V3.6.33: 迁移到 .draggable(URL) 现代 API
        //   - 旧 .onDrag + NSItemProvider 在 macOS 26.5 下行为异常（V3.6.27-V3.6.32 4 种 drag 全部失效）
        //   - .draggable + .dropDestination 是 SwiftUI 13+ 推荐的拖拽 API 对
        //   - URL 自带 Transferable，自动注册 public.file-url，Finder 直接拷原图
        //   - Sidebar 用 .dropDestination(for: URL.self) 接收后按 fileURL 查 photo
        //
        // V3.6.34: 关键修复
        // ─────────────────────────────────────────────────────────
        // .draggable 的 payload 是 @autoclosure @escaping，drag-start 时才求值
        // macOS 26.5 上 drag-start 可能在 background thread，SwiftData @Model
        // 属性访问（photo.fileURL）要求 main thread，会拿到 stale data 或失效
        // 修复：把 SwiftData @Model 属性 capture 到 local let，payload 闭包只
        // 返回已捕获的 URL 值（值类型，thread-safe），不再访问 @Model
        // preview 闭包里的 loadedImage (@State) 同理
        // 验证：用户用 10 行 .draggable 测试 view work，但 ImageGallery 不 work
        // → 区别就是 ImageGallery 用了 SwiftData @Model 属性作 payload
        // ─────────────────────────────────────────────────────────
        //
        // V3.6.30: 拖出语义决策
        // 本 .draggable 编码的是"被拖的那张"原图，**不**展开到整个 selectedIDs。
        // 这与 computeDragReorder 的"展开到整组"语义形成对比——
        // 本路径走 Finder 导出，单图语义与 Photos.app 一致：
        //   多选状态下拖任意一张 = 导出那一张（不是整组一起导出）
        .draggable(capturedFileURL) {
            // 拖动预览：缩略图（用已加载的 capturedPreviewImage 避免重读盘 + @State 访问）
            // V3.6.42: 加 shadow + 边框 + 放大到 96 + 旋转 1°（"被拿起"感）
            // V4.4.0: Radius.md → Radius.thumb 与 cell 本体圆角统一
            ZStack {
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Palette.cellBackground)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    )
                if let nsImage = capturedPreviewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .rotationEffect(.degrees(1))  // 微旋转加强"被拿起"感
        }
        // V3.6.37: 把 contextMenu + confirmationDialog 抽到独立 view
        //   原因：cell 主体 + 30+ modifier + 这两个复杂 modifier 让 Swift 编译器 type-check 超时
        //   V3.6.17/V3.6.23 教训：ContentView 110+ 行也踩过同样的坑
        //   解决：拆子 view，Swift 编译器每个 view 独立 type-check
        .background(
            EmptyView()
        )
        .modifier(CellContextMenuModifier(
            photo: photo,
            folders: folders,
            allTags: allTags,
            modelContext: modelContext,
            toggleTag: toggleTag,
            showingDeleteConfirm: $showingDeleteConfirm,
            onDelete: onDelete
        ))
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
        modelContext.saveWithLog()
    }
}

// V3.6.37: cell contextMenu 抽出独立 ViewModifier（V3.6.17/6.23 type-check timeout 教训）
struct CellContextMenuModifier: ViewModifier {
    let photo: Photo
    let folders: [Folder]
    let allTags: [Tag]
    let modelContext: ModelContext
    let toggleTag: (Tag, Photo) -> Void
    @Binding var showingDeleteConfirm: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Menu {
                Button {
                    photo.folder = nil
                    modelContext.saveWithLog()
                } label: {
                    Label("移出文件夹", systemImage: "tray")
                }
                if !folders.isEmpty {
                    Divider()
                }
                ForEach(folders) { folder in
                    Button {
                        photo.folder = folder
                        modelContext.saveWithLog()
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
                        toggleTag(tag, photo)
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

            // V4.16.0: 复制 + 在 Finder 中显示（macOS Photos 标配）
            //   之前 cell 缺这 2 个 macOS 标准 actions，用户多选到 detail panel
            //   才能找到这些——直接右键 cell 更快
            Button {
                // V4.16.0: 复制单张图片到剪贴板（photo.fileURL -> Data -> NSPasteboard）
                //   ContentView 已有 batch 路径 copyToPasteboard()，单张走相同 NSPasteboard API
                if let data = try? Data(contentsOf: photo.fileURL) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(data, forType: .png)
                    // 实际图片类型由 extension 决定——jpg/heic 不一定 .png
                    // V4.16.0: 简化只设 fileURL promise，让接受方读原文件
                    pasteboard.writeObjects([photo.fileURL as NSURL])
                }
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button {
                // V4.16.0: 在 Finder 中显示（NSWorkspace 桥接 macOS Finder）
                NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL])
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }

            Divider()

            Button {
                photo.isFavorite.toggle()
                modelContext.saveWithLog()
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
    }
}

#Preview {
    PhotoGridView(
        selection: .constant(SelectionState()),
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
        onClearFilters: {},  // V4.9.0
        onExportComplete: { _ in }
    )
    .frame(width: 600, height: 400)
}
