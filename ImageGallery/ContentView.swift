//
//  ContentView.swift
//  ImageGallery
//
//  主视图。整体布局：顶部工具栏 / 三栏布局 / 底部状态栏。
//  状态管理：选中、侧边栏、搜索、缩略图大小、可见列表、导入进度、多选。
//  支持：拖拽导入、Delete 键删除、方向键切换图片、启动记忆、导入进度。
//  多选：⌘+点击加选、⇧+点击范围选择、⌘+A 全选、⌥+拖动框选、Esc 取消。
//
//  V3.6.52: 重构选中状态——3 @State (selectedPhoto/selectedIDs/lastSelectedID) 合并为
//  1 @State<SelectionState>；`selectedPhoto: Photo?` 改为 computed（从
//  selection.singleSelectedID + visiblePhotos 派生）；5+ 处 `selectedIDs = []; selectedPhoto = nil`
//  收成 1 行 `selection = .empty`；5+ 处 `visiblePhotos.filter { selectedIDs.contains($0.id) }`
//  收成 1 行 `selection.selectedPhotos(in: visiblePhotos)`；3 个 O(n) lookup
//  (selectedPhoto/singleSelectedPhoto/currentIndex) 合并为 1 个 `resolvedSingle`。
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// 侧边栏选中项类型
enum SidebarSelection: Hashable {
    case all
    // V5.7: 砍 .favorites——收藏 = 评分 ≥ 5，访问走筛选 popover
    //   侧边栏只放主导航，不再掺杂筛选视图
    case unfiled
    case duplicates

    // V2: 智能文件夹
    case recent7Days       // 最近 7 天导入
    case largeFiles        // 大图 > 5MB

    case folder(Folder)
    case tag(Tag)

    // V3.6 NEW: 回收站
    case recentlyDeleted
}

struct ContentView: View {
    // V3.6.52: 3 @State (selectedPhoto/selectedIDs/lastSelectedID) 合并为 1 @State<SelectionState>
    //   这是图片选中的唯一真相源；`selectedPhoto: Photo?` 改为下面的 computed property
    @State private var selection = SelectionState()

    @State private var isBoxSelecting = false

    // 侧边栏的选中项
    @State private var sidebarSelection: SidebarSelection? = .all

    // V4.36.x: 工具栏筛选按钮状态（session-only，不写 UserDefaults / SwiftData）
    //   4 维：folders / tags / shapes / minRating
    //   与侧边栏并存补充——侧边栏选主上下文，筛选按钮叠加多选精细控制
    @State private var filterState = FilterState()

    // 搜索文本
    @State private var searchText = ""

