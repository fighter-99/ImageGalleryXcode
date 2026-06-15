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

struct ContentView: View {
    // V3.6.52: 3 @State (selectedPhoto/selectedIDs/lastSelectedID) 合并为 1 @State<SelectionState>
    //   这是图片选中的唯一真相源；`selectedPhoto: Photo?` 改为下面的 computed property
    // V5.52-3: 22 个 @State business state 搬到 ContentViewModel; computed proxy 保留 reads/writes 语法
    private var selection: SelectionState {
        get { model.selection }
        nonmutating set { model.selection = newValue }
    }

    @State private var isBoxSelecting = false

    // 侧边栏的选中项
    // 侧边栏的选中项
    private var sidebarSelection: SidebarSelection? {
        get { model.sidebarSelection }
        nonmutating set { model.sidebarSelection = newValue }
    }

    // V4.36.x: 工具栏筛选按钮状态（session-only，不写 UserDefaults / SwiftData）
    //   4 维：folders / tags / shapes / minRating
    //   与侧边栏并存补充——侧边栏选主上下文，筛选按钮叠加多选精细控制
    // V4.36.x: 工具栏筛选按钮状态（session-only，不写 UserDefaults / SwiftData）
    //   4 维：folders / tags / shapes / minRating
    //   与侧边栏并存补充——侧边栏选主上下文，筛选按钮叠加多选精细控制
    private var filterState: FilterState {
        get { model.filterState }
        nonmutating set { model.filterState = newValue }
    }

    // 搜索文本
    // 搜索文本
    private var searchText: String {
        get { model.searchText }
        nonmutating set { model.searchText = newValue }
    }

    // 缩略图大小
    // 缩略图大小
    private var thumbnailSize: CGFloat {
        get { model.thumbnailSize }
        nonmutating set { model.thumbnailSize = newValue }
    }
    // V3.6.13: 保留 @State 用 toolbar 临时调，onChange 同步 stored
    // V3.6.13: viewMode 改用 @AppStorage 持久化（SettingsView 可设默认）
    @AppStorage("viewModeRaw") private var viewModeRaw: String = ViewMode.grid.rawValue
    private var viewMode: ViewMode {
        get { model.viewMode }
        nonmutating set { model.viewMode = newValue }
    }

    // 排序方式（Eagle 化工具栏新增）
    // 排序方式（Eagle 化工具栏新增）
    private var sortOption: SortOption {
        get { model.sortOption }
        nonmutating set { model.sortOption = newValue }
    }

    // V4.36.6: visiblePhotos 从 @State 改为 computed property
    //   旧 @State + onVisiblePhotosChange 模式只服务于 grid view——切到 list/timeline 不更新
    //   改 computed property 用 PhotoStats.filtered 共享 helper, 3 视图同步
    // 注: 侧栏 section 折叠状态 (@AppStorage) 属于 SidebarView 持有, 不在此

    /// V4.36.6: 当前可见图片——PhotoStats.filtered 计算
    /// V5.52-4: 实现搬到 ContentViewModel.visiblePhotos
    private var visiblePhotos: [Photo] { model.visiblePhotos }

    // 拖拽状态
    @State private var isDropTargeted = false

    // 导入进度
    @State private var importProgress: ImportProgress?

    // 批量删除确认
    // 批量删除确认
    private var showingBatchDeleteConfirm: Bool {
        get { model.showingBatchDeleteConfirm }
        nonmutating set { model.showingBatchDeleteConfirm = newValue }
    }

    // V3.6.6: 清空回收站二次确认（防误操作：永久删除所有 trashed 项）
    // V3.6.6: 清空回收站二次确认（防误操作：永久删除所有 trashed 项）
    private var showingEmptyTrashConfirm: Bool {
        get { model.showingEmptyTrashConfirm }
        nonmutating set { model.showingEmptyTrashConfirm = newValue }
    }

    // V3.6.24: 导入时重复检测 dialog（防止 fileHash 重复的图片被再次导入）
    // V3.6.24: 导入时重复检测 dialog（防止 fileHash 重复的图片被再次导入）
    private var importDuplicateCheck: ImageImporter.DuplicateCheckResult? {
        get { model.importDuplicateCheck }
        nonmutating set { model.importDuplicateCheck = newValue }
    }
    private var pendingImportURLs: [URL] {
        get { model.pendingImportURLs }
        nonmutating set { model.pendingImportURLs = newValue }
    }

