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
//  收成 1 行 `selection.selectedPhotos(in: model.visiblePhotos)`；3 个 O(n) lookup
//  (selectedPhoto/model.singleSelectedPhoto/model.currentIndex) 合并为 1 个 `model.resolvedSingle`。
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    // V3.6.52: 3 @State (selectedPhoto/selectedIDs/lastSelectedID) 合并为 1 @State<SelectionState>
    //   这是图片选中的唯一真相源；`selectedPhoto: Photo?` 改为下面的 computed property
    // V5.52-3: 22 个 @State business state 搬到 ContentViewModel; computed proxy 保留 reads/writes 语法
    // V6.28: Grid 业务 (selection/searchText/...) 迁 model.grid — Core 业务 (sidebarSelection/filterState/...) 仍 model
    private var selection: SelectionState {
        get { model.grid.selection }
        nonmutating set { model.grid.selection = newValue }
    }

    @State private var isBoxSelecting = false
    // V3.7.1: 框选进行中的 rect (caller 持有, BoxSelectionGesture 写)
    //   用于 overlay 显示 2pt accent border + "已选 N 张" floating label
    @State private var boxSelectionRect: CGRect? = nil
    // V6.17.0: 改名 isBoxSelecting → isMarqueeActive (真矩形圈选, 不是简化 "全选可见")
    //   state 留在 ContentView (overlay + selection binding 都要), 但 gesture 移到 PhotoGridView
    //   通过 binding 透传 — cell frames 在 photoGrid-local 算, gesture 也挂那, hit test 对得上
    private var isMarqueeActiveBinding: Binding<Bool> {
        Binding(get: { isBoxSelecting }, set: { isBoxSelecting = $0 })
    }
    private var marqueeRectBinding: Binding<CGRect?> {
        Binding(get: { boxSelectionRect }, set: { boxSelectionRect = $0 })
    }

    // 侧边栏的选中项 (Core — 决定"显示什么 scope")
    private var sidebarSelection: SidebarSelection? {
        get { model.sidebarSelection }
        nonmutating set { model.sidebarSelection = newValue }
    }

    // V4.36.x: 工具栏筛选按钮状态（session-only，不写 UserDefaults / SwiftData）
    //   4 维：folders / tags / shapes / minRating
    //   与侧边栏并存补充——侧边栏选主上下文，筛选按钮叠加多选精细控制
    //   (Core — 跟 sidebarSelection 配合决定 visiblePhotos 过滤维度)
    private var filterState: FilterState {
        get { model.filterState }
        nonmutating set { model.filterState = newValue }
    }

    // 搜索文本 (Grid — 跟 selection/sortOption/thumbnailSize 一起组成 grid 业务)
    private var searchText: String {
        get { model.grid.searchText }
        nonmutating set { model.grid.searchText = newValue }
    }

    // 缩略图大小 (Grid — zoom in/out 改 live, ⌘0 reset 清 live)
    private var thumbnailSize: CGFloat {
        get { model.grid.thumbnailSize }
        nonmutating set { model.grid.thumbnailSize = newValue }
    }
    // V3.6.13: viewMode 改用 @AppStorage 持久化（SettingsView 可设默认）
    // V5.59-2: 删 @AppStorage viewModeRaw, viewMode computed 走 model.settings.viewModeRaw
    private var viewMode: ViewMode {
        get { model.viewMode }
        nonmutating set { model.viewMode = newValue }
    }

    // 排序方式（Eagle 化工具栏新增）— Grid 业务 (V6.28)
    private var sortOption: SortOption {
        get { model.grid.sortOption }
        nonmutating set { model.grid.sortOption = newValue }
    }

    // V4.36.6: visiblePhotos 从 @State 改为 computed property
    //   旧 @State + onVisiblePhotosChange 模式只服务于 grid view——切到 list/timeline 不更新
    //   改 computed property 用 PhotoStats.filtered 共享 helper, 3 视图同步
    // 注: 侧栏 section 折叠状态 (@AppStorage) 属于 SidebarView 持有, 不在此

    // V5.60-4: 30 个 D 类 get-only proxy 全删——caller 直接用 model.X
    //   之前 V5.52-3 保留的 "reads/writes 语法糖", 删后改用 model.X 单一访问
    //   例外: model.X 是 @Observable 字段, 在 View body 读取自动追踪
    //   保留: bindableModel/columnLayout/showingDuplicateCheck/hasPurgedExpiredTrash (4 个 helper)
    //   保留: 28 个 get/set 业务 state proxy (selection/sidebarSelection/filterState/...)
    //     → 这些写源需要 proxy 包装 (setter 路径不能直接 model.X = Y 走 computed)

    // 拖拽状态
    @State private var isDropTargeted = false

    // 批量删除确认 (Grid — V6.28)
    private var showingBatchDeleteConfirm: Bool {
        get { model.grid.showingBatchDeleteConfirm }
        nonmutating set { model.grid.showingBatchDeleteConfirm = newValue }
    }
    // P4.2: 批量重命名 sheet — mini toolbar Rename 按钮 / File menu ⌘⇧R 触发 (Grid — V6.28)
    private var showingBatchRenameSheet: Bool {
        get { model.grid.showingBatchRenameSheet }
        nonmutating set { model.grid.showingBatchRenameSheet = newValue }
    }

    // V3.6.6: 清空回收站二次确认（防误操作：永久删除所有 trashed 项）— Grid (V6.28)
    private var showingEmptyTrashConfirm: Bool {
        get { model.grid.showingEmptyTrashConfirm }
        nonmutating set { model.grid.showingEmptyTrashConfirm = newValue }
    }

    // V3.6.24: 导入时重复检测 dialog（防止 fileHash 重复的图片被再次导入）
    // V3.6.24: 导入时重复检测 dialog（防止 fileHash 重复的图片被再次导入）
    private var importDuplicateCheck: ImageImporter.DuplicateCheckResult? {
        get { model.importVM.importDuplicateCheck }
        nonmutating set { model.importVM.importDuplicateCheck = newValue }
    }
    private var pendingImportURLs: [URL] {
        get { model.importVM.pendingImportURLs }
        nonmutating set { model.importVM.pendingImportURLs = newValue }
    }

    // 批量移动
    // （showingBatchMoveSheet 已移除：批量移动流程当前在 PhotoGridView 内联实现，
    //   该状态从未被读。如未来要重新走 sheet 流程再加回。）

    // 新建文件夹弹窗 (Grid — V6.28)
    private var showingNewFolderAlert: Bool {
        get { model.grid.showingNewFolderAlert }
        nonmutating set { model.grid.showingNewFolderAlert = newValue }
    }
    private var newFolderName: String {
        get { model.grid.newFolderName }
        nonmutating set { model.grid.newFolderName = newValue }
    }

    // 沉浸式查看 (Grid — V6.28)
    private var immersivePhoto: Photo? {
        get { model.grid.immersivePhoto }
        nonmutating set { model.grid.immersivePhoto = newValue }
    }
    private var immersiveIndex: Int {
        get { model.grid.immersiveIndex }
        nonmutating set { model.grid.immersiveIndex = newValue }
    }

    // 栏显隐状态（ContentView 唯一持有，ImageGalleryApp 通过 UserDefaults 同步）
    // V5.59-2: 删 @AppStorage showSidebar, 改用 computed proxy 走 model.settings.showSidebar
    private var showSidebar: Bool {
        get { model.settings.showSidebar }
        nonmutating set { model.settings.showSidebar = newValue }
    }
    // V5.22: 默认 showDetail = false——grid 窗口右侧 30% 留给图片而不是空 detail panel
    //   选照片时仍可在 onChange 触发自动 show（V5.22 后续 sprint 加）——目前只改默认
    // V5.59-2: 删 @AppStorage showDetail, 改用 computed proxy 走 model.settings.showDetail
    private var showDetail: Bool {
        get { model.settings.showDetail }
        nonmutating set { model.settings.showDetail = newValue }
    }

    // V4.13.0: 撤回 V3.5.18 旧 @State showSettings——⌘, 现在走 Settings scene
    //   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 状态
    // V5.59-2: 删 @AppStorage accentColorID, 内部仅由 model.accentColor (computed) 消费

    // V3.6 NEW: 回收站保留时长（默认 30 天）
    // V5.59-2: 删 @AppStorage retentionDays, 改用 computed proxy 走 model.settings.trashRetentionDays
    private var retentionDays: Int {
        get { model.settings.trashRetentionDays }
        nonmutating set { model.settings.trashRetentionDays = newValue }
    }

    // V3.6.22: 应用外观（默认跟随系统）
    // V5.59-2: 删 @AppStorage appearanceModeRaw, model.appearanceMode computed 走 model.appearanceMode

    // V3.6 NEW: 启动时清理过期回收站项的"只跑一次"标记
    // ContentView 可能多次出现（开关窗口、切 sidebar），用 flag 避免重复清理
    @State private var hasPurgedExpiredTrash = false

    // V6.22.3 (P2 #10): Onboarding sheet 状态 — 第一次启动 + 未看过 → 弹 3-card sheet
    //   用户点 "开始使用" / "跳过" → model.settings.hasSeenOnboarding = true → sheet dismiss
    //   跟 P4.2 batchRenameSheet / P4.1.1 smartFolderCreateSheet 同 pattern
    private var showingOnboarding: Bool {
        get { !model.settings.hasSeenOnboarding }
        nonmutating set { _ = newValue }
    }

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
        get { model.windowVM.titlebarAccessory }
        nonmutating set { model.windowVM.titlebarAccessory = newValue }
    }

    // V4.20.0: 撤回 V4.19.0 glassNamespace + glassEffectUnion
    //   macOS 26 glassEffectUnion 在 sidebar 边界外产生 outline 痕迹（用户截图反馈）
    //   回滚到 V4.18.0 单 view glassEffect 状态（仅 SidebarView/DetailView 4 处 .glassEffect）

    /// V4.12.0 删: currentVisibleURLs (URL 列表)——V5.42 不再走 QLPreviewPanel
    ///   showQuickLook 直接调 enterImmersiveFromSelection, 不需要 URL 列表
    ///   保留 visiblePhotos + fileURL 在 Photo 数据模型, 这里不再展开

    // 当前选中的强调色（从 accentColorID 解析）

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
    // P4.1.1: smartFolders @Query — 跟 allPhotos/folders/allTags 同模式, 推 model.smartFoldersCache
    @Query(sort: \SmartFolder.order, order: .forward) private var smartFolders: [SmartFolder]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext

    // V5.59-2: 接收 ImageGalleryApp 注入的 sharedSettings 引用
    //   ContentView/menu/SettingsView 共享同一 UserSettings 实例
    let settings: UserSettings

    // V5.52-1: ContentViewModel 业务模型——@Observable class
    //   V5.52-3 之后非 Optional——.task 里注入 modelContext
    //   V5.59-1: init 接受 settings (与 let settings 共享同一引用)
    @State private var model: ContentViewModel

    /// V5.59-2: init 从 ImageGalleryApp 传 settings 引用
    ///   model 与 menu/SettingsView 共享同一 UserSettings 实例
    init(settings: UserSettings) {
        self.settings = settings
        self._model = State(initialValue: ContentViewModel(settings: settings))
    }

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
    // V5.59-2: 删 @AppStorage storedThumbnailSize/storedSidebarKey/storedSortOption
    //   改用 model.thumbnailSize/model.settings.sidebarSelection/model.sortOption
    //   (thumbnailSize 是 CGFloat, sortOption 是 SortOption, sidebarSelection 是 SidebarSelection?)
    //   已有 computed proxy 透传 (上 L70-78), 无需重复声明
    // V5.31: 默认 sort 改 filenameAsc——Photos.app Library 视图无 date header
    //   - Photos 真版: Library 连续流, 无 date section
    //   - 改 filenameAsc: 字母序, isDateBased=false → masonryFlatLayout (无 header)
    //   - 老用户 @AppStorage 已有 storedSortOption 不受影响 (仅新装/重置生效)
    // V5.59-2: 删 @AppStorage storedSortOption, sortOption computed (L75) 已走 model.sortOption
    // V5.17: 缩略图布局模式 (2 选项 .square / .squareFit, V5.47 砍 .masonry)
    //   镜像 AppearanceMode Int-backed pattern
    //   @AppStorage 持久化 + computed 读写 + 透传给 ViewOptionsPopover/PhotoGridPane
    //   nonmutating set 必备——否则 closure 内 [self] capture 后 setter 改 self 编译失败
    // V5.59-2: 删 @AppStorage storedLayoutModeRaw, layoutMode computed 走 model.layoutMode
    private var layoutMode: ThumbnailLayoutMode {
        get { model.layoutMode }
        nonmutating set { model.layoutMode = newValue }
    }

    // V3.5.12：三栏列宽（HStack + 自定义 drag handles，避开 NSSplitView）
    // V5.59-2: 删 @AppStorage storedSidebarWidth/storedDetailWidth, computed proxy 走 model
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

    // V5.8: 砍 filterFavorites property——V5.7 砍 .favorites 侧边栏后此 property 永远 false
    //   用户想看"收藏"改走筛选 popover (评分 ≥ 5)


    // 派生属性——全部 proxy 到 model

    // V3.5.6 Finder 化: 总占用空间格式化

    // V4.2.0 P0❸: navigationTitle

    // V4.2.0 P0❸: subtitle——"N 张 · X MB"

    // V4.4.8: toolbar 搜索框左 padding

    // V3.5.19: 当前选中图片总大小

    // V3.6: 回收站 count + size

    // V3.6.15: 重复图 group / purgeable count / size

    // V3.5.17: 把 6 个宽度 state vars + 4 个约束 + 2 个 AppStorage 钩子打包
    // V5.52-4: state vars 都走 model, 这里用 constants from model
    // V5.60-5: 尝试抽到 ContentView+ColumnLayout.swift extension 失败——`private var model` 跨文件不可见
    //   撤回, 保留在 ContentView 内——20 行不值得做跨文件重构
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
            // V6.33.1: Dynamic Type 注入 — 用户选的 fontScale 走 .dynamicTypeSize 环境
            //   只影响用 semantic font 的 view (V6.34 慢慢把 Typography 迁 semantic)
            .environment(\.dynamicTypeSize, model.settings.appFontScale.dynamicTypeSize)
            // V4.10.0: 6 个 chrome modifier 打包（title/subtitle/colorScheme/WindowAccessor/NSToolbar sync）
            // V5.24: 加 layoutMode + thumbnailSize 参数——传给 windowChromeAndToolbar 推 NSToolbar segment/slider
            // V5.39.3: 加 sortOption 参数——推 NSToolbar sortMenu 按钮 (image 跟 sortOption 走)
            .windowChromeAndToolbar(
                title: model.grid.currentViewTitle,
                subtitle: model.grid.currentViewSubtitle,
                colorScheme: model.appearanceMode.colorScheme,
                selection: selection,
                searchText: searchText,
                // V6.38.1 (Phase 1): model 透传 — syncNSToolbarImportProgress 读 model.importVM.importProgress
                model: model,
                layoutMode: layoutMode,
                thumbnailSize: thumbnailSize,
                sortOption: sortOption,
                configureWindow: { model.windowVM.configureToolbar(window: $0) }
            )
            // V5.59-2: 抽离 4 dialog + 4 onChange + 1 task 到 contentBodyModifiers 解决 type-check 超时
            // V6.28: grid 业务 closure 走 model.grid.X() — Core (startImport/restoreSelection/etc) 仍 model
            .contentBodyModifiers(
                model: model,
                bindableModel: bindableModel,
                bindableGrid: bindableGrid,
                settings: settings,
                modelContext: modelContext,
                allPhotos: allPhotos,
                folders: folders,
                allTags: allTags,
                // P4.1.1: smartFolders 推 model.grid.smartFoldersCache
                smartFolders: smartFolders,
                selection: selection,
                sidebarSelection: sidebarSelection,
                showSidebar: showSidebar,
                showDetail: showDetail,
                filterState: filterState,
                visiblePhotos: model.grid.visiblePhotos,
                batchDeleteTitle: model.grid.batchDeleteTitle,
                duplicateDialogTitle: model.grid.duplicateDialogTitle,
                undoManager: undoManager,
                accentColor: model.accentColor,
                hasPurgedExpiredTrash: $hasPurgedExpiredTrash,
                showingNewFolderAlert: Binding(get: { showingNewFolderAlert }, set: { showingNewFolderAlert = $0 }),
                onImport: { model.importVM.startImport() },
                // V6.20.0 (code audit fix #1 + #9): 3 个入口 (⌘N hidden button / ⌘⇧N 菜单 / SidebarView "+") 都清空 newFolderName
                //   避免上次 name 残留; 之前 ContentView 路径不清, SidebarView 清, 两路不一致
                onNewFolder: { model.grid.newFolderName = ""; showingNewFolderAlert = true },
                onResetFilters: { model.grid.resetFilters() },
                onCopy: { model.grid.copyToPasteboard() },
                onToggleSortDirection: { model.toggleSortDirection() },
                // V6.13.3: 工具栏 sidebar toggle 触发 withAnimation 包裹
                //   配合 MainSplitView 的 .transition(.move + .opacity) 实现 0.3s 滑动
                //   之前硬切——MainSplitView line 75 transition 仍触发但 toggle 本身没 anim 驱动
                onToggleSidebar: { withAnimation(Animations.medium) { showSidebar.toggle() } },
                onSetRating: { model.grid.batchSetRating($0) },
                onDelete: { model.grid.handleDelete() },
                onPrev: { model.grid.goPrev() },
                onNext: { model.grid.goNext() },
                onSelectAll: { selection = selection.settingAll(in: model.grid.visiblePhotos) },
                onZoomIn: { model.grid.zoomIn() },
                onZoomOut: { model.grid.zoomOut() },
                onResetZoom: { model.grid.resetThumbnailSize() },
                onExport: { model.grid.batchExport() },
                onReturn: { model.grid.enterImmersiveFromSelection() },
                onSpace: { model.grid.showQuickLook() },
                onBatchDelete: { model.grid.batchDelete() },
                onCreateFolder: { model.createFolderFromAlert() },
                onEmptyTrash: { model.grid.emptyTrash() },
                onConfirmSkipDuplicates: { model.importVM.confirmSkipDuplicates() },
                onConfirmImportAllDuplicates: { model.importVM.confirmImportAllDuplicates() },
                onCancelDuplicateImport: { model.importVM.cancelDuplicateImport() },
                onSelectionEscape: { selection = .empty },
                onRestoreSelection: { model.restoreSelection(model.settings.sidebarSelection) },
                onSerializeSidebarSelection: { model.serializeSelection($0) },
                onClearSelectionOnFilterChange: { model.grid.clearSelectionOnFilterChange() },
                onSyncTitlebarAccessory: { syncTitlebarAccessory(isActive: $0) },
                onToggleShowDetail: { showDetail = $0 },
                onPurgeExpiredTrashOnStartup: { model.purgeExpiredTrashOnStartup() },
                onCheckStorage: { model.checkStorage() },
                onMigrateFavoriteToRating: { Photo.migrateFavoriteToRating(in: allPhotos, context: modelContext) }
            )
    }

    // V5.52-3: @Bindable shadow @State model——macOS 14+ 推荐模式
    //   让 body 内的 $model.X 走 Bindable dynamicMember subscript → Binding<T>
    //   pane builders 也 shadow 一份, 各自 body 范围独立
    // V6.28: Grid 业务 binding 走 bindableGrid (Bindable<GridViewModel>)——Core 仍 bindableModel
    private var bindableModel: Bindable<ContentViewModel> { Bindable(model) }
    private var bindableGrid: Bindable<GridViewModel> { Bindable(model.grid) }

    // V4.0.0: 抽出 importDuplicateCheck 状态到 binding（让 type-check 过得去）
    // V5.52-4: importDuplicateCheck 走 model, 这里直接构造 binding
    private var showingDuplicateCheck: Binding<Bool> {
        Binding(
            get: { model.importVM.importDuplicateCheck != nil },
            set: { if !$0 { model.importVM.importDuplicateCheck = nil } }
        )
    }

    // V4.0.0: 抽出批量删除确认 title（避免 body 内 string interpolation 触发 type-check 超时）
    // V5.52-4: 走 Copy 字典


    // V6.19.3 (P0 #13): 删 7 个 1-line forwarder (checkStorage/createFolderFromAlert/
    //   toggleSortDirection/copyToPasteboard/enterImmersive/enterImmersiveFromSelection/
    //   resetFilters)——caller 走 model.X() 闭包, 节省 7 行净代码 + 文档
    //   保留: syncTitlebarAccessory (有内部 logic) + 注释 (shareSelected 已删 + immersive 注释)

    // V5.52-8: 删 shareSelected (dead code, 0 caller)
    //   NSSharingServicePicker 路径从未被 wire 进来——V3.6.52 之后用 selection.selectedPhotos
    //   现如要加 share, 直接走 macOS 系统菜单 (Finder > Share) 或 toolbar 按钮
    // V6.19.0 (P0 #1): 走 NSSharingServicePicker (多图) + ShareLink (单图 cell 菜单)

    // V5.59-2: 拆出 helper 函数, 避免 .onChange(of: showDetail) body 复杂导致 type-check 超时
    // V6.19.3 (P0 #13): titlebarAccessoryTooltip 1-line forwarder 删了, 这里直接走 model.X
    private func syncTitlebarAccessory(isActive: Bool) {
        titlebarAccessory?.setActive(isActive)
        let tooltip = model.windowVM.titlebarAccessoryTooltip(isActive: isActive)
        titlebarAccessory?.setTooltip(tooltip)
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
            showSidebar: Binding(get: { showSidebar }, set: { showSidebar = $0 }),
            undoManager: undoManager,
            toastQueue: toastQueue,
            immersivePhoto: Binding(get: { model.grid.immersivePhoto }, set: { model.grid.immersivePhoto = $0 }),
            immersiveIndex: Binding(get: { model.grid.immersiveIndex }, set: { model.grid.immersiveIndex = $0 }),
            visiblePhotos: model.grid.visiblePhotos,
            onImmersiveDismiss: { immersivePhoto = nil },
            // V6.21.1 (Phase 1.2): toast close button → 用户主动 dismiss
            //   调 model.scheduleDismissToast() 移除队首 + 触发 next toast 显示
            onToastDismiss: { model.scheduleDismissToast() }
        )
        // V6.21.0 (Phase 1.1 UX polish): 圈选启动 → dismiss marquee hint
        //   isBoxSelecting 由 ContentView @State 持有, mainSplitPane 传 $isBoxSelecting 给 MainSplitView
        //   BoxSelectionGesture 启动时 set true → 这里 onChange 触发 → dismiss hint
        .onChange(of: isBoxSelecting) { _, new in
            if new && !model.settings.hasShownMarqueeHint {
                model.settings.hasShownMarqueeHint = true
            }
        }
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
    // V6.17.0: 矩形圈选 gesture 移到 PhotoGridView 内部 (cell frames 同坐标系)
    //   mainSplitPane 不再挂 gesture, 也不挂 overlay (overlay 还在用 mainSplitPane 旧坐标,
    //   跟 photoGrid 内部 rect 略差; V1 接受, 后续 V2 polish 把 overlay 也搬进去)
    private var mainSplitPane: some View {
        MainSplitView(
            layout: columnLayout,
            // V5.59-2: showSidebar/showDetail 改为 computed proxy, 需显式 Binding(get:set:) 替代 $
            showSidebar: Binding(get: { showSidebar }, set: { showSidebar = $0 }),
            showDetail: Binding(get: { showDetail }, set: { showDetail = $0 }),
            isDropTargeted: $isDropTargeted,
            isBoxSelecting: $isBoxSelecting,
            onDrop: { providers in model.importVM.handleDrop(providers: providers) },
            sidebar: { sidebarPane },
            center: { gridPane },
            detail: { detailPane }
        )
        // V6.17.0.2: overlay 搬进 photoGrid — rect 跟 overlay 同 space (photoGrid),
        //   视觉精准跟手 (用户报告 V6.17.0.1 矩形不跟手就是这里)
        // P3.1.3: 选完 mini toolbar — 4 action (Tag / Move / Export / Delete)
        //   选非空时浮在 content 顶部, 走 macOS Photos / Finder 范式
        //   regular material + accent color, 跟系统级 toolbar 视觉一致
        .overlay(alignment: .top) {
            if model.grid.isMultiSelect || !model.grid.selection.selectedIDs.isEmpty {
                SelectionMiniToolbar(model: model)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // V6.21.0 (Phase 1.1 UX polish): 圈选功能发现性提示 — first-run floating tip
        //   显示条件: 库有内容 + selection 空 + 用户没看过提示
        //   dismiss 路径: 1) 点 "知道了" → settings.hasShownMarqueeHint = true
        //                 2) 首次拖动 (BoxSelectionGesture onChanged) → 同上
        //   V6.17.1 plain left-drag 圈选是核心交互, 但用户不知道有 — 这是发现性缺口
        .overlay(alignment: .center) {
            if !model.settings.hasShownMarqueeHint
                && model.grid.selection.selectedIDs.isEmpty
                && !model.grid.allPhotos.isEmpty {
                MarqueeHintView(onDismiss: {
                    model.settings.hasShownMarqueeHint = true
                })
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.settings.hasShownMarqueeHint)
        .animation(.easeInOut(duration: 0.25), value: model.grid.allPhotos.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: model.grid.isMultiSelect)
        .animation(.easeInOut(duration: 0.2), value: model.grid.selection.selectedIDs.isEmpty)
    }

    private var sidebarPane: some View {
        SidebarView(
            selection: bindableModel.sidebarSelection,
            photoSelection: bindableGrid.selection,
            // V4.0.0.6: 缩放 + 排序搬到侧栏顶部（"视图控制中心"）
            // V6.28: thumbnailSize/sortOption 在 grid
            thumbnailSize: bindableGrid.thumbnailSize,
            sortOption: bindableGrid.sortOption,
            // P4.1.1: 注入 model 让 sidebar 触发 smart folder 创建 sheet
            model: model,
            // V6.10: 注入 undoManager 让拖到 folder 注册 undo (跟 batchMove 模式一致)
            undoManager: model.undoManager
            // V4.1.0f: 移除 showSidebar binding（hide 按钮完全搬回主工具栏）
        )
    }

    // V4.36.6: 中间列根据 viewMode 切换 3 视图
    //   旧版 gridPane 只返回 PhotoGridPane, viewMode 在 popover 切换无效
    //   新版 switch viewMode → 3 个 Pane 之一, 都用 visiblePhotos (PhotoStats.filtered)
    //   共享 filter helper 保证 3 视图显示完全一致的内容
    // V6.31.1: 加 transition modifier — view mode 切换 crossfade + scale 0.95→1 (Photos.app 范式)
    //   配合 .animation(value: viewMode) 让 transition 真触发
    @ViewBuilder
    private var gridPane: some View {
        // V6.31.1: 包 Group → switch 多 view 转 single view, 上面 .transition / .animation 修饰才能作用
        Group {
            switch viewMode {
            case .grid:
                PhotoGridPane(
                    // V6.28: selection 在 grid
                    selection: bindableGrid.selection,
                    folder: model.grid.currentFolder,
                    tag: model.grid.currentTag,
                    searchText: searchText,
                    // V5.8: 砍 filterFavorites
                    filterUnfiled: model.grid.filterUnfiled,
                    filterDuplicates: model.grid.filterDuplicates,
                    filterRecent7Days: model.grid.filterRecent7Days,
                    filterLargeFiles: model.grid.filterLargeFiles,
                    filterInTrash: model.grid.filterInTrash,
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
                // V5.60-6 启动恢复 + V5.61-1 auto-save——PhotoGridView 双向读写 model
                scrollAnchorPhotoID: model.grid.scrollAnchorPhotoID,
                // V4.36.6: visiblePhotos 改 computed property, 此 callback 不再需要
                //   保留参数避免破坏 PhotoGridPane 签名——传 noop
                onVisiblePhotosChange: { _ in },
                onImport: { model.importVM.startImport() },
                onBatchDelete: { showingBatchDeleteConfirm = true },
                onClearMultiSelect: { selection = .empty },
                // V6.22.1 (P2 #2): 旋转回调 — cell → pane → grid view 透传, 最终调 model.grid.rotateSelected
                //   单 cell 右键 rotate (cell menu) — ContentView 先把 selection 设成单选这张图, 再 rotate
                onRotate: { photo, clockwise in
                    selection = selection.selectingSingle(photo.id)
                    model.grid.rotateSelected(clockwise: clockwise)
                },
                onDoubleTap: { model.grid.enterImmersive($0) },
                onClearFilters: { model.grid.resetFilters() },
                onExportComplete: { count in
                    model.showToast(Copy.exported(count), type: .success)
                },
                // V5.39.6: 拖入导入——从 Finder 拖文件/文件夹到 grid 直接导入
                //   走 ImageImporter.importURLs (同 NSOpenPanel 路径), 含 progress 跟踪 + toast 反馈
                //   filter 文件/文件夹筛选交给 ImageImporter.collectFiles 内部处理
                // V6.28: handleDropImport 仍 Core (Import 业务)
                onDropImport: { model.importVM.handleDropImport($0) },
                // V5.39.7: 重排回调——no-op (PhotoGridView 内部 @State trigger 已处理刷新)
                //   透传 onReorder 闭包到 cell → 调时增 reorderRefreshTrigger → .onChange → recomputePhotos
                //   ContentView 不需要做事, 闭包仅用于保持 chain 类型一致
                onReorder: {},
                // V5.61-1: .scrollPosition(id:) onChange 写回 model.grid (UserDefaults 持久化)
                onScrollAnchorChange: { newID in model.grid.scrollAnchorPhotoID = newID },
                // V6.17.0: 矩形圈选 state 透传到 PhotoGridView (跟 init 参数顺序对齐)
                //   PhotoGridView 内部 photoGrid 的 GeometryReader 算 cell frames,
                //   gesture 挂 photoGrid, 跟 cell frames 同坐标系
                isMarqueeActive: isMarqueeActiveBinding,
                marqueeRect: marqueeRectBinding
            )
        case .list:
            // V5.60-3: 合并 PhotoListPane + PhotoTimelinePane → PhotoListOrTimelinePane
            //   1 个 Pane + kind 路由替代 2 个 Pane——节省 88 行
            // V6.28: grid 业务走 model.grid
            PhotoListOrTimelinePane(
                selection: bindableGrid.selection,
                folder: model.grid.currentFolder,
                tag: model.grid.currentTag,
                searchText: searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: model.grid.filterUnfiled,
                filterDuplicates: model.grid.filterDuplicates,
                filterRecent7Days: model.grid.filterRecent7Days,
                filterLargeFiles: model.grid.filterLargeFiles,
                filterInTrash: model.grid.filterInTrash,
                // V4.36.x: 工具栏筛选 4 维（签名一致；本视图不实际用）
                selectedFolderIDs: filterState.folders,
                selectedTagIDs: filterState.tags,
                selectedShapes: filterState.shapes,
                filterMinRating: filterState.minRating,
                sortOption: sortOption,
                photos: model.grid.visiblePhotos,
                kind: .list,
                onTap: { model.grid.handleTap($0) },
                onDoubleTap: { model.grid.enterImmersive($0) }
            )
        case .timeline:
            PhotoListOrTimelinePane(
                selection: bindableGrid.selection,
                folder: model.grid.currentFolder,
                tag: model.grid.currentTag,
                searchText: searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: model.grid.filterUnfiled,
                filterDuplicates: model.grid.filterDuplicates,
                filterRecent7Days: model.grid.filterRecent7Days,
                filterLargeFiles: model.grid.filterLargeFiles,
                filterInTrash: model.grid.filterInTrash,
                // V4.36.x: 工具栏筛选 4 维（签名一致；本视图不实际用）
                selectedFolderIDs: filterState.folders,
                selectedTagIDs: filterState.tags,
                selectedShapes: filterState.shapes,
                filterMinRating: filterState.minRating,
                sortOption: sortOption,
                photos: model.grid.visiblePhotos,
                kind: .timeline,
                onTap: { model.grid.handleTap($0) },
                onDoubleTap: { model.grid.enterImmersive($0) }
            )
        }
        } // Group 关闭 (V6.31.1)
        // V6.31.1: view mode 切换过渡 — crossfade + scale 0.95→1 (Photos.app 范式)
        //   .transition 只在 view 出现/消失时触发, 配合 .animation(value: viewMode) 让 SwiftUI 跑 transition
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeInOut(duration: 0.3), value: viewMode)
    }

    private var detailPane: some View {
        DetailPane(
            // V6.28: grid 业务走 model.grid
            singleSelectedPhoto: model.grid.singleSelectedPhoto,
            isMultiSelect: model.grid.isMultiSelect,
            // V3.6.52: 用 selection.selectedIDs.count 替直接字段
            count: model.grid.filterInTrash ? model.grid.trashedCount : (model.grid.filterInDuplicates ? model.grid.duplicatePurgeableCount : selection.selectedIDs.count),
            totalSize: model.grid.filterInTrash ? model.grid.trashedTotalSize : (model.grid.filterInDuplicates ? model.grid.duplicatePurgeableSize : model.grid.selectedTotalSize),
            // V6.12: 重复图模式传 duplicateGroupCount 跟 count (purgeable) 区分
            //   duplicateGroupCount 跟 .duplicatePurgeableCount 是不同语义
            //   (groups vs 可清理照片), 之前 DetailPane:107 同一 count 传 2 次是 bug
            duplicateGroupCount: model.grid.filterInDuplicates ? model.grid.duplicateGroupCount : nil,
            folders: folders,
            allTags: allTags,
            onDelete: { model.grid.deleteSinglePhoto() },
            onPrev: { model.grid.goPrev() },
            onNext: { model.grid.goNext() },
            canPrev: model.grid.canPrev,
            canNext: model.grid.canNext,
            currentIndex: model.grid.currentIndex,
            totalCount: model.grid.visiblePhotos.count,
            // V3.5.19：多选 batch 动作从原 PhotoGridView.multiSelectTopBar 搬过来
            onBatchMove: { model.grid.batchMove(to: $0) },
            onBatchAddTag: { model.grid.batchAddTag($0) },
            // V5.7: 砍 onBatchToggleFavorite——多选面板的"收藏"按钮移除
            // V5.12: 加 onBatchSetRating——多选批量评分
            onBatchSetRating: { model.grid.batchSetRating($0) },
            onBatchExport: { model.grid.batchExport() },
            onBatchDelete: { showingBatchDeleteConfirm = true },
            // V3.6.52: 单字段 assignment 替 2 字段 pair
            onClearSelection: { selection = .empty },
            // V3.6 NEW: 回收站模式
            sidebarSelection: sidebarSelection,
            retentionDays: retentionDays,
            onTrashRestore: { model.grid.restoreSelectedFromTrash() },
            onTrashPermanentDelete: { model.grid.permanentDeleteSelected() },
            // V3.6.6: 改弹二次确认（不再直接调 emptyTrash）
            onEmptyTrash: { showingEmptyTrashConfirm = true },
            // V4.9.0: 回收站空时切回"全部"视图
            onExitTrash: { sidebarSelection = .all },
            // V3.6.15: 重复图清理（一键保留每组最新）
            onKeepNewestPerDuplicateGroup: { model.grid.keepNewestPerDuplicateGroup() },
            // V4.11.0: 存储不可写错误（nil = OK）
            storageError: storageErrorMessage,
            onRetryStorage: { model.checkStorage() },
            // V6.08: 详情面板错误回调 (rename 失败等) — show toast
            onError: { model.showToast($0, type: .error) }
        )
    }

    private var statusBarPane: some View {
        // V3.5.6 Finder 化：Status Bar（底部信息条）
        // V6.38.1 (Phase 1): 简化 — 只传全局 meta (总数 + 大小 + 缩略图档位)
        //   删: selectedCount / activeFilterCount / importProgress (重复显示, 搬到触发按钮附近)
        StatusBar(
            totalCount: allPhotos.count,
            // V6.28: totalSizeFormatted 在 grid
            totalSize: model.grid.totalSizeFormatted,
            thumbnailSize: thumbnailSize
        )
    }

    // V6.19.3 (P0 #13): 删 14 个 1-line forwarder (enqueueToast/scheduleDismiss/showToast/
    //   handleDelete/handleTap/goPrev/goNext/zoomIn/zoomOut/resetThumbnailSize/
    //   showQuickLook/titlebarAccessoryTooltip/purgeExpiredTrashOnStartup/startImport)——caller 走 model.X() 闭包
    //   保留: 全部注释 (业务背景, 未来 reader 看 V4.x 历史)

    // V5.42: 旧 QLPreviewPanel 实现删除（QuickLookPreviewController.swift + QuickLookBridge）
    // V6.19.0 (P0 #7): ⌘Y 走 Immersive (跟 Photos.app 一致), 不恢复 QLPreviewPanel

    // ─── 拖入导入 (V5.39.6 NEW) ───
    /// Finder 拖文件 / 文件夹到 grid 任何位置直接导入
    // V6.19.3 (P0 #13): 删 22 个 1-line forwarder (handleDropImport/runImportWithDuplicateCheck/
    //   confirmSkipDuplicates/confirmImportAllDuplicates/cancelDuplicateImport/importPhotos/
    //   handleDrop/clearSelectionOnFilterChange/deleteSinglePhoto/batchDelete/batchMove/batchAddTag/
    //   batchSetRating/batchExport/uniqueDestinationForBatchExport/performOnSelectedTrash/
    //   restoreSelectedFromTrash/permanentDeleteSelected/emptyTrash/keepNewestPerDuplicateGroup/
    //   serializeSelection/restoreSelection)——caller 走 model.X() 闭包
    //   保留: 全部业务注释
    //
    // V6.20.0 (code audit fix #2 + #10): 删 supportedImageExtensions static + expandFolders static
    //   两者都是死代码 (0 caller, ContentViewModel 已有同 signature 实现)
    //   expandFolders `Self.expandFolders(urls)` = 自己 → 无限递归, 任何未来 caller 直接 stack overflow
    //   拖入逻辑用 ImportViewModel.supportedImageExtensions / ImportViewModel.expandFolders (有 symlink 防护)
}

#Preview {
    ContentView(settings: UserSettings())
        .frame(width: 1000, height: 700)
}

// MARK: - V4.8.1: NSToolbar 桥接 extension (V5.51-6: 已抽到 Views/ContentView+ToolbarSync.swift)

// MARK: - V4.10.0: window chrome + NSToolbar 桥接 extension (V5.51-7: 已抽到 Views/ContentView+WindowChrome.swift)