    // 缩略图大小
    @State private var thumbnailSize: CGFloat = 200  // V5.16: 170→200 行高（更宽裕视觉）
    // V3.6.13: 保留 @State 用 toolbar 临时调，onChange 同步 stored
    // V3.6.13: viewMode 改用 @AppStorage 持久化（SettingsView 可设默认）
    @AppStorage("viewModeRaw") private var viewModeRaw: String = ViewMode.grid.rawValue
    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .grid }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    // 排序方式（Eagle 化工具栏新增）
    @State private var sortOption: SortOption = .filenameAsc  // V5.31: importedAtDesc → filenameAsc (无 date header 默认)

    // V4.36.6: visiblePhotos 从 @State 改为 computed property
    //   旧 @State + onVisiblePhotosChange 模式只服务于 grid view——切到 list/timeline 不更新
    //   改 computed property 用 PhotoStats.filtered 共享 helper, 3 视图同步
    // 注: 侧栏 section 折叠状态 (@AppStorage) 属于 SidebarView 持有, 不在此

    /// V4.36.6: 当前可见图片——PhotoStats.filtered 计算
    /// 3 视图（grid/list/timeline）共用同一份 filtered 列表
    /// V4.36.x: 加 4 参（工具栏筛选 4 维：folder multi / tag multi / shape / rating）
    private var visiblePhotos: [Photo] {
        PhotoStats.filtered(
            allPhotos,
            folder: currentFolder,
            tag: currentTag,
            searchText: searchText,
            sortOption: sortOption,
            // V5.8: 砍 filterFavorites——V5.7 砍 .favorites 侧边栏后 dead
            filterUnfiled: filterUnfiled,
            filterDuplicates: filterDuplicates,
            filterRecent7Days: filterRecent7Days,
            filterLargeFiles: filterLargeFiles,
            filterInTrash: filterInTrash,
            // V4.36.x: 工具栏筛选 4 维
            selectedFolderIDs: filterState.folders,
            selectedTagIDs: filterState.tags,
            selectedShapes: filterState.shapes,
            minRating: filterState.minRating
        )
    }

    // 拖拽状态
    @State private var isDropTargeted = false

    // 导入进度
    @State private var importProgress: ImportProgress?

    // 批量删除确认
    @State private var showingBatchDeleteConfirm = false

    // V3.6.6: 清空回收站二次确认（防误操作：永久删除所有 trashed 项）
    @State private var showingEmptyTrashConfirm = false

    // V3.6.24: 导入时重复检测 dialog（防止 fileHash 重复的图片被再次导入）
    @State private var importDuplicateCheck: ImageImporter.DuplicateCheckResult?
    @State private var pendingImportURLs: [URL] = []

    // 批量移动
    // （showingBatchMoveSheet 已移除：批量移动流程当前在 PhotoGridView 内联实现，
    //   该状态从未被读。如未来要重新走 sheet 流程再加回。）

    // 新建文件夹弹窗
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""

    // 沉浸式查看
    @State private var immersivePhoto: Photo?
    @State private var immersiveIndex: Int = 0

    // 栏显隐状态（ContentView 唯一持有，ImageGalleryApp 通过 UserDefaults 同步）
    @AppStorage("showSidebar") private var showSidebar = true
    // V5.22: 默认 showDetail = false——grid 窗口右侧 30% 留给图片而不是空 detail panel
    //   老用户 @AppStorage 有 stored showDetail=true 不受影响（仅新装/重置生效）
    //   选照片时仍可在 onChange 触发自动 show（V5.22 后续 sprint 加）——目前只改默认
    @AppStorage("showDetail") private var showDetail = false

    // V4.13.0: 撤回 V3.5.18 旧 @State showSettings——⌘, 现在走 Settings scene
    //   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 状态
    @AppStorage("accentColorID") private var accentColorID: String = AccentColor.system.rawValue

    // V3.6 NEW: 回收站保留时长（默认 30 天）
    @AppStorage("trashRetentionDays") private var retentionDays: Int = TrashRetentionDays.defaultValue.rawValue

    // V3.6.22: 应用外观（默认跟随系统）
    @AppStorage("appearanceMode") private var appearanceModeRaw: Int = AppearanceMode.defaultValue.rawValue
    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    // V3.6 NEW: 启动时清理过期回收站项的"只跑一次"标记
    // ContentView 可能多次出现（开关窗口、切 sidebar），用 flag 避免重复清理
    @State private var hasPurgedExpiredTrash = false

    // V4.11.0: 存储不可写错误（nil = 正常）
    //   onAppear 调 PhotoStorage.verifyStorage()——失败时填错误消息，detail panel 显示错误态
    @State private var storageErrorMessage: String? = nil

    // V4.12.0: 空格键 QuickLook——macOS Finder/Photos 标准
    //   controller 通过 .background(QuickLookBridge) 接管 QLPreviewPanel
    //   currentVisibleURLs 跟随 visiblePhotos 变化（每次访问重算）
    //   @State 而非 @StateObject：controller 内部状态不需 SwiftUI 监听
    @State private var quickLookController = QuickLookPreviewController()

    // V4.37.4: titlebar 右上角小按钮引用——@State 持 NSObject 引用
    //   onChange(of: showDetail) 时调 setActive / setTooltip 同步状态
    //   configureNSToolbar 内构造（一次），SwiftUI 重渲不重新构造（@State 持久）
    @State private var titlebarAccessory: TitlebarAccessoryController?

    // V4.20.0: 撤回 V4.19.0 glassNamespace + glassEffectUnion
    //   macOS 26 glassEffectUnion 在 sidebar 边界外产生 outline 痕迹（用户截图反馈）
    //   回滚到 V4.18.0 单 view glassEffect 状态（仅 SidebarView/DetailView 4 处 .glassEffect）

    /// V4.12.0: 当前 visiblePhotos 对应的 URL 列表（空格键 QuickLook 翻页用）
    private var currentVisibleURLs: [URL] {
        visiblePhotos.map { $0.fileURL }
    }

    // 当前选中的强调色（从 accentColorID 解析）
    private var accentColor: AccentColor {
        AccentColor(rawValue: accentColorID) ?? .system
    }

    // Toast 提示（队列——V5.13 升级）
    @State private var toastQueue: [ToastInfo] = []
    @State private var toastTask: Task<Void, Never>?

    // SwiftData：获取所有图片（用于状态栏显示总数）
    @Query private var allPhotos: [Photo]
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]
    @Query(sort: \Tag.createdAt, order: .forward) private var allTags: [Tag]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext

    // V3.5 Phase 1 Step 4：撤销/重做（@Observable + @State 模式）
    @State private var undoManager = ImageGalleryUndoManager()

    // 启动记忆
    // V5.30: 240pt → 200pt 默认
    //   - V5.20 设 240pt 是"Photos Library 容器更大"——但实际是单图视觉权重而非 grid 密度
    //   - macOS Photos.app Library 默认 cell 边长 ~180-200pt, 更密集
    //   - 240pt 太稀 (3-4 cell/row), 200pt 是 Photos 真版 (4-5 cell/row, 1188pt 窗口)
    //   - 4 cell 档仍可切: compact 70 / small 110 / medium 200 / large 240
    //   - 老用户 @AppStorage 已有 storedThumbnailSize 不受影响 (仅新装/重置生效)
    @AppStorage("thumbnailSize") private var storedThumbnailSize: Double = 200  // V5.30: 240→200 (Photos 真版密度)
    @AppStorage("sidebarSelection") private var storedSidebarKey: String = "all"
    // V5.31: 默认 sort 改 filenameAsc——Photos.app Library 视图无 date header
    //   - 之前 importedAtDesc → isDateBased=true → DateSectionHeader 显示
    //   - Photos 真版: Library 连续流, 无 date section
    //   - 改 filenameAsc: 字母序, isDateBased=false → masonryFlatLayout (无 header)
    //   - 老用户 @AppStorage 已有 storedSortOption 不受影响 (仅新装/重置生效)
    @AppStorage("sortOption") private var storedSortOption: String = SortOption.filenameAsc.rawValue  // V5.31: importedAtDesc → filenameAsc
    // V5.17: 缩略图布局模式（3 选项 .square / .masonry / .masonryStretch）
    //   镜像 AppearanceMode Int-backed pattern
    //   @AppStorage 持久化 + computed 读写 + 透传给 ViewOptionsPopover/PhotoGridPane
    //   nonmutating set 必备——否则 closure 内 [self] capture 后 setter 改 self 编译失败
    @AppStorage("thumbnailLayoutMode") private var storedLayoutModeRaw: Int = ThumbnailLayoutMode.defaultValue.rawValue
    private var layoutMode: ThumbnailLayoutMode {
        get { ThumbnailLayoutMode(rawValue: storedLayoutModeRaw) ?? .defaultValue }
        nonmutating set { storedLayoutModeRaw = newValue.rawValue }
    }

    // V3.5.12：三栏列宽（HStack + 自定义 drag handles，避开 NSSplitView）
    @AppStorage("sidebarColumnWidth") private var storedSidebarWidth: Double = 220
    @AppStorage("detailColumnWidth") private var storedDetailWidth: Double = 360
    @State private var sidebarColumnWidth: CGFloat = 220
    @State private var detailColumnWidth: CGFloat = 360
    @State private var sidebarDragStartWidth: CGFloat = 220
    @State private var detailDragStartWidth: CGFloat = 360
    private let sidebarMinWidth: CGFloat = 160
    private let sidebarMaxWidth: CGFloat = 320
    // V4.35.x 修复: 3 个按钮等分 (收藏/在 Finder 中显示/删除) 至少需要 ~360pt
    //   旧 240pt → 3 按钮 80pt/个 → "在 Finder 中显示" 7 字 + icon 完全装不下 → 右侧被切
    private let detailMinWidth: CGFloat = 340
    private let detailMaxWidth: CGFloat = 480
    private let contentMinWidth: CGFloat = 400

    // 当前的筛选条件
    private var currentFolder: Folder? {
        if case .folder(let folder) = sidebarSelection { return folder }
        return nil
    }

    private var currentTag: Tag? {
        if case .tag(let tag) = sidebarSelection { return tag }
        return nil
    }

    // V5.8: 砍 filterFavorites property——V5.7 砍 .favorites 侧边栏后此 property 永远 false
    //   用户想看"收藏"改走筛选 popover (评分 ≥ 5)

    private var filterUnfiled: Bool {
        if case .unfiled = sidebarSelection { return true }
        return false
    }

    private var filterDuplicates: Bool {
        if case .duplicates = sidebarSelection { return true }
        return false
    }

    private var filterRecent7Days: Bool {
        if case .recent7Days = sidebarSelection { return true }
        return false
    }

    private var filterLargeFiles: Bool {
        if case .largeFiles = sidebarSelection { return true }
        return false
    }

    // V3.6 NEW: 回收站筛选
    private var filterInTrash: Bool {
        if case .recentlyDeleted = sidebarSelection { return true }
        return false
    }

    // V3.6.15 NEW: 重复图筛选（用于 .duplicates 视图的 count/totalSize 区分）
    private var filterInDuplicates: Bool {
        if case .duplicates = sidebarSelection { return true }
        return false
    }

    // 派生属性
    // V3.6.52: 3 个 O(n) lookup (selectedPhoto + singleSelectedPhoto + currentIndex) 合并为 1 个
    //   之前每次 body 重算要做 2-3 遍 visiblePhotos.first(where:) / firstIndex(where:)
    //   现在用 selection.singleSelectedID + 一次 firstIndex 扫描，photo 和 index 一起拿
    //
    // 返回 (photo, visibleIndex)——photo 供 DetailPane 用，visibleIndex 供 currentIndex 用
    private var resolvedSingle: (photo: Photo, visibleIndex: Int)? {
        guard let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return (visiblePhotos[idx], idx)
    }

    /// V3.6.52：单选 photo（DetailPane.singleSelectedPhoto 用）
    /// selection.singleSelectedID 已涵盖多选强制 nil 的语义，无需 `!isMultiSelect` 守卫
    private var singleSelectedPhoto: Photo? {
        resolvedSingle?.photo
    }

    // V3.6.52 优化：currentIndex 复用 resolvedSingle 的索引，0 遍额外 lookup
    private var currentIndex: Int {
        (resolvedSingle?.visibleIndex ?? -1) + 1
    }

    private var canPrev: Bool { currentIndex > 1 }
    private var canNext: Bool { currentIndex > 0 && currentIndex < visiblePhotos.count }

    // 多选模式（>1 张）
    // V3.6.52: 改用 selection 上的派生属性
    private var isMultiSelect: Bool { selection.isMultiSelect }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    // V3.5.6 Finder 化：总占用空间格式化
    private var totalSizeFormatted: String {
        let bytes = PhotoStats.totalSize(allPhotos)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // V4.2.0 P0❸: 当前 sidebar 选项的可读名（用作 navigationTitle）
    //   hidden title bar 模式下不显示在窗口顶部，但作为窗口元数据进入：
    //   - Dock 右键菜单的窗口名
    //   - ⌘⇥ 切换器的窗口名
    //   - Mission Control 的标签
    //   - VoiceOver 念出的窗口标题
    private var currentViewTitle: String {
        switch sidebarSelection {
        case .all, .none:           return "全部照片"
        // V5.7: 砍 .favorites 侧边栏项——case 移除
        case .unfiled:              return "待整理"
        case .duplicates:           return "重复图"
        case .recent7Days:          return "最近 7 天"
        case .largeFiles:           return "大图（>5MB）"
        case .recentlyDeleted:      return "回收站"
        case .folder(let f):        return f.name
        case .tag(let t):           return "#\(t.name)"
        }
    }

    // V4.2.0 P0❸: 副标题——"N 张 · X MB"
    //   visiblePhotos.count 是当前筛选+排序后实际显示的数量；优于 allPhotos.count
    //   V4.36.x: 工具栏筛选激活时追加 "· 已筛选 (N)" 提示
    private var currentViewSubtitle: String {
        let count = visiblePhotos.count
        let bytes = visiblePhotos.reduce(Int64(0)) { $0 + $1.fileSize }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        var s = "\(count) 张 · \(size)"
        if filterState.isActive {
            s += " · 已筛选 (\(filterState.activeCount))"
        }
        return s
    }

    // V4.4.8: toolbar 搜索框左 padding 动态计算
    //   让 search 左缘与下方主内容区（grid）左缘对齐——形成 toolbar 与
    //   content 之间的视觉锚线。Eagle / Lightroom / Photos 等图片管理 app 同款。
    //   - sidebar 可见时：padding = sidebarColumnWidth - sidebar toggle 占用宽度
    //     toggle 占用 ≈ 64pt（toggle button 40pt + 系统 spacing 8pt + 边距 16pt）
    //   - sidebar 隐藏时：仅留 12pt 与 sidebar toggle 视觉分开
    private var searchFieldLeadingOffset: CGFloat {
        guard showSidebar else { return 12 }
        let togglePlusSpacing: CGFloat = 64
        return max(12, sidebarColumnWidth - togglePlusSpacing)
    }

    // V3.5.19：当前选中图片的总大小（字节）
    // 用于多选详情面板显示 "已选 N 张 · 12.3 MB"
    // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
    private var selectedTotalSize: Int64 {
        selection.selectedPhotos(in: visiblePhotos)
            .reduce(0) { $0 + $1.fileSize }
    }

    // V3.6 NEW: 回收站视图用的 count + totalSize
    // DetailPane 在 .recentlyDeleted 模式下显示这两个值
    // V3.6.1：用 PhotoStats 纯函数（之前在 SidebarView 也重复算过 trashed）
    private var trashedCount: Int {
        PhotoStats.trashed(allPhotos).count
    }

    private var trashedTotalSize: Int64 {
        PhotoStats.trashedSize(allPhotos)
    }

    // V3.6.15 NEW: 重复图视图用的 group count + purgeable count + size
    // DetailPane 在 .duplicates 模式下显示这些值
    /// 重复组数（fileHash 相同且 ≥ 2 张）
    private var duplicateGroupCount: Int {
        PhotoStats.duplicateGroups(in: visiblePhotos).count
    }

    /// 可清理照片数（每组保留最新，其他）
    private var duplicatePurgeableCount: Int {
        PhotoStats.duplicatesToPurge(in: visiblePhotos).count
    }

    /// 可清理照片总大小
    private var duplicatePurgeableSize: Int64 {
        PhotoStats.duplicatesToPurge(in: visiblePhotos).reduce(0) { $0 + $1.fileSize }
    }

    // V3.5.17：把 6 个宽度 state vars + 4 个约束 + 2 个 AppStorage 钩子打包
    // 给 MainSplitView 使用
    private var columnLayout: ColumnLayoutState {
        ColumnLayoutState(
            sidebarColumnWidth: $sidebarColumnWidth,
            detailColumnWidth: $detailColumnWidth,
            sidebarDragStartWidth: $sidebarDragStartWidth,
            detailDragStartWidth: $detailDragStartWidth,
            sidebarMinWidth: 160,
            sidebarMaxWidth: 320,
            detailMinWidth: 340,  // V4.35.x 修复: 旧 240 → 3 按钮被切
            detailMaxWidth: 480,
            onSidebarDragEnd: { storedSidebarWidth = Double(sidebarColumnWidth) },
            onDetailDragEnd: { storedDetailWidth = Double(detailColumnWidth) },
            restoreFromStorage: {
                sidebarColumnWidth = CGFloat(storedSidebarWidth)
                // V4.35.x 修复: 旧值 < 340pt 时升到 340pt（避免窄 detail panel 切按钮）
                let restored = CGFloat(storedDetailWidth)
                detailColumnWidth = max(restored, 340)
            }
        )
    }

    var body: some View {
        mainLayout
            // V4.10.0: 6 个 chrome modifier 打包（title/subtitle/colorScheme/WindowAccessor/NSToolbar sync）
            // V5.24: 加 layoutMode + thumbnailSize 参数——传给 windowChromeAndToolbar 推 NSToolbar segment/slider
            .windowChromeAndToolbar(
                title: currentViewTitle,
                subtitle: currentViewSubtitle,
                colorScheme: appearanceMode.colorScheme,
                selection: selection,
                searchText: searchText,
                layoutMode: layoutMode,
                thumbnailSize: thumbnailSize,
                configureWindow: { configureNSToolbar(window: $0) }
            )
            // V4.10.0: app lifecycle hooks（.onAppear + 6 个 .onChange 打包）
            //   避免 body 链超长触发 type-check 超时
            .appLifecycleHooks(
                thumbnailSize: thumbnailSize,
                sidebarSelection: sidebarSelection,
                sortOption: sortOption,
                viewModeRaw: viewModeRaw,
                storedThumbnailSize: storedThumbnailSize,
                storedSortOption: storedSortOption,
                onAppear: {
                    thumbnailSize = CGFloat(storedThumbnailSize)
                    sidebarSelection = restoreSelection(storedSidebarKey)
                    sortOption = SortOption(rawValue: storedSortOption) ?? .filenameAsc  // V5.31
                    // V3.6 NEW: 启动时清理过期回收站项（只跑一次）
                    if !hasPurgedExpiredTrash {
                        hasPurgedExpiredTrash = true
                        purgeExpiredTrashOnStartup()
                    }
                    // V4.11.0: 检测 Application Support 可写性（v3.6 死代码接入）
                    checkStorage()
                    // V5.8: 一次性数据迁移——isFavorite=true 的照片 rating 升到 5
                    //   收藏 = 评分 ≥ 5 语义合并——历史数据对齐
                    Photo.migrateFavoriteToRating(in: allPhotos, context: modelContext)
                },
                onStoredThumbnailChange: { thumbnailSize = CGFloat($0) },
                onStoredSortChange: { sortOption = SortOption(rawValue: $0) ?? .filenameAsc },  // V5.31
                onThumbnailChange: { storedThumbnailSize = Double($0) },
                onSidebarSelectionChange: { new in
                    storedSidebarKey = serializeSelection(new)
                    // V4.1.0 l: 切换侧栏 section 同时清选中（避免"选中的照片不在新 section"）
                    clearSelectionOnFilterChange()
                },
                onSortOptionChange: { storedSortOption = $0.rawValue }
            )
            // V4.10.0: grid input handling（.onDeleteCommand + .focusable + 6 .onKeyPress 打包）
            .gridInputHandling(
                canPrev: canPrev,
                canNext: canNext,
                hasSelection: !selection.isEmpty,
                onDelete: handleDelete,
                onPrev: goPrev,
                onNext: goNext,
                onEscape: { selection = .empty },
                onSelectAll: { selection = selection.settingAll(in: visiblePhotos) },
                onZoomIn: zoomIn,
                onZoomOut: zoomOut,
                // V4.12.0: 空格键 QuickLook——仅选中单张时生效
                //   V4.37.1: 抽出到 showQuickLook()——⌘Y 菜单 / toolbar 按钮复用同一路径
                //   计算 currentIndex (visiblePhotos 内的位置) + 整个 URL 列表
                //   让 QLPreviewPanel 支持 ←→ 翻页（Photos.app 行为）
                hasSelectedPhoto: singleSelectedPhoto != nil,
                onSpace: showQuickLook,
                // V4.15.0: ⌘0 reset zoom（macOS Photos/Finder 标准）
                //   恢复 thumbnailSize 到用户偏好（storedThumbnailSize）
                onResetZoom: resetThumbnailSize,
                // V4.17.0: ⌘E 导出（macOS Finder 标准）—— 走 batchExport 路径
                onExport: batchExport,
                // V4.49.1: ⌘↩ Return 进入沉浸式查看（macOS Photos 标准）
                //   仅在选中单张时生效——多选/无选 .ignored
                //   Photos.app 用 Return/Enter 进入全屏图片查看
                onReturn: enterImmersiveFromSelection
            )
            // V4.12.0: QLPreviewBridge 注入 view tree——SwiftUI 不显示（透明 NSView）
            //   但参与 firstResponder 链，让 QLPreviewPanel 接管时能找到接管 view
            .background(QuickLookBridge(controller: quickLookController))
            // 快捷键：⌘+1-6 切换侧边栏
            .contentKeyboardShortcuts(
                sidebarSelection: $sidebarSelection,
                onImport: startImport,
                onNewFolder: { showingNewFolderAlert = true },
                onResetFilters: resetFilters,
                // V5.7: 砍 onToggleFavorite——工具栏 ❤ 收藏按钮已移除
                onCopy: copyToPasteboard,
                onToggleSortDirection: toggleSortDirection,
                onToggleSidebar: { showSidebar.toggle() },
                // V5.12: ⌘0-⌘5 评分快捷键
                //   单选 → 设该照片；多选 → 批量设所有选中照片；无选中 → no-op
                onSetRating: { rating in batchSetRating(rating) },
                // V4.15.0: ⌘F 聚焦搜索框改由 NSSearchField (V4.8.1) 自身处理
                //   撤回 V3.6.23 旧 notification 桥接——onFocusSearch 用默认 {} 空实现
                //   contentKeyboardShortcuts 仍调 onFocusSearch（参数保留避免破坏）
            )
            // V4.10.0: 4 dialog 打包（batchDelete / newFolder / emptyTrash / duplicate）
            .batchActionDialogs(
                showingBatchDelete: $showingBatchDeleteConfirm,
                batchDeleteTitle: batchDeleteTitle,
                retentionDays: retentionDays,
                onConfirmBatchDelete: batchDelete,
                showingNewFolder: $showingNewFolderAlert,
                newFolderName: $newFolderName,
                onConfirmNewFolder: createFolderFromAlert,
                showingEmptyTrash: $showingEmptyTrashConfirm,
                onConfirmEmptyTrash: emptyTrash,
                showingDuplicateCheck: showingDuplicateCheck,
                duplicateDialogTitle: duplicateDialogTitle,
                onConfirmSkipDuplicates: confirmSkipDuplicates,
                onConfirmImportAllDuplicates: confirmImportAllDuplicates,
                onCancelDuplicateImport: cancelDuplicateImport
            )
            // V4.13.0: 撤回 V3.5.18 sheet 路径——⌘, 现在走 Settings scene 独立窗口
            //   applySettingsChrome 简化为只应用强调色（.tint + .environment(\.appAccent)）
            .applySettingsChrome(tintColor: accentColor.color)
            // V4.7.0: 暴露 undoManager 给 Edit menu commands
            //   抽到 extension（exposeUndoManager）避免 body 链过长触发 type-check 超时
            .exposeUndoManager(undoManager)
            // V4.36.x: 工具栏筛选按钮 → 角标 tooltip 同步
            //   filterActiveCount 变化时推送到 NSToolbar item.tooltip
            //   onChange 不在初始化时触发——configureNSToolbar 闭包内首次手动 push
            .onChange(of: filterState.activeCount) { _, count in
                ToolbarController.shared.filterActiveCount = count
            }
            // V4.36.x: 切换筛选条件时清选中（仿 clearSelectionOnFilterChange L1114-1119）
            //   避免"选中的照片不在新筛选结果里"
            .onChange(of: filterState) { _, newState in
                if !selection.isEmpty {
                    selection = .empty
                }
                // V4.94.0: 删 .filterStateChangedFromOutside 通知
                //   V4.90.0 Coordinator 直接接收 onStateChange——通知机制已不需要
                //   旧 FilterPopoverViewController.swift 删后，notification 名 extension 消失
            }
            // V4.37.4: 同步 showDetail 状态到 titlebar accessory
            //   三个入口（titlebar 按钮 / ⌘I 菜单 / ⌘Ctrl+D 菜单）toggle 同一 @AppStorage
            //   onChange 推到 accessory.setActive / setTooltip 让按钮反映真实状态
            //   仿 V4.36.x Filter 按钮 filterActiveCount didSet → updateFilterBadge 模式
            .onChange(of: showDetail) { _, newValue in
                titlebarAccessory?.setActive(newValue)
                titlebarAccessory?.setTooltip(titlebarAccessoryTooltip(isActive: newValue))
            }
            // V5.23: 选照片自动 showDetail / deselect 自动 hide
            //   V5.22 默认 showDetail=false——无选中时 grid 100% 占窗口
            //   但选 1 张时希望自动展开 detail 看 metadata
            //   手动 toggle (⌘Ctrl+D / titlebar 按钮) 仍优先——onChange 只在自动路径触发
            //   V5.23 镜像 Mac Photos 行为：选即显，取消即隐
            .onChange(of: selection.hasSelection) { _, hasSelection in
                withAnimation(Animations.medium) {
                    showDetail = hasSelection
                }
            }
    }

    // V4.0.0: 抽出 importDuplicateCheck 状态到 binding（让 type-check 过得去）
    // 之前 inline Binding get/set 触发 "unable to type-check in reasonable time"
    private var showingDuplicateCheck: Binding<Bool> {
        Binding(
            get: { importDuplicateCheck != nil },
            set: { if !$0 { importDuplicateCheck = nil } }
        )
    }

    // V4.0.0: 抽出批量删除确认 title（避免 body 内 string interpolation 触发 type-check 超时）
    private var batchDeleteTitle: String {
        "确定要删除 \(selection.selectedIDs.count) 张图片吗？"
    }

    // V4.8.0: NSToolbar 配置（WindowAccessor 触发）
    //   - 设置 window.toolbar = NSToolbar（AppKit 原生，Photos.app 风格）
    //   - 设置 NSToolbar.delegate = ToolbarController.shared
    //   - 设置 NSToolbar 视觉：.iconOnly display + .unified style
    //   - 绑 action closures（SwiftUI → AppKit action bridge）
    private func configureNSToolbar(window: NSWindow) {
        // 只在第一次设置
        guard window.toolbar == nil else { return }

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        toolbar.delegate = ToolbarController.shared
        toolbar.displayMode = .iconOnly
        // V4.8.3: centeredItemIdentifiers = [.search] 让搜索框居中
        //   (Photos.app 风格——搜索框与 grid 中线对齐)
        //   5 actions 走默认 .principalItems 区域，在 trailing 端
        toolbar.centeredItemIdentifiers = [ToolbarController.Identifier.search.nsIdentifier]
        toolbar.allowsUserCustomization = true   // 用户可自定义 toolbar items
        toolbar.autosavesConfiguration = true   // 自定义状态自动保存
        toolbar.showsBaselineSeparator = false  // 不显示底部分隔线

        // 绑 action closures
        //   ContentView 是 value type——strong capture 是值复制，无 reference cycle
        //   (用 [weak self] 需要 class-bound，struct 不行)
        let controller = ToolbarController.shared
        controller.onToggleSidebar = { [self] in
            withAnimation(Animations.medium) { showSidebar.toggle() }
        }
        // V5.7: 砍 onToggleFavorite——工具栏 ❤ 收藏按钮已移除
        controller.onBatchExport = { [self] in
            batchExport()
        }
        controller.onDelete = { [self] in
            handleDelete()
        }
        controller.onImport = { [self] in
            startImport()
        }
        // V4.37.1: ⌘Y Quick Look——复用 showQuickLook()（与空格键同路径）
        //   onQuickLook toolbar 按钮 + ⌘Y 菜单项共用这一个 closure
        controller.onQuickLook = { [self] in
            showQuickLook()
        }
        // V4.37.2: ⌘[ / ⌘] 上下张切换（macOS Quick Look 标准）
        //   菜单项 ⌘[/⌘] 通过 ToolbarController.onPrev/onNext closures 触发
        controller.onPrev = { [self] in
            goPrev()
        }
        controller.onNext = { [self] in
            goNext()
        }
        // V5.24 NEW: 布局模式 + 密度 toolbar 集成桥接
        //   用户点 NSToolbar segment/slider → ToolbarController 回调
        //   → 这里写回 @AppStorage（layoutMode + thumbnailSize）
        //   SwiftUI 监听 .onChange → 重算 grid layout
        controller.onLayoutModeChange = { [self] mode in
            layoutMode = mode
        }
        controller.onDensityChange = { [self] density in
            thumbnailSize = density
            // 同步 storedThumbnailSize 以便重启后恢复（V4.15.0 ⌘0 行为一致）
            storedThumbnailSize = Double(density)
        }
        // V4.9.1: View Options 改用 NSPopover + NSHostingController
        //   之前 V4.8.0 NSToolbar 迁移时丢了 .popover modifier——只 toggle showViewOptions 无效
        //   现在 ToolbarController.handleShowViewOptions 内部直接 NSPopover.show
        //   contentProvider 提供 NSHostingController(rootView: ViewOptionsPopover(...))
        //   viewMode 是 @AppStorage 的 computed property——用 Binding(get:set:) 构造 binding
        controller.viewOptionsContentProvider = { [self] in
            // V4.77.0: 改用 ViewOptionsPopoverHostController (NSVisualEffectView 包裹)
            //   与 FilterPopoverViewController 完全一致的 transl 行为
            //   之前 V4.9.1 .background(.clear) 让 NSPopover 自动 transl——与 FilterPopover transl 行为不一致（用户反馈）
            // V5.17: 加 thumbnailLayoutMode binding 传 3 模式布局切换
            ViewOptionsPopoverHostController(swiftUIView: ViewOptionsPopover(
                viewMode: Binding(
                    get: { self.viewMode },
                    set: { self.viewMode = $0 }
                ),
                thumbnailSize: $thumbnailSize,
                // V5.17: thumbnailLayoutMode 在 sortOption 之前（ViewOptionsPopover init 顺序）
                thumbnailLayoutMode: Binding(
                    get: { self.layoutMode },
                    set: { self.layoutMode = $0 }
                ),
                sortOption: $sortOption
            ))
        }
        // V4.36.x: Filter popover provider——纯 AppKit FilterPopoverViewController
        //   弃用 SwiftUI FilterPopover + NSHostingController（intrinsic size 协商不可控）
        //   AppKit controller 直接 preferredContentSize，NSPopover 读这个值
        //   state 变化通过 onStateChange 回调同步（双向）
        //   V4.36.x #4: 还接 onClearAll 回调 + filterStateChangedFromOutside 通知
        // V4.90.0: filterContentProvider 改 filterCoordinatorFactory——coordinator 接管 lifecycle
        //   coordinator 内置 顶层 + 4 子 popover 强引用
        //   onStateChange: 写回 ContentView @State filterState
        controller.filterCoordinatorFactory = { [self] onStateChange in
            return FilterPopoverCoordinator(
                folders: folders,
                tags: allTags,
                onStateChange: { newState in
                    self.filterState = newState
                    onStateChange(newState)
                }
            )
        }
        // V4.36.x: 首次同步角标（onChange 不会在初始化时触发，必须手动 push）
        controller.filterActiveCount = filterState.activeCount
        // V4.8.1: search field 改用 NSSearchField (AppKit 原生) 替代 SwiftUI 自绘
        //   NSSearchField 由 ToolbarController.makeSearchItem 创建
        //   这里只绑 text 变化 closure 同步到 SwiftUI @State
        controller.onSearchTextChanged = { [self] newText in
            // NSSearchField 文本变化 → SwiftUI @State 同步
            // 避免无限循环：SwiftUI @State → setSearchText 时检查值是否相同
            if searchText != newText {
                searchText = newText
            }
        }

        window.toolbar = toolbar
        window.toolbarStyle = .unified  // V4.8.0: Photos.app 风格 (unified 比 unifiedCompact 视觉更原生)
        // window title 隐藏——toolbar 顶到窗口顶部
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        // V4.37.4: titlebar 右上角小按钮（Photos.app ⓘ 风格 + 状态感知）
        //   V4.37.3 基础上加 setActive / setTooltip——保持与 V4.36.x Filter 按钮 didSet 模式统一
        //   - 双 symbol: info.circle (inactive) ↔ info.circle.fill (active)
        //   - tint: 系统默认 ↔ .controlAccentColor（按下时变蓝，Photos.app 同款）
        //   - tooltip: 动态反映当前操作 + ⌘I 快捷键提示
        //   NSToolbar 在 toolbar 区域，titlebar accessory 在 titlebar 区域
        //   layoutAttribute = .trailing = 紧邻交通灯右侧
        //   withAnimation 让切换有平滑过渡（V4.8.0 侧边栏 toggle 模式）
        //   V4.20.0 撤回 V4.19.0 glassEffectUnion 后，titlebar 不参与玻璃融合——独立按钮
        let accessory = TitlebarAccessoryController(
            inactiveSymbol: "info.circle",
            activeSymbol: "info.circle.fill",
            accessibilityLabel: "信息面板",
            tooltip: titlebarAccessoryTooltip(isActive: showDetail),
            onAction: { [self] in
                withAnimation(Animations.medium) { showDetail.toggle() }
            }
        )
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
        // V4.37.4: @State 持引用（NSObject 引用类型可被 @State 管）——.onChange 时同步状态
        titlebarAccessory = accessory
        accessory.setActive(showDetail)

        // 初始 enabled 状态同步
        controller.updateAllStates(
            hasSelection: selection.hasSelection,
            hasMultipleSelection: selection.isMultiSelect
        )
    }

    // V4.11.0: 检查 Application Support/ImageGallery/Photos/ 目录可写性
    //   失败时填 storageErrorMessage 触发 detail panel 错误态
    //   用户可点重试按钮再次检测（磁盘腾出空间 / 权限恢复后）
    //   PhotoStorage.verifyStorage() 是 v3.6 写但从未调用的死代码——v4.11.0 接入
    private func checkStorage() {
        if PhotoStorage.shared.verifyStorage() {
            storageErrorMessage = nil
        } else {
            storageErrorMessage = "无法写入存储目录。请检查磁盘空间、权限或「系统设置 → 隐私与安全 → 文件与文件夹」授权。"
        }
    }

    // ⌘N 触发的创建文件夹
    private func createFolderFromAlert() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = Folder(name: trimmed)
        modelContext.insert(folder)
        modelContext.saveWithLog()
        sidebarSelection = .folder(folder)
    }

    // 隐藏的快捷键按钮（.background 注入，不可见但响应快捷键）
    // 切换当前排序方向（在同字段的 asc/desc 之间切换）
    private func toggleSortDirection() {
        sortOption = sortOption.toggledDirection
    }

    // V3.5 Phase 1 Step 3：分享选中的照片
    // 使用 macOS 系统分享面板（NSSharingServicePicker）
    // 可选：AirDrop / 信息 / 邮件 / 备忘录 / 第三方 App 等
    private func shareSelected() {
        // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
        let urls: [URL]
        if !selection.selectedIDs.isEmpty {
            urls = selection.selectedPhotos(in: visiblePhotos).map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            urls = [photo.fileURL]
        } else {
            return  // 没有选中
        }

        let picker = NSSharingServicePicker(items: urls)
        let view = NSApp.keyWindow?.contentView ?? NSView()
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    // 复制到剪贴板（支持多选）
    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // 收集所有要复制的文件 URL
        // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
        let urls: [URL]
        if !selection.selectedIDs.isEmpty {
            // 多选：复制所有选中
            urls = selection.selectedPhotos(in: visiblePhotos).map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            // 单选：复制单张
            urls = [photo.fileURL]
        } else {
            return  // 没有选中
        }

        // 写入剪贴板
        pasteboard.writeObjects(urls as [NSURL])
        showToast(urls.count == 1 ? "已复制 1 张图片" : "已复制 \(urls.count) 张图片", type: .success)
    }

    // 进入沉浸式查看（双击图片触发）
    private func enterImmersive(_ photo: Photo) {
        if let idx = visiblePhotos.firstIndex(where: { $0.id == photo.id }) {
            immersiveIndex = idx
            immersivePhoto = photo
        }
    }

    // V4.49.1: ⌘↩ Return 触发的进入沉浸式——从 singleSelectedPhoto 派发
    //   Photos.app 标准：Return 键进入全屏查看当前选中
    //   仅在单选时触发——多选/无选不响应
    private func enterImmersiveFromSelection() {
        guard let photo = singleSelectedPhoto else { return }
        enterImmersive(photo)
    }

    // 清除所有筛选
    private func resetFilters() {
        sidebarSelection = .all
        searchText = ""
        // V4.36.x: 工具栏筛选按钮 4 维也清
        filterState = .empty
    }

    // V5.7: 砍 toggleFavorite()——工具栏 ❤ 收藏按钮已移除
    //   原逻辑：单选切换 / 多选批量反向——通过右键菜单评分 / 筛选 popover 替代

    // V4.8.0: 删 toolbarContent 定义——NSToolbar (AppKit) 接管所有 toolbar items
    // V4.9.1: 删 showViewOptions @State——View Options popover 改用 NSPopover 由 ToolbarController 管
    //   SwiftUI .toolbar 是降级实现，Photos.app 风格必须用 NSToolbar
    //   新 toolbar 配置在 configureNSToolbar(window:) 方法里
    //   （V4.7.1-V4.7.7 7 个 commit 探索 SwiftUI toolbar 限制都失败）

    // 主布局（V3.5.17：拆到 Views/MainLayoutView.swift；V4.0.0 toolbar 迁出到 native .toolbar；V4.8.0 改为 NSToolbar）
    // V4.10.0: 把 4 个区块抽到 private var pane（sidebarPane/gridPane/detailPane/statusBarPane）
    //   避免 mainLayout body 内 100+ 行的 PhotoGridPane / DetailPane 闭包列表触发 type-check 超时
    private var mainLayout: some View {
        MainLayoutView(
            pathBar: { pathBarPane },
            split: { mainSplitPane },
            statusBar: { statusBarPane },
            showSidebar: $showSidebar,
            undoManager: undoManager,
            toastQueue: toastQueue,
            immersivePhoto: $immersivePhoto,
            immersiveIndex: $immersiveIndex,
            visiblePhotos: visiblePhotos,
            onImmersiveDismiss: { immersivePhoto = nil }
        )
    }

    // V3.5.17：PathBar 已禁用（用户偏好）
    // 保留 MainLayoutView 接口；空 @ViewBuilder 闭包 = EmptyView = 不占空间
    // 如要恢复：取消下面注释即可
    //
    // if !pathSegments.isEmpty {
    //     PathBar(
    //         segments: pathSegments,
    //         onNavigate: { target in
    //             if let target = target {
    //                 sidebarSelection = target
    //             }
    //         }
    //     )
    // }
    @ViewBuilder
    private var pathBarPane: some View {
        // V4.36.x: 工具栏筛选按钮激活时显示 chip 行
        //   仅 filterState.isActive 时返回 ActiveFiltersBar（内部 EmptyView 早返）
        //   V3.5.17 PathBar 已被本组件"复活"——新的筛选状态可视化
        ActiveFiltersBar(
            filterState: $filterState,
            allFolders: folders,
            allTags: allTags
        )
    }

    // V3.6.32: 恢复到 V3.6.27 顶层加 .boxSelectionGesture 模式
    // 之前 R2 改到 PhotoGridView 内部，simultaneousGesture 仍破坏 cell .onDrag
    // 现在先恢复 V1（最安全），box-select V2 留待未来换实现思路
    private var mainSplitPane: some View {
        MainSplitView(
            layout: columnLayout,
            showSidebar: $showSidebar,
            showDetail: $showDetail,
            isDropTargeted: $isDropTargeted,
            isBoxSelecting: $isBoxSelecting,
            onDrop: handleDrop,
            sidebar: { sidebarPane },
            center: { gridPane },
            detail: { detailPane }
        )
        // V3.6.52: 1 binding<SelectionState> 替 2 bindings
        .boxSelectionGesture(
            isBoxSelecting: $isBoxSelecting,
            selection: $selection,
            visiblePhotos: visiblePhotos
        )
    }

    private var sidebarPane: some View {
        SidebarView(
            selection: $sidebarSelection,
            photoSelection: $selection,
            // V4.0.0.6: 缩放 + 排序搬到侧栏顶部（"视图控制中心"）
            thumbnailSize: $thumbnailSize,
            sortOption: $sortOption
            // V4.1.0f: 移除 showSidebar binding（hide 按钮完全搬回主工具栏）
        )
    }

    // V4.36.6: 中间列根据 viewMode 切换 3 视图
    //   旧版 gridPane 只返回 PhotoGridPane, viewMode 在 popover 切换无效
    //   新版 switch viewMode → 3 个 Pane 之一, 都用 visiblePhotos (PhotoStats.filtered)
    //   共享 filter helper 保证 3 视图显示完全一致的内容
    @ViewBuilder
    private var gridPane: some View {
        switch viewMode {
        case .grid:
            PhotoGridPane(
                selection: $selection,
                folder: currentFolder,
                tag: currentTag,
                searchText: searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: filterUnfiled,
                filterDuplicates: filterDuplicates,
                filterRecent7Days: filterRecent7Days,
                filterLargeFiles: filterLargeFiles,
                filterInTrash: filterInTrash,
                // V4.36.x: 工具栏筛选 4 维
                selectedFolderIDs: filterState.folders,
                selectedTagIDs: filterState.tags,
                selectedShapes: filterState.shapes,
                filterMinRating: filterState.minRating,
                retentionDays: retentionDays,
                thumbnailSize: thumbnailSize,
                // V5.17: 缩略图布局模式 3 选项（方格 / 按比例 / 按比例满行）
                //   透传到 PhotoGridView.masonryRowsView 决定 uniformWidth/stretchLastRow
                layoutMode: layoutMode,
                sortOption: sortOption,
                // V4.36.6: visiblePhotos 改 computed property, 此 callback 不再需要
                //   保留参数避免破坏 PhotoGridPane 签名——传 noop
                onVisiblePhotosChange: { _ in },
                onImport: startImport,
                onBatchDelete: { showingBatchDeleteConfirm = true },
                onClearMultiSelect: { selection = .empty },
                onDoubleTap: enterImmersive,
                onClearFilters: { resetFilters() },
                onExportComplete: { count in
                    showToast("已导出 \(count) 张图片", type: .success)
                }
            )
        case .list:
            PhotoListPane(
                selection: $selection,
                folder: currentFolder,
                tag: currentTag,
                searchText: searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: filterUnfiled,
                filterDuplicates: filterDuplicates,
                filterRecent7Days: filterRecent7Days,
                filterLargeFiles: filterLargeFiles,
                filterInTrash: filterInTrash,
                // V4.36.x: 工具栏筛选 4 维（签名一致；本视图不实际用）
                selectedFolderIDs: filterState.folders,
                selectedTagIDs: filterState.tags,
                selectedShapes: filterState.shapes,
                filterMinRating: filterState.minRating,
                sortOption: sortOption,
                photos: visiblePhotos,
                onTap: handleTap,
                onDoubleTap: enterImmersive
            )
        case .timeline:
            PhotoTimelinePane(
                selection: $selection,
                folder: currentFolder,
                tag: currentTag,
                searchText: searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: filterUnfiled,
                filterDuplicates: filterDuplicates,
                filterRecent7Days: filterRecent7Days,
                filterLargeFiles: filterLargeFiles,
                filterInTrash: filterInTrash,
                // V4.36.x: 工具栏筛选 4 维（签名一致；本视图不实际用）
                selectedFolderIDs: filterState.folders,
                selectedTagIDs: filterState.tags,
                selectedShapes: filterState.shapes,
                filterMinRating: filterState.minRating,
                sortOption: sortOption,
                photos: visiblePhotos,
                onTap: handleTap,
                onDoubleTap: enterImmersive
            )
        }
    }

    private var detailPane: some View {
        DetailPane(
            singleSelectedPhoto: singleSelectedPhoto,
            isMultiSelect: isMultiSelect,
            // V3.6.52: 用 selection.selectedIDs.count 替直接字段
            count: filterInTrash ? trashedCount : (filterInDuplicates ? duplicatePurgeableCount : selection.selectedIDs.count),
            totalSize: filterInTrash ? trashedTotalSize : (filterInDuplicates ? duplicatePurgeableSize : selectedTotalSize),
            folders: folders,
            allTags: allTags,
            onDelete: deleteSinglePhoto,
            onPrev: goPrev,
            onNext: goNext,
            canPrev: canPrev,
            canNext: canNext,
            currentIndex: currentIndex,
            totalCount: visiblePhotos.count,
            // V3.5.19：多选 batch 动作从原 PhotoGridView.multiSelectTopBar 搬过来
            onBatchMove: { folder in batchMove(to: folder) },
            onBatchAddTag: { tag in batchAddTag(tag) },
            // V5.7: 砍 onBatchToggleFavorite——多选面板的"收藏"按钮移除
            // V5.12: 加 onBatchSetRating——多选批量评分
            onBatchSetRating: { rating in batchSetRating(rating) },
            onBatchExport: batchExport,
            onBatchDelete: { showingBatchDeleteConfirm = true },
            // V3.6.52: 单字段 assignment 替 2 字段 pair
            onClearSelection: { selection = .empty },
            // V3.6 NEW: 回收站模式
            sidebarSelection: sidebarSelection,
            retentionDays: retentionDays,
            onTrashRestore: restoreSelectedFromTrash,
            onTrashPermanentDelete: permanentDeleteSelected,
            // V3.6.6: 改弹二次确认（不再直接调 emptyTrash）
            onEmptyTrash: { showingEmptyTrashConfirm = true },
            // V4.9.0: 回收站空时切回"全部"视图
            onExitTrash: { sidebarSelection = .all },
            // V3.6.15: 重复图清理（一键保留每组最新）
            onKeepNewestPerDuplicateGroup: keepNewestPerDuplicateGroup,
            // V4.11.0: 存储不可写错误（nil = OK）
            storageError: storageErrorMessage,
            onRetryStorage: checkStorage
        )
    }

    private var statusBarPane: some View {
        // V3.5.6 Finder 化：Status Bar（底部信息条）
        StatusBar(
            totalCount: allPhotos.count,
            totalSize: totalSizeFormatted,
            // V3.6.52: 用 selection.selectedIDs.count 替直接字段
            selectedCount: selection.selectedIDs.count,
            // V5.15: 导入进度——StatusBar 右侧显示"导入中 X/Y · N 失败"
            importProgress: importProgress
        )
    }

    /// V5.13: 入队 Toast（V4.36.x 单 in-flight 改 queue）
    /// - 自动 dismiss：用 scheduleDismiss 单点维护 task
    /// - 错误 toast 用 .long duration（5s）让用户看清
    private func enqueueToast(_ message: String, type: ToastView.ToastType = .info, duration: ToastInfo.Duration = .normal) {
        let info = ToastInfo(message: message, type: type, duration: duration)
        toastQueue.append(info)
        if toastQueue.count == 1 {
            // 队列从空到非空——启动 dismiss task
            scheduleDismiss(after: info.duration.seconds)
        }
        // 否则排队中——当前 dismiss task 处理完后会自动续 next
    }

    /// V5.13: dismiss task 单点维护
    /// - 每次启动新 task 取消上一个（防 race）
    /// - 队列空时停；非空时按队首 duration 续 task
    private func scheduleDismiss(after seconds: TimeInterval) {
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard !toastQueue.isEmpty else { return }
            toastQueue.removeFirst()
            if let next = toastQueue.first {
                scheduleDismiss(after: next.duration.seconds)
            }
        }
    }

    /// 兼容旧 showToast 调用（V4.36.x 8 处 call site 保持 0 改动）
    ///   Day 5 错误 toast 改用 enqueueToast(message, type: .error, duration: .long)
    private func showToast(_ message: String, type: ToastView.ToastType = .info) {
        enqueueToast(message, type: type, duration: .normal)
    }


    // 处理 Delete 键
    private func handleDelete() {
        // V3.6.52: 用 selection.selectedIDs 替旧 selectedIDs
        if !selection.selectedIDs.isEmpty {
            showingBatchDeleteConfirm = true
        } else if singleSelectedPhoto != nil {
            deleteSinglePhoto()
        }
    }

    // V4.36.6: 从 PhotoGridView.handleTap 抽出到 ContentView——3 视图共用
    //   旧版 tap 处理逻辑在 PhotoGridView 内, List/Timeline 视图无法复用
    //   现在 3 视图都传 onTap: handleTap 闭包, 选中行为完全一致
    private func handleTap(_ photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        let modifier: ClickModifier = {
            if modifiers.contains(.command) { return .command }
            if modifiers.contains(.shift) { return .shift }
            return .plain
        }()
        let photoIDs = visiblePhotos.map { $0.id }
        let outcome = MultiSelectMath.handleTap(
            state: selection,
            photoID: photo.id,
            modifier: modifier,
            photoIDs: photoIDs
        )
        // TapOutcome 是 enum with associated values——从 3 个 case 都拿 SelectionState
        switch outcome {
        case .singleSelect(let s), .toggleMultiSelect(let s), .rangeSelect(let s):
            selection = s
        }
    }

    // ─── 上一张 / 下一张 ───
    // V3.6.52: 用 selection.selectingSingle(_:) 替 2 字段手工赋值
    private func goPrev() {
        guard canPrev,
              let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        let newID = visiblePhotos[idx - 1].id
        selection = selection.selectingSingle(newID)
    }

    private func goNext() {
        guard canNext,
              let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx < visiblePhotos.count - 1 else { return }
        let newID = visiblePhotos[idx + 1].id
        selection = selection.selectingSingle(newID)
    }

    // ─── V4.0.0.6: 缩放快捷键（⌘+ / ⌘-）───
    // 缩放搬到侧栏顶部后，必须配快捷键——否则要"绕到侧栏才能缩"
    // 参考 macOS Photos.app / Preview：⌘+ / ⌘- 缩略图大小
    private func zoomIn() {
        if let next = ThumbnailDensity.larger(than: thumbnailSize) {
            thumbnailSize = next.size
        }
    }

    private func zoomOut() {
        if let prev = ThumbnailDensity.smaller(than: thumbnailSize) {
            thumbnailSize = prev.size
        }
    }

    // V4.15.0: ⌘0 reset zoom——macOS Photos/Finder 标准快捷键
    //   恢复 thumbnailSize 到用户偏好（storedThumbnailSize from @AppStorage）
    //   不硬编码 170——尊重用户在 Settings 设的 default
    //   （与 ⌘+ / ⌘- 配合——缩放后可一键 reset 回默认）
    private func resetThumbnailSize() {
        thumbnailSize = CGFloat(storedThumbnailSize)
    }

    // V4.37.1: 触发 Quick Look——复用于 ⌘Y 菜单 / toolbar 按钮 / 空格键
    //   抽出 onSpace 闭包逻辑（避免 3 处重复 currentVisibleURLs + firstIndex 计算）
    //   currentVisibleURLs 让 QLPreviewPanel 支持 ←→ 在整个 visiblePhotos 内翻页（Photos.app 行为）
    private func showQuickLook() {
        guard let photo = singleSelectedPhoto,
              let idx = visiblePhotos.firstIndex(where: { $0.id == photo.id }) else {
            return
        }
        quickLookController.show(urls: currentVisibleURLs, currentIndex: idx)
    }

    // V4.37.4: titlebar accessory tooltip——反映当前 showDetail 状态
    //   加 ⌘I 快捷键提示——用户 hover 时发现 macOS Photos 标准快捷键
    //   仿 V4.36.x Filter 按钮 "筛选 (N)" 动态 tooltip 模式
    private func titlebarAccessoryTooltip(isActive: Bool) -> String {
        isActive ? "隐藏信息面板（⌘I）" : "显示信息面板（⌘I）"
    }

    // ─── 启动时清理过期回收站项（V3.6 NEW）───
    private func purgeExpiredTrashOnStartup() {
        let days = TrashRetentionDays(rawValue: retentionDays) ?? .defaultValue
        let service = RecycleBinService(storage: .shared, modelContext: modelContext)
        service.purgeExpired(retentionDays: days.rawValue)
    }

    // ─── 启动导入 ───
    private func startImport() {
        let panel = NSOpenPanel()
        panel.title = "选择图片或文件夹"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }

        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)

        // V5.15: 4 参数 onProgress (current, total, inserted, failureCount)
        let importer = ImageImporter(
            modelContext: modelContext,
            folder: currentFolder
        ) { current, total, inserted, failureCount in
            Task { @MainActor in
                importProgress = ImportProgress(
                    current: current, total: total,
                    inserted: inserted, failureCount: failureCount,
                    isImporting: true
                )
                if current >= total && total > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let p = importProgress, p.current >= p.total {
                        importProgress = nil
                    }
                }
            }
        }
        // V3.6.24: 导入前重复检测（fileHash 重复弹 dialog 让用户选跳过/副本）
        runImportWithDuplicateCheck(urls: panel.urls)
    }

    /// V3.6.24: 扫现有 photo + 算新 url fileHash，弹 dialog 让用户选
    /// V3.6.27: 改用 async 版本（后台 actor 算 SHA256，不阻塞 main thread）
    private func runImportWithDuplicateCheck(urls: [URL]) {
        Task { @MainActor in
            let check = await ImageImporter.checkDuplicatesAsync(
                newURLs: urls,
                in: modelContext
            ) { current, total in
                // V3.6.27: 进度反馈（"检测重复中... 5/12"）
                importProgress = ImportProgress(current: current, total: total, isImporting: true)
            }
            // 算完后清进度
            importProgress = nil
            if check.hasDuplicates {
                pendingImportURLs = urls
                importDuplicateCheck = check
            } else {
                importPhotos(urls: urls)
            }
        }
    }

    // V3.6.24: 重复检测 dialog 的动态 title（避免 body message: 闭包触发 type-check）
    private var duplicateDialogTitle: String {
        guard let check = importDuplicateCheck else { return "检测到重复文件" }
        return "发现 \(check.existing.count) 张已存在 / \(check.newCount) 张新文件"
    }

    private func confirmSkipDuplicates() {
        let existing = Set(importDuplicateCheck?.existing ?? [])
        let newURLs = pendingImportURLs.filter { !existing.contains($0) }
        importDuplicateCheck = nil
        pendingImportURLs = []
        if !newURLs.isEmpty { importPhotos(urls: newURLs) }
    }

    private func confirmImportAllDuplicates() {
        let allURLs = pendingImportURLs
        importDuplicateCheck = nil
        pendingImportURLs = []
        importPhotos(urls: allURLs)
    }

    private func cancelDuplicateImport() {
        importDuplicateCheck = nil
        pendingImportURLs = []
    }

    /// V3.6.24: 实际跑导入（dialog 确认后调用，或无重复时直接调）
    /// V5.13: 接 ImportResult——成功 1 个 success toast + 失败 N 个 error toasts
    /// V5.15: 进度用 inserted/failureCount 显示；混合结果合并 1 个 summary toast
    private func importPhotos(urls: [URL]) {
        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        // V5.15: 4 参数 onProgress (current, total, inserted, failureCount)
        let importer = ImageImporter(modelContext: modelContext, folder: currentFolder) { current, total, inserted, failureCount in
            Task { @MainActor in
                importProgress = ImportProgress(
                    current: current, total: total,
                    inserted: inserted, failureCount: failureCount,
                    isImporting: true
                )
                if current >= total && total > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let p = importProgress, p.current >= p.total {
                        importProgress = nil
                    }
                }
            }
        }
        let result = importer.importURLs(urls)
        // V5.15: 合并 1 个 summary toast（避免 N 个 per-failure 堆叠）
        if result.inserted > 0 && result.hasFailures {
            // 部分成功 + 部分失败
            enqueueToast("已导入 \(result.inserted) 张，\(result.failureCount) 张失败", type: .info)
        } else if result.inserted > 0 {
            // 全成功
            enqueueToast("已导入 \(result.inserted) 张图片", type: .success)
        }
        // 纯失败时仍 per-file 报（让用户知道哪些文件）
        for (url, _) in result.failures where result.inserted == 0 {
            enqueueToast("导入失败：\(url.lastPathComponent)", type: .error, duration: .long)
        }
    }

    // ─── 拖拽导入 ───
    /// V4.49.0: 支持的图像扩展名——拖入时先过滤,避免非图片文件进 importer
    /// 跟 ImageImporter.supportedExtensions 保持一致
    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"
    ]

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                defer { group.leave() }
                guard let data = data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                // V4.49.0: 文件夹递归展开
                //   Photos.app 行为：拖入文件夹 = 导入文件夹内所有图片
                let expanded = Self.expandFolders([url])
                lock.lock()
                urls.append(contentsOf: expanded)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            // V4.49.0: 过滤非图片文件（macOS 拖入可能含 .txt/.pdf 等）
            let imageURLs = urls.filter { Self.supportedImageExtensions.contains($0.pathExtension.lowercased()) }
            guard !imageURLs.isEmpty else { return }
            // V3.6.24: 拖拽导入也走重复检测
            runImportWithDuplicateCheck(urls: imageURLs)
        }

        return true
    }

    /// V4.49.0: 递归展开文件夹——返回所有文件 URL
    ///   Photos.app 行为：拖入文件夹 = 导入该文件夹 + 子文件夹的图片
    ///   跳隐藏文件 (.DS_Store 等)
    private static func expandFolders(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fileManager = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let contents = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    result.append(contentsOf: expandFolders(contents))
                }
            } else {
                result.append(url)
            }
        }
        return result
    }

    // V4.1.0 l: 切换侧栏 section 时清选中（避免"选中的照片不在新 section"）
    private func clearSelectionOnFilterChange() {
        if !selection.isEmpty {
            selection = .empty
        }
    }

    // ─── 删除单张（V3.6：走 RecycleBinService，不再调 undoManager）───
    private func deleteSinglePhoto() {
        guard let photo = singleSelectedPhoto else { return }
        // V3.6：删除 = 移到回收站（软删），文件保留在 Photos/ 原位
        // V5.13: 注入 onError 失败时 toast
        RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { error in
                enqueueToast("移到回收站失败：\(error.localizedDescription)", type: .error, duration: .long)
            }
        ).recycle(photo)
        // V3.6.52: 单字段清空替 2 字段 pair
        selection = .empty
        showToast("已移到回收站（\(retentionDays) 天后永久删除）", type: .info)
    }

    // ─── 批量删除（V3.6：走 RecycleBinService，不再调 undoManager）───
    private func batchDelete() {
        performOnSelectedTrash(
            { svc, photos in photos.forEach { svc.recycle($0) } },
            message: { "已移到回收站 \($0) 张" }
        )
    }

    // V3.5.19：从 PhotoGridView 搬上来的 4 个 batch 方法
    // 原因：multi-select 顶部栏被移到详情面板里，详情面板的 MultiSelectDetailView
    // 需要直接调用这些方法。

    // ─── 批量移动到文件夹 ───
    private func batchMove(to folder: Folder?) {
        // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
        let photosToMove = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToMove.isEmpty else { return }

        // 快照：移动前的 folder 列表
        let oldFolders = photosToMove.map { $0.folder }
        let count = photosToMove.count
        let folderName = folder?.name ?? "待整理"

        undoManager.registerAction(
            description: "移动 \(count) 张照片到 \(folderName)"
        ) {
            for photo in photosToMove {
                photo.folder = folder
            }
            modelContext.saveWithLog()
            // 移动后清空多选
            selection = .empty
        } undo: {
            for (photo, oldFolder) in zip(photosToMove, oldFolders) {
                photo.folder = oldFolder
            }
            modelContext.saveWithLog()
        }
    }

    // ─── 批量加标签 ───
    private func batchAddTag(_ tag: Tag) {
        // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
        let photosToTag = selection.selectedPhotos(in: visiblePhotos)
        for photo in photosToTag {
            if !photo.tags.contains(where: { $0.id == tag.id }) {
                photo.tags.append(tag)
            }
        }
        modelContext.saveWithLog()
        // 加标签后保留多选（用户可能想加多个标签）
    }

    // V5.12: 批量评分
    //   - 多选 N 张 → onBatchSetRating(M) 一次设 M 星
    //   - M = 0 表示清除评分
    //   - 与详情页 RatingStarsView 共用同一 photo.rating 字段
    //   - ⌘0-⌘5 快捷键也走同一函数（ContentKeyboardShortcuts.onSetRating）
    private func batchSetRating(_ rating: Int) {
        let photosToRate = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToRate.isEmpty else { return }
        BatchSetRatingMath.applyRating(rating, count: photosToRate.count) { index, r in
            photosToRate[index].rating = r
        }
        // V5.13: 失败 toast（onError 默认 no-op 向后兼容）
        modelContext.saveWithLog { _ in
            enqueueToast("批量评分失败", type: .error, duration: .long)
        }
    }

    // ─── 批量导出 ───
    private func batchExport() {
        // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
        let photosToExport = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToExport.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "选择导出位置"
        panel.prompt = "导出"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destDir = panel.url else { return }

        var successCount = 0
        for photo in photosToExport {
            let destURL = destDir.appendingPathComponent(photo.filename)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let uniqueDest = uniqueDestinationForBatchExport(for: destURL)
                    try FileManager.default.copyItem(at: photo.fileURL, to: uniqueDest)
                } else {
                    try FileManager.default.copyItem(at: photo.fileURL, to: destURL)
                }
                successCount += 1
            } catch {
                // V5.13: 删 print 改 error toast（每个失败 1 个）—— 错误用 .long 让用户看清
                enqueueToast("导出失败：\(photo.filename)", type: .error, duration: .long)
            }
        }
        if successCount > 0 {
            showToast("已导出 \(successCount) 张图片", type: .success)
        }
    }

    /// 避免导出时文件名冲突
    private func uniqueDestinationForBatchExport(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        while true {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let candidate = dir.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    // ─── V5.7: 砍 batchToggleFavorite()——多选面板的"收藏"按钮已移除 ───

    // ─── 回收站操作（V3.6 NEW）───

    /// 在 visiblePhotos ∩ selectedIDs 上执行 trash 操作（3 个 batch 方法的共用骨架）
    /// - Parameters:
    ///   - operation: 实际的 SwiftData 变更（recycle / restore / purge）
    ///   - message: toast 消息生成器（接收处理数量）
    ///   - type: toast 类型（默认 .info；恢复用 .success）
    /// V5.13: 注入 onError → RecycleBinService 失败时 toast
    private func performOnSelectedTrash(
        _ operation: (RecycleBinService, [Photo]) -> Void,
        message: (Int) -> String,
        type: ToastView.ToastType = .info
    ) {
        // V3.6.52: 用 selection.selectedPhotos(in:) 替手写 filter
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty else { return }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { error in
                enqueueToast(
                    "回收站操作失败：\(error.localizedDescription)",
                    type: .error,
                    duration: .long
                )
            }
        )
        operation(service, photos)
        let count = photos.count
        selection = .empty
        showToast(message(count), type: type)
    }

    /// 恢复选中的照片（从回收站 → 图库）
    private func restoreSelectedFromTrash() {
        performOnSelectedTrash(
            { svc, photos in photos.forEach { svc.restore($0) } },
            message: { "已恢复 \($0) 张图片" },
            type: .success
        )
    }

    /// 永久删除选中的照片（文件 + SwiftData）
    private func permanentDeleteSelected() {
        performOnSelectedTrash(
            { svc, photos in svc.purgeAll(photos) },
            message: { "已永久删除 \($0) 张图片" }
        )
    }

    /// 清空回收站（永久删除所有 trashed 项；不走 selectedIDs）
    private func emptyTrash() {
        let trashed = allPhotos.filter { $0.isInTrash }
        guard !trashed.isEmpty else { return }
        // V5.13: 注入 onError → purge 失败时 toast
        RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { error in
                enqueueToast("清空回收站失败：\(error.localizedDescription)", type: .error, duration: .long)
            }
        ).purgeAll(trashed)
        let count = trashed.count
        // V3.6.52: 单字段清空替 2 字段 pair
        selection = .empty
        showToast("已清空回收站（\(count) 张）", type: .info)
    }

    /// V3.6.15 NEW: 重复图清理 — 每组保留 importedAt 最新的，其他移到回收站
    private func keepNewestPerDuplicateGroup() {
        // 找所有可见图（应用当前 filter 后的子集）里可清理的
        let visible = visiblePhotos.filter { !$0.isInTrash }
        let purgeable = PhotoStats.duplicatesToPurge(in: visible)
        guard !purgeable.isEmpty else { return }
        // V5.13: 注入 onError → 批量 recycle 失败时 toast
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { error in
                enqueueToast("批量移到回收站失败：\(error.localizedDescription)", type: .error, duration: .long)
            }
        )
        for photo in purgeable { service.recycle(photo) }
        showToast("已移到回收站 \(purgeable.count) 张重复图", type: .info)
    }

    // ─── 序列化 SidebarSelection ───
    private func serializeSelection(_ selection: SidebarSelection?) -> String {
        guard let selection = selection else { return "all" }
        switch selection {
        case .all: return "all"
        // V5.7: 砍 .favorites case
        case .unfiled: return "unfiled"
        case .duplicates: return "duplicates"
        case .recent7Days: return "recent7Days"
        case .largeFiles: return "largeFiles"
        case .folder(let f): return "folder:\(f.id.uuidString)"
        case .tag(let t): return "tag:\(t.id.uuidString)"
        case .recentlyDeleted: return "recentlyDeleted"  // V3.6 NEW
        }
    }

    // ─── 恢复 SidebarSelection ───
    private func restoreSelection(_ key: String) -> SidebarSelection? {
        switch key {
        case "all": return .all
        // V5.7: 砍 "favorites" case
        case "unfiled": return .unfiled
        case "duplicates": return .duplicates
        case "recent7Days": return .recent7Days
        case "largeFiles": return .largeFiles
        case "recentlyDeleted": return .recentlyDeleted  // V3.6 NEW
        default:
            if key.hasPrefix("folder:") {
                let uuidStr = String(key.dropFirst(7))
                if let uuid = UUID(uuidString: uuidStr) {
                    let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == uuid })
                    if let folder = try? modelContext.fetch(descriptor).first {
                        return .folder(folder)
                    }
                }
            }
            if key.hasPrefix("tag:") {
                let uuidStr = String(key.dropFirst(4))
                if let uuid = UUID(uuidString: uuidStr) {
                    let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == uuid })
                    if let tag = try? modelContext.fetch(descriptor).first {
                        return .tag(tag)
                    }
                }
            }
            return .all
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}