    // 批量移动
    // （showingBatchMoveSheet 已移除：批量移动流程当前在 PhotoGridView 内联实现，
    //   该状态从未被读。如未来要重新走 sheet 流程再加回。）

    // 新建文件夹弹窗
    // 新建文件夹弹窗
    private var showingNewFolderAlert: Bool {
        get { model.showingNewFolderAlert }
        nonmutating set { model.showingNewFolderAlert = newValue }
    }
    private var newFolderName: String {
        get { model.newFolderName }
        nonmutating set { model.newFolderName = newValue }
    }

    // 沉浸式查看
    // 沉浸式查看
    private var immersivePhoto: Photo? {
        get { model.immersivePhoto }
        nonmutating set { model.immersivePhoto = newValue }
    }
    private var immersiveIndex: Int {
        get { model.immersiveIndex }
        nonmutating set { model.immersiveIndex = newValue }
    }

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
    private var appearanceMode: AppearanceMode { model.appearanceMode }

    // V3.6 NEW: 启动时清理过期回收站项的"只跑一次"标记
    // ContentView 可能多次出现（开关窗口、切 sidebar），用 flag 避免重复清理
    @State private var hasPurgedExpiredTrash = false

    // V4.11.0: 存储不可写错误（nil = 正常）
    //   onAppear 调 PhotoStorage.verifyStorage()——失败时填错误消息，detail panel 显示错误态
    // V4.11.0: 存储不可写错误（nil = 正常）
    //   onAppear 调 PhotoStorage.verifyStorage()——失败时填错误消息，detail panel 显示错误态
    private var storageErrorMessage: String? {
        get { model.storageErrorMessage }
        nonmutating set { model.storageErrorMessage = newValue }
    }

    // V4.12.0 删: QuickLookPreviewController (@State) 整段——V5.42 走 ImmersivePhotoView, 不再需要
    // V5.42 替代: showQuickLook() 调 enterImmersiveFromSelection() 走系统 ImmersivePhotoView

    // V4.37.4: titlebar 右上角小按钮引用——@State 持 NSObject 引用
    //   onChange(of: showDetail) 时调 setActive / setTooltip 同步状态
    //   configureNSToolbar 内构造（一次），SwiftUI 重渲不重新构造（@State 持久）
    // V4.37.4: titlebar 右上角小按钮引用——@State 持 NSObject 引用
    //   onChange(of: showDetail) 时调 setActive / setTooltip 同步状态
    //   configureNSToolbar 内构造（一次），SwiftUI 重渲不重新构造（@State 持久）
    private var titlebarAccessory: TitlebarAccessoryController? {
        get { model.titlebarAccessory }
        nonmutating set { model.titlebarAccessory = newValue }
    }

    // V4.20.0: 撤回 V4.19.0 glassNamespace + glassEffectUnion
    //   macOS 26 glassEffectUnion 在 sidebar 边界外产生 outline 痕迹（用户截图反馈）
    //   回滚到 V4.18.0 单 view glassEffect 状态（仅 SidebarView/DetailView 4 处 .glassEffect）

    /// V4.12.0 删: currentVisibleURLs (URL 列表)——V5.42 不再走 QLPreviewPanel
    ///   showQuickLook 直接调 enterImmersiveFromSelection, 不需要 URL 列表
    ///   保留 visiblePhotos + fileURL 在 Photo 数据模型, 这里不再展开

    // 当前选中的强调色（从 accentColorID 解析）
    private var accentColor: AccentColor { model.accentColor }

    // Toast 提示（队列——V5.13 升级）
    // Toast 提示（队列——V5.13 升级）
    private var toastQueue: [ToastInfo] {
        get { model.toastQueue }
        nonmutating set { model.toastQueue = newValue }
    }
    private var toastTask: Task<Void, Never>? {
        get { model.toastTask }
        nonmutating set { model.toastTask = newValue }
    }

