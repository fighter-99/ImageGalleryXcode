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
    // V6.77.2: 删 9 个 read+set 业务 state proxy — caller 直读 model.X / \$model.X
    //   - selection (Grid, V3.6.52)
    //   - searchText (Grid, V4.36.x)
    //   - thumbnailSize (Grid, V3.5.x)
    //   - viewMode (Core, V3.6.13)
    //   - newFolderName (Grid, V6.28)
    //   - immersivePhoto / immersiveIndex (Grid, V6.28)
    //   - showSidebar / showDetail (Settings, V5.59-2)
    //   inline setter 路径 (10+ 处):
    //     `selection = .empty` → `model.grid.selection = .empty`
    //     `searchText = X` → `model.grid.searchText = X`
    //     `showSidebar.toggle()` → `model.settings.showSidebar.toggle()`
    //   Binding caller 用 Bindable(model.grid).X / Bindable(model.settings).X
    //
    // V3.6.52 注释保留 — 图片选中唯一真相源仍是 model.grid.selection
    // V5.52-3 注释保留 — 22 @State 搬到 ContentViewModel (V6.77 删完最后一个 get/set proxy)

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

    // 拖拽状态
    @State private var isDropTargeted = false

    // 批量移动
    // （showingBatchMoveSheet 已移除：批量移动流程当前在 PhotoGridView 内联实现，
    //   该状态从未被读。如未来要重新走 sheet 流程再加回。）

    // V4.13.0: 撤回 V3.5.18 旧 @State showSettings——⌘, 现在走 Settings scene
    //   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 状态
    // V5.59-2: 删 @AppStorage accentColorID, 内部仅由 model.accentColor (computed) 消费

    // V6.77.0: 删 retentionDays proxy — caller 直读 model.settings.trashRetentionDays

    // V3.6.22: 应用外观（默认跟随系统）
    // V5.59-2: 删 @AppStorage appearanceModeRaw, model.appearanceMode computed 走 model.appearanceMode

    // V3.6 NEW: 启动时清理过期回收站项的"只跑一次"标记
    // ContentView 可能多次出现（开关窗口、切 sidebar），用 flag 避免重复清理
    @State private var hasPurgedExpiredTrash = false

    // V6.22.3 (P2 #10): Onboarding sheet 状态 — 通过 .sheet(isPresented:) 直接读 model.settings.hasSeenOnboarding
    //   V6.67 (Q5 dead code 二次清理): 删 showingOnboarding computed property
    //   之前: 8 行死代码 (private getter + dummy setter), 0 caller since V6.22.3
    //   现在: 直接 model.settings.hasSeenOnboarding in .sheet(isPresented:)

    // V4.11.0: 存储不可写错误（nil = 正常）
    //   onAppear 调 PhotoStorage.verifyStorage()——失败时填错误消息，detail panel 显示错误态
    // V6.77.0: 删 storageErrorMessage proxy — caller 直读 model.storageErrorMessage

    // V4.12.0 删: QuickLookPreviewController (@State) 整段——V5.42 走 ImmersivePhotoView, 不再需要
    // V5.42 替代: showQuickLook() 调 enterImmersiveFromSelection() 走系统 ImmersivePhotoView

    // V6.74.2: 删 titlebarAccessory proxy + syncTitlebarAccessory helper — TitlebarAccessoryController 整文件删
    //   ⓘ 按钮已迁 MainSplitView SwiftUI .toolbar .primaryAction (V6.74.1), 不再需要 AppKit 桥接

    // V6.80: 删 V4.20.0/V4.21.0 rollback 注释块 — 全 codebase 0 处 .glassEffect, 死注释清理
    //   V4.18 试过 .glassEffect(.regular) 在 SidebarView/DetailView 4 处, V4.21 因 macOS 26 单 view
    //   视觉副作用未消除全 rollback. V6.80 保守路径: toolbar 走 .regularMaterial (Apple standard,
    //   macOS 14-25 stable), macOS 26 Liquid Glass .glass 待 V6.81+ 实施 + 截图验收
    //   SidebarView/DetailView 维持 V4.21 rollback 状态 (避免 outline 风险)

    /// V4.12.0 删: currentVisibleURLs (URL 列表)——V5.42 不再走 QLPreviewPanel
    ///   showQuickLook 直接调 enterImmersiveFromSelection, 不需要 URL 列表
    ///   保留 visiblePhotos + fileURL 在 Photo 数据模型, 这里不再展开

    // 当前选中的强调色（从 accentColorID 解析）

    // V6.77.2: 删 toastQueue / toastTask proxy — caller 直读 model.X
    //   后续 V6.78+ 可考虑把 toastTask 也搬到 model (UI 状态管理)

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

    // V6.76: 删 undoManager / layoutMode / sidebarColumnWidth / detailColumnWidth /