// MARK: - V3.5.18：设置面板 chrome helper
//
// V4.13.0: 撤回 onOpenSettings + showSettings 参数——⌘, 现在走 Settings scene
//   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 路径
//   简化后只应用强调色（.tint + .environment(\.appAccent)）
//
// 抽出 modifier 到独立 generic extension，避免 body 链超长触发
// Swift 编译器的 "unable to type-check this expression in reasonable time" 错误。
// 同样模式可复用：任何"挂在已有视图链尾端"的 modifier 都能用此技巧。
extension View {
    func applySettingsChrome(tintColor: Color) -> some View {
        self
            .tint(tintColor)
            .environment(\.appAccent, tintColor)
    }
}

// MARK: - V4.8.1: NSToolbar 桥接 extension
//
// 抽到 extension 避免 ContentView body 链过长触发 type-check 超时
// （V3.6.17/6.23/4.7.7 教训——body 临界点 ~200 行）
//
// syncNSToolbarSelectionState: SwiftUI @State SelectionState → NSToolbar buttons enabled
// syncNSToolbarSearchField: SwiftUI @State searchText → NSSearchField.stringValue
//
extension View {
    /// V4.8.0: 选中状态变化 → 同步到 NSToolbar 5 actions 的 enabled
    /// V5.24: 加 layoutMode + density 同步——ContentView 状态变化时推 toolbar
    func syncNSToolbarSelectionState(
        selection: SelectionState,
        layoutMode: ThumbnailLayoutMode? = nil,
        density: CGFloat? = nil
    ) -> some View {
        onChange(of: selection.hasSelection) { _, hasSelection in
            // V5.33: 删 layoutMode: 参数——3 模式 toolbar 控件已删
            ToolbarController.shared.updateAllStates(
                hasSelection: hasSelection,
                hasMultipleSelection: selection.isMultiSelect,
                density: density
            )
        }
    }