    // SwiftData：获取所有图片（用于状态栏显示总数）
    @Query private var allPhotos: [Photo]
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]
    @Query(sort: \Tag.createdAt, order: .forward) private var allTags: [Tag]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext

    // V5.52-1: ContentViewModel 业务模型——@Observable class
    //   V5.52-3 之后非 Optional——.task 里注入 modelContext
    @State private var model = ContentViewModel()

    // V3.5 Phase 1 Step 4：撤销/重做（@Observable + @State 模式）
    // V3.5 Phase 1 Step 4：撤销/重做（@Observable + @State 模式）
    private var undoManager: ImageGalleryUndoManager {
        get { model.undoManager }
        nonmutating set { model.undoManager = newValue }
    }

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
    // V5.17: 缩略图布局模式 (2 选项 .square / .squareFit, V5.47 砍 .masonry)
    //   镜像 AppearanceMode Int-backed pattern
    //   @AppStorage 持久化 + computed 读写 + 透传给 ViewOptionsPopover/PhotoGridPane
    //   nonmutating set 必备——否则 closure 内 [self] capture 后 setter 改 self 编译失败
    @AppStorage("thumbnailLayoutMode") private var storedLayoutModeRaw: Int = ThumbnailLayoutMode.defaultValue.rawValue
    private var layoutMode: ThumbnailLayoutMode {
        get { model.layoutMode }
        nonmutating set { model.layoutMode = newValue }
    }

    // V3.5.12：三栏列宽（HStack + 自定义 drag handles，避开 NSSplitView）
    @AppStorage("sidebarColumnWidth") private var storedSidebarWidth: Double = 220
    @AppStorage("detailColumnWidth") private var storedDetailWidth: Double = 360
    private var sidebarColumnWidth: CGFloat {
        get { model.sidebarColumnWidth }
        nonmutating set { model.sidebarColumnWidth = newValue }
    }
    private var detailColumnWidth: CGFloat {
        get { model.detailColumnWidth }
        nonmutating set { model.detailColumnWidth = newValue }
    }
    private var sidebarDragStartWidth: CGFloat {
        get { model.sidebarDragStartWidth }
        nonmutating set { model.sidebarDragStartWidth = newValue }
    }
    private var detailDragStartWidth: CGFloat {
        get { model.detailDragStartWidth }
        nonmutating set { model.detailDragStartWidth = newValue }
    }
    private let sidebarMinWidth: CGFloat = 160
    private let sidebarMaxWidth: CGFloat = 320
    // V4.35.x 修复: 3 个按钮等分 (收藏/在 Finder 中显示/删除) 至少需要 ~360pt
    //   旧 240pt → 3 按钮 80pt/个 → "在 Finder 中显示" 7 字 + icon 完全装不下 → 右侧被切
    private let detailMinWidth: CGFloat = 340
    private let detailMaxWidth: CGFloat = 480
    private let contentMinWidth: CGFloat = 400

    // 当前的筛选条件
    private var currentFolder: Folder? { model.currentFolder }
    private var currentTag: Tag? { model.currentTag }

    // V5.8: 砍 filterFavorites property——V5.7 砍 .favorites 侧边栏后此 property 永远 false
    //   用户想看"收藏"改走筛选 popover (评分 ≥ 5)

    private var filterUnfiled: Bool { model.filterUnfiled }
    private var filterDuplicates: Bool { model.filterDuplicates }
    private var filterRecent7Days: Bool { model.filterRecent7Days }
    private var filterLargeFiles: Bool { model.filterLargeFiles }
    private var filterInTrash: Bool { model.filterInTrash }
    private var filterInDuplicates: Bool { model.filterInDuplicates }

    // 派生属性——全部 proxy 到 model
    private var resolvedSingle: (photo: Photo, visibleIndex: Int)? { model.resolvedSingle }
    private var singleSelectedPhoto: Photo? { model.singleSelectedPhoto }
    private var currentIndex: Int { model.currentIndex }
    private var canPrev: Bool { model.canPrev }
    private var canNext: Bool { model.canNext }
    private var isMultiSelect: Bool { model.isMultiSelect }
    private var trimmedSearch: String { model.trimmedSearch }

    // V3.5.6 Finder 化: 总占用空间格式化
    private var totalSizeFormatted: String { model.totalSizeFormatted }

    // V4.2.0 P0❸: navigationTitle
    private var currentViewTitle: String { model.currentViewTitle }

    // V4.2.0 P0❸: subtitle——"N 张 · X MB"
    private var currentViewSubtitle: String { model.currentViewSubtitle }

    // V4.4.8: toolbar 搜索框左 padding
    private var searchFieldLeadingOffset: CGFloat { model.searchFieldLeadingOffset }

    // V3.5.19: 当前选中图片总大小
    private var selectedTotalSize: Int64 { model.selectedTotalSize }

    // V3.6: 回收站 count + size
    private var trashedCount: Int { model.trashedCount }
    private var trashedTotalSize: Int64 { model.trashedTotalSize }

    // V3.6.15: 重复图 group / purgeable count / size
    private var duplicateGroupCount: Int { model.duplicateGroupCount }
    private var duplicatePurgeableCount: Int { model.duplicatePurgeableCount }
    private var duplicatePurgeableSize: Int64 { model.duplicatePurgeableSize }

    // V3.5.17：把 6 个宽度 state vars + 4 个约束 + 2 个 AppStorage 钩子打包
    // V5.52-4: state vars 都走 model, 这里用 constants from model
    private var columnLayout: ColumnLayoutState {
        ColumnLayoutState(
            sidebarColumnWidth: Binding(get: { model.sidebarColumnWidth }, set: { model.sidebarColumnWidth = $0 }),
            detailColumnWidth: Binding(get: { model.detailColumnWidth }, set: { model.detailColumnWidth = $0 }),
            sidebarDragStartWidth: Binding(get: { model.sidebarDragStartWidth }, set: { model.sidebarDragStartWidth = $0 }),
            detailDragStartWidth: Binding(get: { model.detailDragStartWidth }, set: { model.detailDragStartWidth = $0 }),
            sidebarMinWidth: model.sidebarMinWidth,
            sidebarMaxWidth: model.sidebarMaxWidth,
            detailMinWidth: model.detailMinWidth,
            detailMaxWidth: model.detailMaxWidth,
            onSidebarDragEnd: { model.settings.sidebarColumnWidth = Double(model.sidebarColumnWidth) },
            onDetailDragEnd: { model.settings.detailColumnWidth = Double(model.detailColumnWidth) },
            restoreFromStorage: {
                model.sidebarColumnWidth = CGFloat(model.settings.sidebarColumnWidth)
                // V4.35.x 修复: 旧值 < 340pt 时升到 340pt
                let restored = CGFloat(model.settings.detailColumnWidth)
                model.detailColumnWidth = max(restored, 340)
            }
        )
    }

    var body: some View {
        mainLayout
            // V4.10.0: 6 个 chrome modifier 打包（title/subtitle/colorScheme/WindowAccessor/NSToolbar sync）
            // V5.24: 加 layoutMode + thumbnailSize 参数——传给 windowChromeAndToolbar 推 NSToolbar segment/slider
            // V5.39.3: 加 sortOption 参数——推 NSToolbar sortMenu 按钮 (image 跟 sortOption 走)
            .windowChromeAndToolbar(
                title: currentViewTitle,
                subtitle: currentViewSubtitle,
                colorScheme: appearanceMode.colorScheme,
                selection: selection,
                searchText: searchText,
                layoutMode: layoutMode,
                thumbnailSize: thumbnailSize,
                sortOption: sortOption,
                configureWindow: { model.configureToolbar(window: $0) }
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
            // V4.12.0 删: .background(QuickLookBridge(...))——V5.42 不再走 QLPreviewPanel
            // 快捷键：⌘+1-6 切换侧边栏
            .contentKeyboardShortcuts(
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
                // V5.52-8: 删 sidebarSelection 参数
            )
            // V4.10.0: 4 dialog 打包（batchDelete / newFolder / emptyTrash / duplicate）
            .batchActionDialogs(
                showingBatchDelete: bindableModel.showingBatchDeleteConfirm,
                batchDeleteTitle: batchDeleteTitle,
                retentionDays: retentionDays,
                onConfirmBatchDelete: batchDelete,
                showingNewFolder: bindableModel.showingNewFolderAlert,
                newFolderName: bindableModel.newFolderName,
                onConfirmNewFolder: createFolderFromAlert,
                showingEmptyTrash: bindableModel.showingEmptyTrashConfirm,
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
            // V5.52-1: 注入 modelContext 到 ContentViewModel——.task 在 view 出现后跑一次
            //   V5.52-3 之后 model 非 Optional, 这里只 attach modelContext
            // V5.52-7: 推送 3 个 @Query 结果到 model (model 是单一真相源)
            .task {
                model.modelContext = modelContext
                // V5.52-2: 把 12 个 @AppStorage 同步到 model.settings
                model.settings.viewModeRaw = viewModeRaw
                model.settings.showSidebar = showSidebar
                model.settings.showDetail = showDetail
                model.settings.accentColorID = accentColorID
                model.settings.trashRetentionDays = retentionDays
                model.settings.appearanceMode = appearanceModeRaw
                model.settings.thumbnailSize = storedThumbnailSize
                model.settings.sidebarSelection = storedSidebarKey
                model.settings.sortOption = storedSortOption
                model.settings.thumbnailLayoutMode = storedLayoutModeRaw
                model.settings.sidebarColumnWidth = storedSidebarWidth
                model.settings.detailColumnWidth = storedDetailWidth
                // V5.52-7: 初始 push 3 个 @Query 缓存到 model
                model.allPhotos = allPhotos
                model.folders = folders
                model.allTags = allTags
            }
            // V5.52-7: @Query 变化时同步到 model——SwiftData store 变化驱动 .onChange
            .onChange(of: allPhotos) { _, new in model.allPhotos = new }
            .onChange(of: folders) { _, new in model.folders = new }
            .onChange(of: allTags) { _, new in model.allTags = new }
    }

    // V5.52-3: @Bindable shadow @State model——macOS 14+ 推荐模式
    //   让 body 内的 $model.X 走 Bindable dynamicMember subscript → Binding<T>
    //   pane builders 也 shadow 一份, 各自 body 范围独立
    private var bindableModel: Bindable<ContentViewModel> { Bindable(model) }

    // V4.0.0: 抽出 importDuplicateCheck 状态到 binding（让 type-check 过得去）
    // V5.52-4: importDuplicateCheck 走 model, 这里直接构造 binding
    private var showingDuplicateCheck: Binding<Bool> {
        Binding(
            get: { model.importDuplicateCheck != nil },
            set: { if !$0 { model.importDuplicateCheck = nil } }
        )
    }

    // V4.0.0: 抽出批量删除确认 title（避免 body 内 string interpolation 触发 type-check 超时）
    // V5.52-4: 走 Copy 字典
    private var batchDeleteTitle: String { model.batchDeleteTitle }


    // V4.11.0: 检查 Application Support/ImageGallery/Photos/ 目录可写性
    //   失败时填 storageErrorMessage 触发 detail panel 错误态
    //   用户可点重试按钮再次检测（磁盘腾出空间 / 权限恢复后）
    //   PhotoStorage.verifyStorage() 是 v3.6 写但从未调用的死代码——v4.11.0 接入
    private func checkStorage() -> Void { model.checkStorage() }

    // ⌘N 触发的创建文件夹
    private func createFolderFromAlert() -> Void { model.createFolderFromAlert() }

    // 隐藏的快捷键按钮（.background 注入，不可见但响应快捷键）
    // 切换当前排序方向（在同字段的 asc/desc 之间切换）
    private func toggleSortDirection() -> Void { model.toggleSortDirection() }

    // V5.52-8: 删 shareSelected (dead code, 0 caller)
    //   NSSharingServicePicker 路径从未被 wire 进来——V3.6.52 之后用 selection.selectedPhotos
    //   现如要加 share, 直接走 macOS 系统菜单 (Finder > Share) 或 toolbar 按钮

    // 复制到剪贴板（支持多选）
    private func copyToPasteboard() -> Void { model.copyToPasteboard() }

    // 进入沉浸式查看（双击图片触发）
    private func enterImmersive(_ photo: Photo) -> Void { model.enterImmersive(photo) }

    // V4.49.1: ⌘↩ Return 触发的进入沉浸式——从 singleSelectedPhoto 派发
    //   Photos.app 标准：Return 键进入全屏查看当前选中
    //   仅在单选时触发——多选/无选不响应
    private func enterImmersiveFromSelection() -> Void { model.enterImmersiveFromSelection() }

    // 清除所有筛选
    private func resetFilters() -> Void { model.resetFilters() }

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
            immersivePhoto: Binding(get: { model.immersivePhoto }, set: { model.immersivePhoto = $0 }),
            immersiveIndex: Binding(get: { model.immersiveIndex }, set: { model.immersiveIndex = $0 }),
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
            filterState: bindableModel.filterState,
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
            selection: bindableModel.selection,
            visiblePhotos: visiblePhotos
        )
    }

    private var sidebarPane: some View {
        SidebarView(
            selection: bindableModel.sidebarSelection,
            photoSelection: bindableModel.selection,
            // V4.0.0.6: 缩放 + 排序搬到侧栏顶部（"视图控制中心"）
            thumbnailSize: bindableModel.thumbnailSize,
            sortOption: bindableModel.sortOption
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
                selection: bindableModel.selection,
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
                },
                // V5.39.6: 拖入导入——从 Finder 拖文件/文件夹到 grid 直接导入
                //   走 ImageImporter.importURLs (同 NSOpenPanel 路径), 含 progress 跟踪 + toast 反馈
                //   filter 文件/文件夹筛选交给 ImageImporter.collectFiles 内部处理
                onDropImport: handleDropImport,
                // V5.39.7: 重排回调——no-op (PhotoGridView 内部 @State trigger 已处理刷新)
                //   透传 onReorder 闭包到 cell → 调时增 reorderRefreshTrigger → .onChange → recomputePhotos
                //   ContentView 不需要做事, 闭包仅用于保持 chain 类型一致
                onReorder: {}
            )
        case .list:
            PhotoListPane(
                selection: bindableModel.selection,
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
                selection: bindableModel.selection,
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
    private func enqueueToast(_ message: String, type: ToastView.ToastType = .info, duration: ToastInfo.Duration = .normal) -> Void { model.enqueueToast(message, type: type, duration: duration) }

    /// V5.13: dismiss task 单点维护
    /// - 每次启动新 task 取消上一个（防 race）
    /// - 队列空时停；非空时按队首 duration 续 task
    private func scheduleDismiss(after seconds: TimeInterval) -> Void { model.scheduleDismiss(after: seconds) }

    /// 兼容旧 showToast 调用（V4.36.x 8 处 call site 保持 0 改动）
    ///   Day 5 错误 toast 改用 enqueueToast(message, type: .error, duration: .long)
    private func showToast(_ message: String, type: ToastView.ToastType = .info) -> Void { model.showToast(message, type: type) }


    // 处理 Delete 键
    private func handleDelete() -> Void { model.handleDelete() }

    // V4.36.6: 从 PhotoGridView.handleTap 抽出到 ContentView——3 视图共用
    //   旧版 tap 处理逻辑在 PhotoGridView 内, List/Timeline 视图无法复用
    //   现在 3 视图都传 onTap: handleTap 闭包, 选中行为完全一致
    private func handleTap(_ photo: Photo) -> Void { model.handleTap(photo) }

    // ─── 上一张 / 下一张 ───
    // V3.6.52: 用 selection.selectingSingle(_:) 替 2 字段手工赋值
    private func goPrev() -> Void { model.goPrev() }

    private func goNext() -> Void { model.goNext() }

    // ─── V4.0.0.6: 缩放快捷键（⌘+ / ⌘-）───
    // 缩放搬到侧栏顶部后，必须配快捷键——否则要"绕到侧栏才能缩"
    // 参考 macOS Photos.app / Preview：⌘+ / ⌘- 缩略图大小
    private func zoomIn() -> Void { model.zoomIn() }

    private func zoomOut() -> Void { model.zoomOut() }

    // V4.15.0: ⌘0 reset zoom——macOS Photos/Finder 标准快捷键
    //   恢复 thumbnailSize 到用户偏好（storedThumbnailSize from @AppStorage）
    //   不硬编码 170——尊重用户在 Settings 设的 default
    //   （与 ⌘+ / ⌘- 配合——缩放后可一键 reset 回默认）
    private func resetThumbnailSize() -> Void { model.resetThumbnailSize() }

    // V4.37.1: 触发 Quick Look——复用于 ⌘Y 菜单 / toolbar 按钮 / 空格键
    //   抽出 onSpace 闭包逻辑（避免 3 处重复 currentVisibleURLs + firstIndex 计算）
    // V5.42: 改走 enterImmersiveFromSelection()——跟双击 / ⌘↩ Return 同路径
    //   - 修 'No items selected' bug（QLPreviewPanel 路径 URL 不可达）
    //   - 4 个入口 (⌘Y / 工具栏 / 空格 / 双击) 行为完全一致
    //   - 镜像 Photos.app 行为：Spacebar 选中照片进沉浸式
    // V5.42: 旧 QLPreviewPanel 实现删除（QuickLookPreviewController.swift + QuickLookBridge）
    private func showQuickLook() -> Void { model.showQuickLook() }

    // V4.37.4: titlebar accessory tooltip——反映当前 showDetail 状态
    //   加 ⌘I 快捷键提示——用户 hover 时发现 macOS Photos 标准快捷键
    //   仿 V4.36.x Filter 按钮 "筛选 (N)" 动态 tooltip 模式
    private func titlebarAccessoryTooltip(isActive: Bool) -> String { model.titlebarAccessoryTooltip(isActive: isActive) }

    // ─── 启动时清理过期回收站项（V3.6 NEW）───
    private func purgeExpiredTrashOnStartup() -> Void { model.purgeExpiredTrashOnStartup() }

    // ─── 启动导入 ───
    private func startImport() -> Void { model.startImport() }

    // ─── 拖入导入 (V5.39.6 NEW) ───
    /// Finder 拖文件 / 文件夹到 grid 任何位置直接导入
    ///   - 走 ImageImporter 内部 collectFiles 递归展开文件夹
    ///   - 走 runImportWithDuplicateCheck 同 NSOpenPanel 路径 (fileHash 重复检测 + 进度反馈)
    ///   - 空 urls 直接 return (用户拖了非图片文件)
    private func handleDropImport(_ urls: [URL]) -> Void { model.handleDropImport(urls) }

    /// V3.6.24: 扫现有 photo + 算新 url fileHash，弹 dialog 让用户选
    /// V3.6.27: 改用 async 版本（后台 actor 算 SHA256，不阻塞 main thread）
    private func runImportWithDuplicateCheck(urls: [URL]) -> Void { model.runImportWithDuplicateCheck(urls: urls) }

    // V3.6.24: 重复检测 dialog 的动态 title
    // V5.52-4: 实现搬到 ContentViewModel.duplicateDialogTitle
    private var duplicateDialogTitle: String { model.duplicateDialogTitle }

    private func confirmSkipDuplicates() -> Void { model.confirmSkipDuplicates() }

    private func confirmImportAllDuplicates() -> Void { model.confirmImportAllDuplicates() }

    private func cancelDuplicateImport() -> Void { model.cancelDuplicateImport() }

    /// V3.6.24: 实际跑导入（dialog 确认后调用，或无重复时直接调）
    /// V5.13: 接 ImportResult——成功 1 个 success toast + 失败 N 个 error toasts
    /// V5.15: 进度用 inserted/failureCount 显示；混合结果合并 1 个 summary toast
    private func importPhotos(urls: [URL]) -> Void { model.importPhotos(urls: urls) }

    // ─── 拖拽导入 ───
    /// V4.49.0: 支持的图像扩展名——拖入时先过滤,避免非图片文件进 importer
    /// 跟 ImageImporter.supportedExtensions 保持一致
    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"
    ]

    private func handleDrop(providers: [NSItemProvider]) -> Bool { model.handleDrop(providers: providers) }

    /// V4.49.0: 递归展开文件夹——返回所有文件 URL
    ///   Photos.app 行为：拖入文件夹 = 导入该文件夹 + 子文件夹的图片
    ///   跳隐藏文件 (.DS_Store 等)
    private static func expandFolders(_ urls: [URL]) -> [URL] { Self.expandFolders(urls) }

    // V4.1.0 l: 切换侧栏 section 时清选中（避免"选中的照片不在新 section"）
    private func clearSelectionOnFilterChange() -> Void { model.clearSelectionOnFilterChange() }

    // ─── 删除单张（V3.6：走 RecycleBinService，不再调 undoManager）───
    private func deleteSinglePhoto() -> Void { model.deleteSinglePhoto() }

    // ─── 批量删除（V3.6：走 RecycleBinService，不再调 undoManager）───
    private func batchDelete() -> Void { model.batchDelete() }

    // V3.5.19：从 PhotoGridView 搬上来的 4 个 batch 方法
    // 原因：multi-select 顶部栏被移到详情面板里，详情面板的 MultiSelectDetailView
    // 需要直接调用这些方法。

    // ─── 批量移动到文件夹 ───
    private func batchMove(to folder: Folder?) -> Void { model.batchMove(to: folder) }

    // ─── 批量加标签 ───
    private func batchAddTag(_ tag: Tag) -> Void { model.batchAddTag(tag) }

    // V5.12: 批量评分
    //   - 多选 N 张 → onBatchSetRating(M) 一次设 M 星
    //   - M = 0 表示清除评分
    //   - 与详情页 RatingStarsView 共用同一 photo.rating 字段
    //   - ⌘0-⌘5 快捷键也走同一函数（ContentKeyboardShortcuts.onSetRating）
    private func batchSetRating(_ rating: Int) -> Void { model.batchSetRating(rating) }

    // ─── 批量导出 ───
    private func batchExport() -> Void { model.batchExport() }

    /// 避免导出时文件名冲突
    private func uniqueDestinationForBatchExport(for url: URL) -> URL { model.uniqueDestinationForBatchExport(for: url) }

    // ─── V5.7: 砍 batchToggleFavorite()——多选面板的"收藏"按钮已移除 ───

    // ─── 回收站操作（V3.6 NEW）───

    /// 在 visiblePhotos ∩ selectedIDs 上执行 trash 操作（3 个 batch 方法的共用骨架）
    /// - Parameters:
    ///   - operation: 实际的 SwiftData 变更（recycle / restore / purge）
    ///   - message: toast 消息生成器（接收处理数量）
    ///   - type: toast 类型（默认 .info；恢复用 .success）
    /// V5.13: 注入 onError → RecycleBinService 失败时 toast
    private func performOnSelectedTrash(_ operation: (RecycleBinService, [Photo]) -> Void, message: (Int) -> String, type: ToastView.ToastType = .info) -> Void { model.performOnSelectedTrash(operation, message: message, type: type) }

    /// 恢复选中的照片（从回收站 → 图库）
    private func restoreSelectedFromTrash() -> Void { model.restoreSelectedFromTrash() }

    /// 永久删除选中的照片（文件 + SwiftData）
    private func permanentDeleteSelected() -> Void { model.permanentDeleteSelected() }

    /// 清空回收站（永久删除所有 trashed 项；不走 selectedIDs）
    private func emptyTrash() -> Void { model.emptyTrash() }

    /// V3.6.15 NEW: 重复图清理 — 每组保留 importedAt 最新的，其他移到回收站
    private func keepNewestPerDuplicateGroup() -> Void { model.keepNewestPerDuplicateGroup() }

    // ─── 序列化 SidebarSelection ───
    private func serializeSelection(_ selection: SidebarSelection?) -> String { model.serializeSelection(selection) }

    // ─── 恢复 SidebarSelection ───
    private func restoreSelection(_ key: String) -> SidebarSelection? { model.restoreSelection(key) }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}

// MARK: - V4.8.1: NSToolbar 桥接 extension (V5.51-6: 已抽到 Views/ContentView+ToolbarSync.swift)

// MARK: - V4.10.0: window chrome + NSToolbar 桥接 extension (V5.51-7: 已抽到 Views/ContentView+WindowChrome.swift)