//   sidebarDragStartWidth / detailDragStartWidth 6 个 read-only proxy
//   caller 全部直读 model.X (无需 setter 包装)
//   19 个 get/set 业务 state proxy 保留 (跨边界 setter 需要包装, V6.77 再处理)

    // 启动记忆
    //   镜像 AppearanceMode Int-backed pattern
    //   @AppStorage 持久化 + computed 读写 + 透传给 ViewOptionsPopover/PhotoGridPane
    // V5.59-2: 删 @AppStorage storedLayoutModeRaw, layoutMode computed 走 model.layoutMode
    // V6.76: 删 layoutMode / sidebarColumnWidth / detailColumnWidth / sidebarDragStartWidth /
    //   detailDragStartWidth 5 个 read-only proxy — caller 全部直读 model.X (read-only, 0 setter 风险)

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
    var body: some View {
        ZStack {
            mainLayout
            // V6.33.1: Dynamic Type 注入 — 用户选的 fontScale 走 .dynamicTypeSize 环境
            //   只影响用 semantic font 的 view (V6.34 慢慢把 Typography 迁 semantic)
            .environment(\.dynamicTypeSize, model.settings.appFontScale.dynamicTypeSize)
            // V6.74.2: 删 windowChromeAndToolbar modifier 链 — NSToolbar dead code 全清
            //   ContentView 直接挂 .navigationTitle/.navigationSubtitle/.preferredColorScheme 3 个 modifier
            //   原 helper (ContentView+WindowChrome.swift) 整个文件删
            .navigationTitle(model.grid.currentViewTitle)
            .navigationSubtitle(model.grid.currentViewSubtitle)
            .preferredColorScheme(model.appearanceMode.colorScheme)
            // V6.97 P3-1: trackpad 触控板手势 — Pinch 调缩略图大小, Swipe 切 sidebar/沉浸
            //   装在 contentBodyModifiers 之前 — 让 .gesture 在最外层, 整 window 都响应
            //   thumbnailSize 用 Bindable(model.grid) 双向绑定, 滑动后立即反映
            .trackpadGestures(thumbnailSize: Bindable(model.grid).thumbnailSize)
            // V6.97 P3-1: trackpad 4 向滑动 → NotificationCenter 桥接 → model 行为
            //   swipe left/right 切 sidebar, swipe up 进入沉浸, swipe down 退出
            //   跟 .markupRequested / .newFolderRequested 同模式 (AppKit menu 走 NotificationCenter)
            .onReceive(NotificationCenter.default.publisher(for: .trackpadSwipeLeft)) { _ in
                withAnimation(Animations.standard) { model.settings.showSidebar = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackpadSwipeRight)) { _ in
                withAnimation(Animations.standard) { model.settings.showSidebar = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackpadSwipeUp)) { _ in
                // 沉浸模式: 用当前 grid selection 第一张 (跟 ⌘↩ / 双击 Enter 范式一致)
                if let firstPhoto = model.grid.visiblePhotos.first {
                    model.grid.immersivePhoto = firstPhoto
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trackpadSwipeDown)) { _ in
                // 退出沉浸
                model.grid.immersivePhoto = nil
            }
            // V6.100: 拆 contentBodyModifiers 250 行 / 53 参数 → 5 sub-modifier (Views/Lifecycle/)
//   - lifecycleModifiers: appLifecycleHooks + .task + 4 .onChange
//   - keyboardModifiers: gridInputHandling + contentKeyboardShortcuts (12 keyboard shortcut)
//   - dialogModifiers: batchActionDialogs (3 alert + duplicate check) + applySettingsChrome + exposeUndoManager
//   - sheetModifiers: batchRenameSheet + shareSheet + markupSheet + cropSheet + smartFolderSheets
//   - notificationModifiers: 12 .onReceive + shortcutsHandler
//
// 拆出后 ContentView body chain 13 modifier → 8 modifier, 编译推断秒过
// V5.59-2 拆 modifier 解决 type-check timeout precedent (跟本方案同源)
.lifecycleModifiers(
    model: model,
    modelContext: modelContext,
    allPhotos: allPhotos,
    folders: folders,
    allTags: allTags,
    smartFolders: smartFolders,
    sidebarSelection: model.sidebarSelection,
    sortOption: model.grid.sortOption,
    viewModeRaw: settings.viewModeRaw,
    hasPurgedExpiredTrash: $hasPurgedExpiredTrash,
    onRestoreSelection: { model.restoreSelection(model.settings.sidebarSelection) },
    onPurgeExpiredTrashOnStartup: { model.purgeExpiredTrashOnStartup() },
    onCheckStorage: { model.checkStorage() },
    onMigrateFavoriteToRating: { Photo.migrateFavoriteToRating(in: allPhotos, context: modelContext) },
    onSerializeSidebarSelection: { model.serializeSelection($0) },
    onClearSelectionOnFilterChange: { model.grid.clearSelectionOnFilterChange() },
    onSelectionEscape: { model.grid.selection = .empty },
    filterState: model.filterState,
    selection: model.grid.selection
)
.keyboardModifiers(
    canPrev: model.grid.canPrev,
    canNext: model.grid.canNext,
    hasSelection: !model.grid.selection.isEmpty,
    hasSelectedPhoto: model.grid.singleSelectedPhoto != nil,
    // V6.110.1 (Esc double-press bug fix): 透传 immersivePhoto state — 让底层 gridInputHandling
    //   在 immersive 显示时不抢 Esc / ← / → / Space 事件, 全部 bubble 给 ImmersivePhotoView
    //   之前 bug: 第一次 Esc 被 gridInputHandling 抢走 → 清 selection → 删除/快速查看按钮变灰
    //   第二次 Esc 才真 dismiss (用户要按 2 次)
    hasImmersivePhoto: model.grid.immersivePhoto != nil,
    onDelete: { model.grid.handleDelete() },
    onPrev: { model.grid.goPrev() },
    onNext: { model.grid.goNext() },
    onEscape: { model.grid.selection = .empty },
    onSelectAll: { model.grid.selection = model.grid.selection.settingAll(in: model.grid.visiblePhotos) },
    onZoomIn: { model.grid.zoomIn() },
    onZoomOut: { model.grid.zoomOut() },
    onSpace: { model.grid.showQuickLook() },
    onResetZoom: { model.grid.resetThumbnailSize() },
    onExport: { model.grid.batchExport() },
    onReturn: { model.grid.enterImmersiveFromSelection() },
    onImport: { model.importVM.startImport() },
    onNewFolder: { model.grid.newFolderName = ""; model.grid.showingNewFolderAlert = true },
    onResetFilters: { model.grid.resetFilters() },
    onCopy: { model.grid.copyToPasteboard() },
    onToggleSortDirection: { model.toggleSortDirection() },
    onToggleSidebar: { withAnimation(Animations.standard) { model.settings.showSidebar.toggle() } },
    onSetRating: { model.grid.batchSetRating($0) }
)
.dialogModifiers(
    bindableGrid: bindableGrid,
    importVM: model.importVM,
    model: model,
    batchDeleteTitle: model.grid.batchDeleteTitle,
    duplicateDialogTitle: model.grid.duplicateDialogTitle,
    retentionDays: model.settings.trashRetentionDays,
    undoManager: model.undoManager,
    accentColor: model.accentColor,
    onBatchDelete: { model.grid.batchDelete() },
    onCreateFolder: { model.createFolderFromAlert() },
    onEmptyTrash: { model.grid.emptyTrash() },
    onConfirmSkipDuplicates: { model.importVM.confirmSkipDuplicates() },
    onConfirmImportAllDuplicates: { model.importVM.confirmImportAllDuplicates() },
    onCancelDuplicateImport: { model.importVM.cancelDuplicateImport() }
)
.sheetModifiers(
    model: model,
    bindableGrid: bindableGrid,
    selection: model.grid.selection,
    visiblePhotos: model.grid.visiblePhotos,
    showingBatchRename: bindableGrid.showingBatchRenameSheet
)
.notificationModifiers(model: model)
        }
    // V6.96 P1 #2: 拖放 API 统一——.onDrop 升级为 .dropDestination (URL.self)
    //   之前 providers: [NSItemProvider] 要在 handleDrop 里手动 loadDataRepresentation 反序列化
    //   现在 urls: [URL] SwiftUI 直接给已解析的 URL, 跟 SidebarView 的 .dropDestination 同 API
    //   主窗格 isTargeted 状态绑 P1 #3 DropTargetHighlight modifier (folder/trash/window 三种 style)
    .dropDestination(for: URL.self) { urls, _ in
        // V6.97 P2-3: .dropDestination 闭包必须返 Bool — handleDropImport 返 Void 包一层
        //   true = drop 被消费 (SwiftUI 显示 valid drop 光标), false = 不消费 (invalid 光标)
        //   跟 SidebarView folder row 的 .dropDestination 模式一致
        model.importVM.handleDropImport(urls)
        return true
    } isTargeted: { isTargeted in
        isDropTargeted = isTargeted
    }
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
    // V6.74.2: 删 syncTitlebarAccessory helper — TitlebarAccessoryController 整文件删, 无需 AppKit 桥接

    // V5.7: 砍 toggleFavorite()——工具栏 ❤ 收藏按钮已移除
    //   原逻辑：单选切换 / 多选批量反向——通过右键菜单评分 / 筛选 popover 替代

    // V4.8.0: 删 toolbarContent 定义——NSToolbar (AppKit) 接管所有 toolbar items
    // V4.9.1: 删 showViewOptions @State——View Options popover 改用 NSPopover 由 ToolbarController 管
    // V6.74.2: 删 V4.9.1 注释 — NSToolbar / ToolbarController 整文件删, SwiftUI .toolbar 接管所有 toolbar
    //   SwiftUI .toolbar 在 macOS 14+ 是首选实现, 跟 Photos 真版对齐 (.toolbar .primaryAction ⓘ + 9 items)
    //   新 toolbar 配置在 configureNSToolbar(window:) 方法里
    //   （V4.7.1-V4.7.7 7 个 commit 探索 SwiftUI toolbar 限制都失败）

    // 主布局（V3.5.17：拆到 Views/MainLayoutView.swift；V4.0.0 toolbar 迁出到 native .toolbar；V4.8.0 改为 NSToolbar）
    // V4.10.0: 把 3 个区块抽到 private var pane（sidebarPane/gridPane/detailPane）
    //   避免 mainLayout body 内 100+ 行的 PhotoGridPane / DetailPane 闭包列表触发 type-check 超时
    private var mainLayout: some View {
        MainLayoutView(
            pathBar: { pathBarPane },
            split: { mainSplitPane },
            showSidebar: Bindable(model.settings).showSidebar,
            undoManager: model.undoManager,
            toastQueue: model.toastQueue,
            immersivePhoto: Bindable(model.grid).immersivePhoto,
            immersiveIndex: Bindable(model.grid).immersiveIndex,
            visiblePhotos: model.grid.visiblePhotos,
            onImmersiveDismiss: { model.grid.immersivePhoto = nil },
            // V6.21.1 (Phase 1.2): toast close button → 用户主动 dismiss
            //   调 model.scheduleDismissToast() 移除队首 + 触发 next toast 显示
            onToastDismiss: { model.scheduleDismissToast() },
            // V6.111.1: 沉浸式详情抽屉 closure — 让 ImmersivePhotoView 顶部 chrome 显示 ⓘ 按钮
            //   closure 读 model.grid.immersivePhoto, ←/→ 翻页时 drawer 自动跟新
            immersiveDetailContent: immersiveDetailContent
        )
        // V6.74.6: 删 .onChange(of: isBoxSelecting) marquee hint dismiss 逻辑 — hint 整撤掉
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
            // V6.113: 删 showDetail binding — 主页面详情面板完全移除
            //   想看详情: 走 immersive ⓘ drawer (V6.111 实施)
            isDropTargeted: $isDropTargeted,
            isBoxSelecting: $isBoxSelecting,
            onDrop: { providers in model.importVM.handleDrop(providers: providers) },
            toolbarActions: ToolbarActions(
                onImport: { model.importVM.startImport() },
                onExport: { model.grid.batchExport() },
                onDelete: { model.grid.handleDelete() },
                onQuickLook: { model.grid.enterImmersiveFromSelection() },
                onToggleFilter: { model.grid.resetFilters() },
                onToggleSortDirection: { model.toggleSortDirection() }
                // V6.74.5: 删 onToggleDetail 注入 — ⓘ 按钮从 toolbar 撤掉, 详情面板走 ⌘I/⌘⌃D 菜单 Toggle
            ),
            searchText: Bindable(model.grid).searchText,
            sortOption: bindableGrid.sortOption,
            viewMode: Bindable(model).viewMode,
            // V6.79: toolbar slider 绑 settings.thumbnailSize (持久化)
            //   let settings: UserSettings 不是 @Bindable, 不能 $settings.thumbnailSize, 手动 Binding
            //   SettingsView slider 已删 (V6.79.2), toolbar 唯一入口
            thumbnailSize: Binding(
                get: { settings.thumbnailSize },
                set: { settings.thumbnailSize = $0 }
            ),
            filterState: Binding(get: { model.filterState }, set: { model.filterState = $0 }),
            selectionEmpty: Binding(get: { model.grid.selection.selectedIDs.isEmpty }, set: { _ in }),
            selectionSingle: Binding(get: { model.grid.selection.selectedIDs.count == 1 }, set: { _ in }),
            importProgress: Binding(get: {
                guard let p = model.importVM.importProgress else { return 0.0 }
                return Double(p.current) / Double(max(p.total, 1))
            }, set: { _ in }),
            recentSearches: Binding(get: { model.grid.recentSearches }, set: { model.grid.recentSearches = $0 }),
            // V6.74.4: 搜索提交时记录最近搜索 — Photos 范式 (回车 / 失焦)
            onSearchSubmit: { model.grid.recordRecentSearch($0) },
            allFolders: folders,
            allTags: allTags,
            // V6.103.5: 重新传 showSidebar @Binding (跟 @State columnVisibility 双向 onChange 同步)
            //   之前 V6.103.5 试过 @State + 闭包, ContentView 不能访问 MainSplitView 私有 @State → 失败
            //   现在用 @Binding + 双向 onChange 同步 (条件判断避免循环)
            //   ContentView 真相源 (toolbar ⌘\ 改 model.settings.showSidebar) ↔
            //   MainSplitView @State columnVisibility (NS 自己 manage)
            showSidebar: Bindable(model.settings).showSidebar,
            sidebar: { sidebarPane },
            center: { gridPane },
            // V6.115: toolbar .principal 段 library status bar closure — "全部 92张 27.1MB"
            //   之前 NavigationSplitView 系统渲染, V6.113 改 HStack 后系统不渲染
            //   现在用 SidebarStatusBar View 通过 closure 注入, 跟 V6.111 immersiveDetailContent 同 pattern
            //   closure 内部读 model.grid.libraryStats (V6.20 缓存, V6.28 移到 model.grid)
            libraryStatusBar: { [model] in
                AnyView(SidebarStatusBar(libraryStats: model.grid.libraryStats))
            }
            // V6.113: 删 detail: { detailPane } — 主页面详情面板完全移除
        )
        // V6.17.0.2: overlay 搬进 photoGrid — rect 跟 overlay 同 space (photoGrid),
        //   视觉精准跟手 (用户报告 V6.17.0.1 矩形不跟手就是这里)
        // V6.38.2 (Phase 2): SelectionMiniToolbar .overlay(alignment: .top) 移除
        //   之前: 浮在 mainSplitPane 顶层 — 不占 layout, 跟 grid 内容重叠
        //   现在: 嵌到 gridPane 顶部 VStack (line 637 附近), layout shift 自动让 grid 下移
        // V6.74.6: 删 .overlay marquee hint block + 4 个 .animation
        //   圈选 (marquee select) 用户已知, hint 浮层反而干扰 grid 浏览 — 撤掉
        //   .animation value 三处 (allPhotos.isEmpty / isMultiSelect / selection.isEmpty) hint 用过, 删
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
        // V6.71 (取消 ContextualSelectionBar): 删 gridPane 顶部 VStack + 44pt contextual bar
        //   之前: 选中时 grid 顶部滑出 44pt contextual bar (Tag/Move/Rename/Export/Delete)
        //   现在: 主 toolbar move/export/delete items 在 selected 时 enable (V6.66 已加)
        //         Tag 通过右键 cell submenu 触发 (V6.29.3 已加 manageTags)
        //         StatusBar 强化显示 "已选 N 张" (V6.71) — Photos 真版底栏对齐
        //   视觉: 选中 0→1 无 layout shift (grid 不下移), 内容区变大 ~7%
        Group {
            switch model.viewMode {
            case .grid:
                PhotoGridPane(
                    // V6.28: selection 在 grid
                    // V6.28: selection 在 grid
                    selection: bindableGrid.selection,
                    folder: model.grid.currentFolder,
                    tag: model.grid.currentTag,
                    searchText: model.grid.searchText,
                    // V5.8: 砍 filterFavorites
                    filterUnfiled: model.grid.filterUnfiled,
                    filterDuplicates: model.grid.filterDuplicates,
                    filterRecent7Days: model.grid.filterRecent7Days,
                    filterLargeFiles: model.grid.filterLargeFiles,
                    filterInTrash: model.grid.filterInTrash,
                // V4.36.x: 工具栏筛选 4 维
                selectedFolderIDs: model.filterState.folders,
                selectedTagIDs: model.filterState.tags,
                selectedShapes: model.filterState.shapes,
                filterMinRating: model.filterState.minRating,
                retentionDays: model.settings.trashRetentionDays,
                thumbnailSize: model.grid.thumbnailSize,
                // V5.17: 缩略图布局模式 3 选项（方格 / 按比例 / 按比例满行）
                //   透传到 PhotoGridView.masonryRowsView 决定 uniformWidth/stretchLastRow
                layoutMode: model.layoutMode,
                sortOption: model.grid.sortOption,
                // V5.60-6 启动恢复 + V5.61-1 auto-save——PhotoGridView 双向读写 model
                scrollAnchorPhotoID: model.grid.scrollAnchorPhotoID,
                // V4.36.6: visiblePhotos 改 computed property, 此 callback 不再需要
                //   保留参数避免破坏 PhotoGridPane 签名——传 noop
                onVisiblePhotosChange: { _ in },
                onImport: { model.importVM.startImport() },
                onBatchDelete: { model.grid.showingBatchDeleteConfirm = true },
                onClearMultiSelect: { model.grid.selection = .empty },
                // V6.22.1 (P2 #2): 旋转回调 — cell → pane → grid view 透传, 最终调 model.grid.rotateSelected
                //   单 cell 右键 rotate (cell menu) — ContentView 先把 selection 设成单选这张图, 再 rotate
                onRotate: { photo, clockwise in
                    model.grid.selection = model.grid.selection.selectingSingle(photo.id)
                    model.grid.rotateSelected(clockwise: clockwise)
                },
                // V6.94.1 (P0 #3): 标注回调 — 走 NotificationCenter.markupRequested (跟 Edit menu ⌘M 同源)
                //   ContentView 在 .onReceive 监听 → model.grid.showingMarkupSheet = true
                //   MarkupSheet 弹 → 选中 1 张图时启用 (resolvedSingle), 0/多张图走 toast 提示
                onMarkup: {
                    NotificationCenter.default.post(name: .markupRequested, object: nil)
                },
                // V6.97.1 (P0 #5): 裁剪回调 — 走 NotificationCenter.cropRequested (跟 Edit menu ⌘⇧K 同源)
                // V6.97.1.1 (Bug fix C2): onCrop 改 (Photo) -> Void 跟 onRotate 对称
                //   之前 () -> Void 永远弹 resolvedSingle (错的图) — 右键 B 弹 A
                //   现在 (Photo) → ContentView 先 selectSingle(photo.id) 再 post .cropRequested
                //   跟 onRotate 同样: model.grid.selection = selection.selectingSingle(photo.id)
                onCrop: { photo in
                    model.grid.selection = model.grid.selection.selectingSingle(photo.id)
                    NotificationCenter.default.post(name: .cropRequested, object: nil)
                },
                // V6.97.1.1 (Bug fix C3): isSingle — 单选 gate, 透传到 cell context menu
                //   判定 model.grid.selection.selectedIDs.count == 1 → cell "裁剪..." button 启用
                //   多选或 0 选 → cell "裁剪..." button disable (跟 onMarkup 同样 gate)
                isSingle: model.grid.selection.selectedIDs.count == 1,
                onDoubleTap: { handlePhotoDoubleTap($0) },
                onClearFilters: { model.grid.resetFilters() },
                onExportComplete: { count in
                    model.showToast(Copy.exported(count), type: .success)
                },
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
            // V6.114: list 不实际用 thumbnailSize/layoutMode 等 grid layout 参, 但 SwiftUI Group switch
            //   推断要求所有 branch 类型一致, 必须传占位 props (no-op)
            PhotoListOrTimelinePane(
                selection: bindableGrid.selection,
                folder: model.grid.currentFolder,
                tag: model.grid.currentTag,
                searchText: model.grid.searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: model.grid.filterUnfiled,
                filterDuplicates: model.grid.filterDuplicates,
                filterRecent7Days: model.grid.filterRecent7Days,
                filterLargeFiles: model.grid.filterLargeFiles,
                filterInTrash: model.grid.filterInTrash,
                // V4.36.x: 工具栏筛选 4 维（签名一致；本视图不实际用）
                selectedFolderIDs: model.filterState.folders,
                selectedTagIDs: model.filterState.tags,
                selectedShapes: model.filterState.shapes,
                filterMinRating: model.filterState.minRating,
                sortOption: model.grid.sortOption,
                photos: model.grid.visiblePhotos,
                kind: .list,
                onTap: { model.grid.handleTap($0) },
                onDoubleTap: { handlePhotoDoubleTap($0) },
                // V6.114: list 不实际用这些 grid layout 参, 传占位让 SwiftUI Group switch 推断过
                thumbnailSize: model.grid.thumbnailSize,
                layoutMode: model.layoutMode,
                folders: folders,
                allTags: allTags,
                retentionDays: model.settings.trashRetentionDays,
                onRotate: { _, _ in },
                onMarkup: {},
                onCrop: { _ in }
            )
        case .timeline:
            PhotoListOrTimelinePane(
                selection: bindableGrid.selection,
                folder: model.grid.currentFolder,
                tag: model.grid.currentTag,
                searchText: model.grid.searchText,
                // V5.8: 砍 filterFavorites
                filterUnfiled: model.grid.filterUnfiled,
                filterDuplicates: model.grid.filterDuplicates,
                filterRecent7Days: model.grid.filterRecent7Days,
                filterLargeFiles: model.grid.filterLargeFiles,
                filterInTrash: model.grid.filterInTrash,
                // V4.36.x: 工具栏筛选 4 维（签名一致；本视图不实际用）
                selectedFolderIDs: model.filterState.folders,
                selectedTagIDs: model.filterState.tags,
                selectedShapes: model.filterState.shapes,
                filterMinRating: model.filterState.minRating,
                sortOption: model.grid.sortOption,
                photos: model.grid.visiblePhotos,
                kind: .timeline,
                onTap: { model.grid.handleTap($0) },
                onDoubleTap: { handlePhotoDoubleTap($0) },
                // V6.114: timeline 复用 grid layout — 缩略图大小跟 thumbnailSize slider 联动
                thumbnailSize: model.grid.thumbnailSize,
                layoutMode: model.layoutMode,
                folders: folders,
                allTags: allTags,
                retentionDays: model.settings.trashRetentionDays,
                onRotate: { photo, clockwise in
                    model.grid.selection = model.grid.selection.selectingSingle(photo.id)
                    model.grid.rotateSelected(clockwise: clockwise)
                },
                onMarkup: { NotificationCenter.default.post(name: .markupRequested, object: nil) },
                onCrop: { photo in
                    model.grid.selection = model.grid.selection.selectingSingle(photo.id)
                    NotificationCenter.default.post(name: .cropRequested, object: nil)
                }
            )
            }
        }
        // V6.31.1: view mode 切换过渡 — crossfade + scale 0.95→1 (Photos.app 范式)
        //   .transition 只在 view 出现/消失时触发, 配合 .animation(value: viewMode) 让 SwiftUI 跑 transition
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(Animations.standard, value: model.viewMode)
    }

    // V6.113: 删 detailPane private var — 主页面详情面板完全移除
    //   makeDetailPane(for:hideBigImage:) factory 仍保留, 给 immersiveDetailContent 用

    /// V6.111.1: DetailPane 工厂方法 — grid 主视图 + immersive 详情抽屉共用
    ///   photo 传 nil 时走 .empty branch (DetailPane 内部), 跟之前 detailPane 行为一致
    ///   photo 传具体值时走 .photo-{id} branch, immersive drawer 用此保持显示当前 photo
    ///   singleSelectedPhoto / immersivePhoto 都是 SwiftData @Model, 值类型 capture 安全
    ///   V6.111.4: hideBigImage 参数 — true 时 drawer 隐藏大图 (避免跟左侧 immersive 大图重复)
    private func makeDetailPane(for photo: Photo?, hideBigImage: Bool = false) -> DetailPane {
        DetailPane(
            // V6.28: grid 业务走 model.grid
            // V6.111.1: photo 参数 — 让 caller 决定显示哪个 photo (singleSelectedPhoto / immersivePhoto)
            singleSelectedPhoto: photo ?? model.grid.singleSelectedPhoto,
            isMultiSelect: model.grid.isMultiSelect,
            // V3.6.52: 用 model.grid.selection.selectedIDs.count 替直接字段
            count: model.grid.filterInTrash ? model.grid.trashedCount : (model.grid.filterInDuplicates ? model.grid.duplicatePurgeableCount : model.grid.selection.selectedIDs.count),
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
            onBatchDelete: { model.grid.showingBatchDeleteConfirm = true },
            // V3.6.52: 单字段 assignment 替 2 字段 pair
            onClearSelection: { model.grid.selection = .empty },
            // V3.6 NEW: 回收站模式
            sidebarSelection: model.sidebarSelection,
            retentionDays: model.settings.trashRetentionDays,
            onTrashRestore: { model.grid.restoreSelectedFromTrash() },
            onTrashPermanentDelete: { model.grid.permanentDeleteSelected() },
            // V3.6.6: 改弹二次确认（不再直接调 emptyTrash）
            onEmptyTrash: { model.grid.showingEmptyTrashConfirm = true },
            // V4.9.0: 回收站空时切回"全部"视图
            onExitTrash: { model.sidebarSelection = .all },
            // V3.6.15: 重复图清理（一键保留每组最新）
            onKeepNewestPerDuplicateGroup: { model.grid.keepNewestPerDuplicateGroup() },
            // V4.11.0: 存储不可写错误（nil = OK）
            storageError: model.storageErrorMessage,
            onRetryStorage: { model.checkStorage() },
            // V6.08: 详情面板错误回调 (rename 失败等) — show toast
            onError: { model.showToast($0, type: .error) },
            // V6.111.4: immersive drawer 模式隐藏 bigImageCard (避免跟左侧大图重复)
            //   grid 主视图 detail pane 不传 (默认 false) — 保留 V4.x 大图 60% + 元数据 40% 行为
            hideBigImage: hideBigImage
        )
    }

    /// V6.111.1: 沉浸式详情抽屉 closure — closure 内部读 model.grid.immersivePhoto
    ///   这样 ←/→ 翻页时 drawer 自动跟新 (因为 immersivePhoto 跟着 currentIndex 变)
    ///   返回 AnyView 因为 ImmersivePhotoView 接收 (() -> AnyView)? — 不强制 caller 知道具体类型
    ///   V6.111.4: hideBigImage: true 隐藏 drawer 内的缩略图 — 跟左侧 immersive 大图 100% 重复
    ///   Photos.app Sonoma+ 真版: drawer 只显示元数据 (文件名/EXIF/评分/标签/操作)
    private var immersiveDetailContent: () -> AnyView {
        { [model] in
            AnyView(makeDetailPane(for: model.grid.immersivePhoto, hideBigImage: true))
        }
    }


    // V6.39.1: 双击行为 — 读 settings.appDoubleClickAction 决定走 immersive 或 NSWorkspace.open (QuickLook via Preview.app)
    //   默认 .immersive (跟 V6.39.0 之前完全兼容), 可选 .quickLook 让系统 Preview.app 打开
    private func handlePhotoDoubleTap(_ photo: Photo) {
        switch settings.appDoubleClickAction {
        case .immersive:
            model.grid.enterImmersive(photo)
        case .quickLook:
            // V6.39.1: NSWorkspace.open 在系统默认 app (Preview.app) 打开 — 简单可靠
            //   跟 macOS Finder 空格 Quick Look 行为一致 (Finder 用 QLPreviewPanel, app 跨进程时 Preview.app)
            //   关闭 Preview.app 自动回到 app
            NSWorkspace.shared.open(photo.fileURL)
        }
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