    // V5.33: 删 syncNSToolbarLayoutMode——3 模式 toolbar 控件已删
    //   之前 .onChange(of: layoutMode) 推 segment, 现在 toolbar 无 segment 不需同步
    //   layoutMode 仍可改 (ViewOptionsPopover), 但只影响 masonryRowsView 内部, 无 toolbar UI

    /// V5.24 NEW: 密度变化 → 同步到 NSToolbar slider value
    func syncNSToolbarDensity(_ density: CGFloat) -> some View {
        onChange(of: density) { _, newDensity in
            // V5.33: 删 layoutMode: nil 参数
            ToolbarController.shared.updateAllStates(
                hasSelection: false,
                hasMultipleSelection: false,
                density: newDensity
            )
        }
    }

    /// V4.8.1: SwiftUI @State searchText 变化 → 同步到 NSSearchField
    ///   NSSearchField 内部变化由 ToolbarController.onSearchTextChanged 闭包处理（避免循环）
    func syncNSToolbarSearchField(text: String) -> some View {
        onChange(of: text) { _, newValue in
            ToolbarController.shared.setSearchText(newValue)
        }
    }
}

// MARK: - V4.10.0: app lifecycle hooks extension
//
// 把 .onAppear + 6 个 .onChange 打包成 1 个语义化 modifier，让 body 链显著缩短。
// 同样的"抽到 extension 避免 type-check 超时"模式参考 applySettingsChrome / syncNSToolbar*。
extension View {
    func appLifecycleHooks(
        thumbnailSize: CGFloat,
        sidebarSelection: SidebarSelection?,
        sortOption: SortOption,
        viewModeRaw: String,
        storedThumbnailSize: Double,
        storedSortOption: String,
        onAppear: @escaping () -> Void,
        onStoredThumbnailChange: @escaping (Double) -> Void,
        onStoredSortChange: @escaping (String) -> Void,
        onThumbnailChange: @escaping (CGFloat) -> Void,
        onSidebarSelectionChange: @escaping (SidebarSelection?) -> Void,
        onSortOptionChange: @escaping (SortOption) -> Void
    ) -> some View {
        self
            .onAppear { onAppear() }
            // V3.6.13: 监听 SettingsView 修改 storedThumbnailSize，实时同步当前 session
            //   避免"重启后生效"的尴尬
            .onChange(of: storedThumbnailSize) { _, new in onStoredThumbnailChange(new) }
            .onChange(of: storedSortOption) { _, new in onStoredSortChange(new) }
            // V3.6.13: viewModeRaw 通过 computed property 自动响应 AppStorage 变化
            .onChange(of: viewModeRaw) { _, _ in }
            .onChange(of: thumbnailSize) { _, new in onThumbnailChange(new) }
            .onChange(of: sidebarSelection) { _, new in onSidebarSelectionChange(new) }
            .onChange(of: sortOption) { _, new in onSortOptionChange(new) }
    }
}

// MARK: - V4.10.0: grid input handling extension
//
// 把 .onDeleteCommand + .focusable + 7 个 .onKeyPress（←→ESC / ⌘A / ⌘+ / ⌘- / ⌘0 / ⌘E / Space）打包。
// 同样的"抽到 extension 避免 type-check 超时"模式参考 applySettingsChrome / appLifecycleHooks。
extension View {
    func gridInputHandling(
        canPrev: Bool,
        canNext: Bool,
        hasSelection: Bool,
        onDelete: @escaping () -> Void,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        // V4.12.0: 空格键 QuickLook（macOS Finder/Photos 标准）
        hasSelectedPhoto: Bool,
        onSpace: @escaping () -> Void,
        // V4.15.0: ⌘0 reset zoom（macOS Photos/Finder 标准）
        onResetZoom: @escaping () -> Void,
        // V4.17.0: ⌘E 导出（macOS Finder 标准，⌘L 撤回——与 macOS Get Info 冲突）
        onExport: @escaping () -> Void,
        // V4.49.1: ⌘↩ Return 进入沉浸式查看（macOS Photos 标准）
        //   仅选中单张时有效——多选/无选 .ignored
        onReturn: @escaping () -> Void
    ) -> some View {
        self
            .onDeleteCommand(perform: onDelete)
            .focusable()
            .onKeyPress(.leftArrow) {
                if canPrev { onPrev() }
                return .handled
            }
            .onKeyPress(.rightArrow) {
                if canNext { onNext() }
                return .handled
            }
            .onKeyPress(.escape) {
                if hasSelection {
                    onEscape()
                    return .handled
                }
                return .ignored
            }
            // V4.12.0: 空格键 QuickLook——无选中时不响应（macOS Finder 行为一致）
            .onKeyPress(.space) {
                if hasSelectedPhoto {
                    onSpace()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("a", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    // V3.6.52: 用 selection.settingAll(in:) 替手写 Set 构造
                    onSelectAll()
                    return .handled
                }
                return .ignored
            }
            // V4.0.0.6: ⌘+ / ⌘- 缩放快捷键（缩放搬到侧栏顶部后必须配快捷键）
            .onKeyPress("+", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onZoomIn()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("-", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onZoomOut()
                    return .handled
                }
                return .ignored
            }
            // V4.15.0: ⌘0 reset zoom（macOS Photos/Finder 标准）—— 恢复 storedThumbnailSize
            .onKeyPress("0", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onResetZoom()
                    return .handled
                }
                return .ignored
            }
            // V4.17.0: ⌘E 导出（macOS Finder 标准）—— 走 batchExport 路径，
            //   单张多张都弹 NSOpenPanel 选目录
            .onKeyPress("e", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onExport()
                    return .handled
                }
                return .ignored
            }
            // V4.49.1: ⌘↩ Return 进入沉浸式查看（macOS Photos 标准）
            //   Photos.app 用 Return 键进入全屏图片——快捷键 ⌘↩ 标准
            //   仅在 gridInputHandling 接受（多选/无选 .ignored 内部检查）
            .onKeyPress(.return) {
                onReturn()
                return .handled
            }
            // V4.37.2: ⌘[ / ⌘] 上下张切换（macOS Quick Look / Finder 标准）
            //   Photos.app 用 ←→ 方向键（gridInputHandling 已有）
            //   ⌘[/⌘] 是 macOS Quick Look 整个列表翻页的同款快捷键
            .onKeyPress("[", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    if canPrev { onPrev() }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("]", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    if canNext { onNext() }
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - V4.10.0: batch action dialogs extension
//
// 把 4 个 dialog（batchDelete / newFolder / emptyTrash / duplicate）打包成 1 个 modifier。
// 各 dialog 独立的 isPresented，顺序之间无相互依赖。
extension View {
    func batchActionDialogs(
        showingBatchDelete: Binding<Bool>,
        batchDeleteTitle: String,
        retentionDays: Int,
        onConfirmBatchDelete: @escaping () -> Void,
        showingNewFolder: Binding<Bool>,
        newFolderName: Binding<String>,
        onConfirmNewFolder: @escaping () -> Void,
        showingEmptyTrash: Binding<Bool>,
        onConfirmEmptyTrash: @escaping () -> Void,
        showingDuplicateCheck: Binding<Bool>,
        duplicateDialogTitle: String,
        onConfirmSkipDuplicates: @escaping () -> Void,
        onConfirmImportAllDuplicates: @escaping () -> Void,
        onCancelDuplicateImport: @escaping () -> Void
    ) -> some View {
        self
            .confirmationDialog(
                batchDeleteTitle,
                isPresented: showingBatchDelete,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive, action: onConfirmBatchDelete)
                Button("取消", role: .cancel) {}
            } message: {
                // V3.6 改：删除走回收站，N 天后才永久清除
                Text("选中的图片会移到回收站，\(retentionDays) 天后自动永久清除。可在回收站中恢复。")
            }
            // ⌘N 新建文件夹
            .alert("新建文件夹", isPresented: showingNewFolder) {
                TextField("文件夹名称", text: newFolderName)
                Button("取消", role: .cancel) { newFolderName.wrappedValue = "" }
                Button("创建") {
                    onConfirmNewFolder()
                    newFolderName.wrappedValue = ""
                }
            } message: {
                Text("为新文件夹命名")
            }
            // V3.6.6: 清空回收站二次确认
            .confirmationDialog(
                "确定要清空回收站吗？",
                isPresented: showingEmptyTrash,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive, action: onConfirmEmptyTrash)
                Button("取消", role: .cancel) {}
            } message: {
                Text("回收站里的所有照片将被永久删除，无法恢复。")
            }
            // V3.6.24: 导入时重复检测 dialog
            .confirmationDialog(
                duplicateDialogTitle,
                isPresented: showingDuplicateCheck,
                titleVisibility: .visible
            ) {
                Button("全部跳过（保留现有）", action: onConfirmSkipDuplicates)
                Button("全部导入（可能重复）", role: .destructive, action: onConfirmImportAllDuplicates)
                Button("取消", role: .cancel, action: onCancelDuplicateImport)
            } message: {
                Text("选\"跳过\"避免重复导入。")
            }
    }
}

// MARK: - V4.10.0: window chrome + NSToolbar 桥接 extension
//
// 把 .navigationTitle + .navigationSubtitle + .preferredColorScheme +
// .background(WindowAccessor) + .syncNSToolbarSelectionState + .syncNSToolbarSearchField
// 6 个 chrome modifier 打包成 1 个语义化 modifier。
extension View {
    func windowChromeAndToolbar(
        title: String,
        subtitle: String,
        colorScheme: ColorScheme?,
        selection: SelectionState,
        searchText: String,
        // V5.24: 加 layoutMode + thumbnailSize 参数——windowChromeAndToolbar 自身不持有
        //   状态，需 caller 传入以同步到 NSToolbar segment/slider
        layoutMode: ThumbnailLayoutMode,
        thumbnailSize: CGFloat,
        configureWindow: @escaping (NSWindow) -> Void
    ) -> some View {
        self
            // V4.8.0: 删 .toolbar { toolbarContent }——SwiftUI .toolbar 在 macOS 是降级实现
            //   改用 NSToolbar (AppKit) 在 WindowAccessor 处设置
            //   Photos.app / Finder / Mail 都用 NSToolbar——本路线一致
            //
            // V4.2.0 P0❸: 窗口元数据（hidden title bar 模式下不显示在窗口顶部，
            //   但进入 Dock 右键 / ⌘⇥ 切换器 / Mission Control / VoiceOver 等位置）
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            // V3.6.22: 应用外观（浅色/深色/跟随系统）
            .preferredColorScheme(colorScheme)
            // V4.8.0: NSToolbar 桥接——WindowAccessor 拿到 NSWindow 后设置 NSToolbar
            //   .background(WindowAccessor) 嵌入零尺寸 NSView
            .background(WindowAccessor { window in
                configureWindow(window)
            })
            // V4.8.0: 选中状态变化 → 更新 NSToolbar buttons enabled
            .syncNSToolbarSelectionState(
                selection: selection,
                layoutMode: layoutMode,
                density: thumbnailSize
            )
            // V4.8.1: SwiftUI @State searchText 变化 → 同步到 NSSearchField
            .syncNSToolbarSearchField(text: searchText)
            // V5.33: 删 .syncNSToolbarLayoutMode(layoutMode)——3 模式 toolbar 控件已删
            //   layoutMode 仍可改 (ViewOptionsPopover), 但只影响 masonryRowsView 内部, 无 toolbar UI
            // V5.24: 密度变化 → 同步到 NSToolbar segment/slider
            .syncNSToolbarDensity(thumbnailSize)
    }
}
