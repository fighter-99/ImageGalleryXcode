//
//  ContentView+Lifecycle.swift
//  ImageGallery
//
//  V5.51-3: 从 ContentView.swift 抽出 appLifecycleHooks modifier
//  原位置 ContentView.swift:1744-1775
//  V4.10.0 引入——把 .onAppear + 6 个 .onChange 打包成 1 个 modifier 避免 type-check 超时
//

import SwiftUI
import SwiftData

// MARK: - V4.10.0: app lifecycle hooks extension
//
// 把 .onAppear + 6 个 .onChange 打包成 1 个语义化 modifier，让 body 链显著缩短。
// 同样的"抽到 extension 避免 type-check 超时"模式参考 applySettingsChrome / syncNSToolbar*。
// V5.59-2: 删 6 个 obsolete 参数 (storedThumbnailSize/storedSortOption/onStoredThumbnailChange/
//   onStoredSortChange/onThumbnailChange/onSortOptionChange)——model.thumbnailSize/model.sortOption
//   已是 computed proxy 绑 settings, 无需手动 AppStorage 镜像
extension View {
    func appLifecycleHooks(
        thumbnailSize: CGFloat,
        sidebarSelection: SidebarSelection?,
        sortOption: SortOption,
        viewModeRaw: String,
        onAppear: @escaping () -> Void,
        onSidebarSelectionChange: @escaping (SidebarSelection?) -> Void
    ) -> some View {
        self
            .onAppear { onAppear() }
            // V3.6.13: viewModeRaw 通过 computed property 自动响应 AppStorage 变化
            .onChange(of: viewModeRaw) { _, _ in }
            .onChange(of: sidebarSelection) { _, new in onSidebarSelectionChange(new) }
    }
}

// MARK: - V5.59-2: contentBodyModifiers 打包剩余 body modifiers 解决 type-check 超时
//
// 把 .appLifecycleHooks + .gridInputHandling + .contentKeyboardShortcuts +
// .batchActionDialogs + .applySettingsChrome + .exposeUndoManager + 4 个 .onChange + .task
// 全部打包成一个 modifier, 让 ContentView.body 主体只剩 2 个 chained call.
//
// 40+ 参数的 modifier 是 type-check 解决的代价 (V5.59-2 改 showDetail 为 computed proxy 后
// body 推断时间超 60s, 拆出后才 5s 内过编译).
//
extension View {
    @MainActor
    func contentBodyModifiers(
        model: ContentViewModel,
        bindableModel: Bindable<ContentViewModel>,
        // V6.28: bindableGrid for grid business binding (showingBatchDeleteConfirm / newFolderName / etc)
        bindableGrid: Bindable<GridViewModel>,
        settings: UserSettings,
        modelContext: ModelContext,
        allPhotos: [Photo],
        folders: [Folder],
        allTags: [Tag],
        // P4.1.1: smartFolders 跟 allPhotos/folders/allTags 同 pattern
        smartFolders: [SmartFolder],
        selection: SelectionState,
        sidebarSelection: SidebarSelection?,
        showSidebar: Bool,
        showDetail: Bool,
        filterState: FilterState,
        visiblePhotos: [Photo],
        batchDeleteTitle: String,
        duplicateDialogTitle: String,
        undoManager: ImageGalleryUndoManager,
        accentColor: AccentColor,
        hasPurgedExpiredTrash: Binding<Bool>,
        showingNewFolderAlert: Binding<Bool>,
        onImport: @escaping () -> Void,
        onNewFolder: @escaping () -> Void,
        onResetFilters: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onToggleSortDirection: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void,
        onSetRating: @escaping (Int) -> Void,
        onDelete: @escaping () -> Void,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        onResetZoom: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onReturn: @escaping () -> Void,
        onSpace: @escaping () -> Void,
        onBatchDelete: @escaping () -> Void,
        onCreateFolder: @escaping () -> Void,
        onEmptyTrash: @escaping () -> Void,
        onConfirmSkipDuplicates: @escaping () -> Void,
        onConfirmImportAllDuplicates: @escaping () -> Void,
        onCancelDuplicateImport: @escaping () -> Void,
        onSelectionEscape: @escaping () -> Void,
        onRestoreSelection: @escaping () -> SidebarSelection?,
        onSerializeSidebarSelection: @escaping (SidebarSelection?) -> String,
        onClearSelectionOnFilterChange: @escaping () -> Void,
        // V6.74.2: 删 onSyncTitlebarAccessory / onToggleShowDetail — ⓘ 按钮走 SwiftUI .toolbar .primaryAction (V6.74.1)
        //   showDetail 现在只受 MainSplitView .primaryAction 按钮 / ⌘I / ⌘⌃D toggle (ImageGalleryApp Toggle menu)
        onPurgeExpiredTrashOnStartup: @escaping () -> Void,
        onCheckStorage: @escaping () -> Void,
        onMigrateFavoriteToRating: @escaping () -> Void
    ) -> some View {
        self
            .appLifecycleHooks(
                // V6.28: thumbnailSize/sortOption 在 model.grid
                thumbnailSize: model.grid.thumbnailSize,
                sidebarSelection: sidebarSelection,
                sortOption: model.grid.sortOption,
                viewModeRaw: settings.viewModeRaw,
                onAppear: {
                    onRestoreSelection()
                    if !hasPurgedExpiredTrash.wrappedValue {
                        hasPurgedExpiredTrash.wrappedValue = true
                        onPurgeExpiredTrashOnStartup()
                    }
                    onCheckStorage()
                    onMigrateFavoriteToRating()
                },
                onSidebarSelectionChange: { new in
                    _ = onSerializeSidebarSelection(new)
                    onClearSelectionOnFilterChange()
                }
            )
            .gridInputHandling(
                // V6.28: canPrev/canNext/singleSelectedPhoto 在 model.grid
                canPrev: model.grid.canPrev,
                canNext: model.grid.canNext,
                hasSelection: !selection.isEmpty,
                onDelete: onDelete,
                onPrev: onPrev,
                onNext: onNext,
                onEscape: onSelectionEscape,
                onSelectAll: onSelectAll,
                onZoomIn: onZoomIn,
                onZoomOut: onZoomOut,
                hasSelectedPhoto: model.grid.singleSelectedPhoto != nil,
                onSpace: onSpace,
                onResetZoom: onResetZoom,
                onExport: onExport,
                onReturn: onReturn
            )
            .contentKeyboardShortcuts(
                onImport: onImport,
                onNewFolder: onNewFolder,
                onResetFilters: onResetFilters,
                onCopy: onCopy,
                onToggleSortDirection: onToggleSortDirection,
                onToggleSidebar: onToggleSidebar,
                onSetRating: onSetRating
            )
            .batchActionDialogs(
                // V6.28: batch delete / new folder / empty trash 都在 model.grid
                showingBatchDelete: bindableGrid.showingBatchDeleteConfirm,
                batchDeleteTitle: batchDeleteTitle,
                retentionDays: model.settings.trashRetentionDays,
                onConfirmBatchDelete: onBatchDelete,
                showingNewFolder: bindableGrid.showingNewFolderAlert,
                newFolderName: bindableGrid.newFolderName,
                onConfirmNewFolder: onCreateFolder,
                showingEmptyTrash: bindableGrid.showingEmptyTrashConfirm,
                onConfirmEmptyTrash: onEmptyTrash,
                showingDuplicateCheck: Binding(
                    get: { model.importVM.importDuplicateCheck != nil },
                    set: { if !$0 { model.importVM.importDuplicateCheck = nil } }
                ),
                duplicateDialogTitle: duplicateDialogTitle,
                onConfirmSkipDuplicates: onConfirmSkipDuplicates,
                onConfirmImportAllDuplicates: onConfirmImportAllDuplicates,
                onCancelDuplicateImport: onCancelDuplicateImport
            )
            .applySettingsChrome(tintColor: accentColor.color)
            .exposeUndoManager(undoManager)
            // P4.2: 批量重命名 sheet + 通知监听 (V6.28: showingBatchRenameSheet 在 grid)
            .batchRenameSheet(
                model: model,
                selection: selection,
                visiblePhotos: visiblePhotos,
                showingBatchRename: bindableGrid.showingBatchRenameSheet
            )
            // V6.97 P2-3: 抽 5 个 sheet/notification modifier 到 .smartFolderAndShareSheets
            //   原因: 原 chain 13+ modifier 导致 Swift type-check 超时 (line 210:17)
            //   拆出后 ContentView body 缩短 ~25 行, 编译推断秒过
            .smartFolderAndShareSheets(
                model: model,
                bindableGrid: bindableGrid
            )
            // V6.39.0: Settings page "清空回收站" button → NotificationCenter → ContentView
            //   跟 .newFolderRequested / .speakRequested 同 pattern (Settings 不持有 model 直接引用)
            .onReceive(NotificationCenter.default.publisher(for: .emptyTrashRequested)) { _ in
                model.grid.emptyTrash()
            }
            // V6.94.1: Markup sheet — 弹 MarkupSheet (NSBezierPath 自绘) — P0 #3 Markup feature
            //   接收 model.grid.showingMarkupSheet, 选中 1 张图时启用, 0/多张图时弹 toast 提示
            .markupSheet(model: model, showingSheet: model.grid.showingMarkupSheet)
            // V6.74.0: View 菜单 ⌘Y / ⌘[ / ⌘] 桥接 — 取代 ToolbarController.shared.onXxx nil closure 死路径
            //   V6.62 注释说 "SwiftUI toolbar 替代 AppKit NSToolbar", 但 menu button 仍调 ToolbarController.shared.onQuickLook?()
            //   onQuickLook 永远 nil (configureToolbar 早返没赋值). 修法跟 .newFolderRequested 同 pattern — NotificationCenter.
            .onReceive(NotificationCenter.default.publisher(for: .quickLookRequested)) { _ in
                model.grid.showQuickLook()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigatePrevRequested)) { _ in
                model.grid.goPrev()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateNextRequested)) { _ in
                model.grid.goNext()
            }
            // V6.94.1: Markup (PencilKit 标注) — Edit menu ⌘M 触发 → 弹 MarkupSheet
            //   P0 #3 Markup feature — 跟 .quickLookRequested 同 pattern (NotificationCenter)
            // V6.96 P0 #7: Edit > Copy (⌘C) — 桥到 model.grid.copyToPasteboard()
            //   原 ToolbarController.shared.onCopySelected?() closure 永远 nil (跟 .markupRequested 同 pattern)
            .onReceive(NotificationCenter.default.publisher(for: .copyRequested)) { _ in
                model.grid.copyToPasteboard()
            }
            // V6.96 P0 #7: View > Actual Size (⌘0) / Zoom In (⌘+) / Zoom Out (⌘-)
            //   缩略图大小通过 thumbnailSize binding 调整 (model.grid.resetThumbnailSize/zoomIn/zoomOut 已存在)
            .onReceive(NotificationCenter.default.publisher(for: .actualSizeRequested)) { _ in
                model.grid.resetThumbnailSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomInRequested)) { _ in
                model.grid.zoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOutRequested)) { _ in
                model.grid.zoomOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .markupRequested)) { _ in
                model.grid.showingMarkupSheet = true
            }
            // V6.97.1: Crop sheet — 弹 CropSheet (NSView 9 handles) — P0 #5 Crop / Aspect feature
            //   跟 markupSheet 完全对称 wiring: 接 showingCropSheet, 选中 1 张图时启用
            .cropSheet(model: model, showingSheet: model.grid.showingCropSheet)
            // V6.97.1: Crop (P0 #5) — Edit menu ⌘⇧K / context menu "裁剪..." 触发 → 弹 CropSheet
            //   跟 .markupRequested 完全同 pattern
            .onReceive(NotificationCenter.default.publisher(for: .cropRequested)) { _ in
                model.grid.showingCropSheet = true
            }
            // V6.74.2: 删 .onChange(of: filterState.activeCount) → ToolbarController.shared.filterActiveCount = count
            //   ToolbarController 整文件删, SwiftUI .toolbar 红圈 badge 直接读 filterState.activeCount (MainSplitView.swift:133)
            // V5.62-2: 外部 filterState 变化推送 (如 chip × 删除, ActiveFiltersBar 弹 Menu 删)
            //   若 child popover open, coordinator 调对应子 popover.updateState() 同步视觉
            .onChange(of: filterState) { _, newState in
                // V6.74.2: 删 ToolbarController.shared.pushFilterStateToOpenChild(newState) — NSToolbar 不存在
                //   SwiftUI .toolbar Filter button popover 直接读 filterState binding (MainSplitView.swift:140), 无需 push
                if !selection.isEmpty {
                    onSelectionEscape()
                }
            }
            // V6.74.2: 删 .onChange(of: showDetail) → onSyncTitlebarAccessory(newValue)
            //   ⓘ 按钮走 SwiftUI .toolbar .primaryAction (V6.74.1), showDetail 变化由 SwiftUI 自动 re-render ⓘ icon
            //   不需要 ContentView 桥接 syncTitlebarAccessory (TitlebarAccessoryController 整文件删)
            // V5.60-8: 删 V5.23 的 .onChange(of: selection.hasSelection) { showDetail = hasSelection }
            //   原因: 用户要求"详情面板常驻" (V5.60-1), V5.23 的"选即显/取消即隐" 冲突
            //   Bug 表现: 点缩略图进入 immersive → ESC 退出 → 详情面板消失 (因 hasSelection 在 re-render
            //     瞬间被认为 false, 触发 V5.23 把 showDetail 设为 false)
            //   修法: 删 onChange——showDetail 现在只受 V5.60-1 默认 (true) + 手动 toggle (⌘I/⌘⌃D/titlebar) 控制
            //   selection 仍保留 onChange (如有别处用), 但不再影响 showDetail
            .task {
                model.modelContext = modelContext
                // V6.28: @Query cache 推 model.grid
                model.grid.allPhotos = allPhotos
                model.grid.folders = folders
                model.grid.allTags = allTags
                // V6.22.0 (P2 #12): Thumbnail warmup — 启动后批量预热最近 50 张
                //   用户进入 grid 时立即看到缩略图 (而不是等懒加载)
                //   .background priority 不抢主线程 + 滚动性能
                //   ModelContainer.fetch 拉最近 50 张 (按 importedAt 降序)
                //   失败 URL (data 损坏 / 文件删) ImageLoader.warmupThumbnails 内部跳过
                await Self.warmupRecentThumbnails(context: modelContext, count: 50)
                // V6.22.11 (XCUITest): launch arg auto-trigger — single launch 测试 fix
                //   之前 V6.22.10: -uitest-import-dir 只在 startImport() 入口检查, 测试需 tap import 按钮
                //   现在: ContentView .task 自动 trigger (onAppear 后 1 次), 测试 launch 后自动 import
                //   prod 完全 noop (无 launch arg 时直接 return)
                let args = ProcessInfo.processInfo.arguments
                guard let idx = args.firstIndex(of: "-uitest-import-dir"),
                      idx + 1 < args.count else { return }
                let dir = args[idx + 1]
                let dirURL = URL(fileURLWithPath: dir)
                let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
                guard let contents = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { return }
                let urls = contents.filter { imageExts.contains($0.pathExtension.lowercased()) }
                guard !urls.isEmpty else { return }
                // V6.22.11: 直接调 importPhotos 跳过 duplicate check dialog (测试不要 dialog)
                //   runImportWithDuplicateCheck 走 async checkDuplicatesAsync 会弹 dialog 阻塞测试
                model.importVM.importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
                model.importVM.importPhotos(urls: urls)
            }
            // V6.28: .onChange 推 model.grid
            .onChange(of: allPhotos) { _, new in model.grid.allPhotos = new }
            .onChange(of: folders) { _, new in model.grid.folders = new }
            .onChange(of: allTags) { _, new in model.grid.allTags = new }
            // P4.1.1: smartFolders 推 model.grid.smartFoldersCache (createSmartFolder 用 max+1 算 order)
            .onChange(of: smartFolders) { _, new in model.grid.smartFoldersCache = new }
    }
}

// MARK: - P4.2: 批量重命名 sheet
//
// Photos.app 范式: 弹 sheet, 模板实时 preview, Apply 调 ContentViewModel.batchRename
// File 菜单 ⌘⇧R 通过 NotificationCenter 触发 (绕过 menu 不能直接拿 SwiftUI state 的限制,
//   跟 V3.5.D .openSettingsRequested 同模式 — memory: V3.5.D 通知方案)
extension View {
    @MainActor
    func batchRenameSheet(
        model: ContentViewModel,
        selection: SelectionState,
        visiblePhotos: [Photo],
        showingBatchRename: Binding<Bool>
    ) -> some View {
        self
            .sheet(isPresented: showingBatchRename) {
                // 实时从 visiblePhotos 解析选中 (跟上一次 selection.selectedPhotos(in: visiblePhotos) 一致)
                let selectedPhotos = visiblePhotos.filter { selection.selectedIDs.contains($0.id) }
                BatchRenameSheet(
                    photos: selectedPhotos,
                    onApply: { template in
                        // 直接调 model.grid, 跟 batchMove 一样不通过 closure 包装
                        model.grid.batchRename(template: template)
                    }
                )
            }
            // P4.2: File 菜单 ⌘⇧R 通过通知触发 sheet
            //   收到通知 → 设 showingBatchRename = true (跟 V3.5.D .openSettingsRequested 同模式)
            .onReceive(NotificationCenter.default.publisher(for: .showBatchRenameSheet)) { _ in
                guard !selection.isEmpty else { return }
                showingBatchRename.wrappedValue = true
            }
    }
}

// MARK: - V6.19.0 (P0 #1): 分享 sheet (NSSharingServicePicker 多图)
//
// Photos.app 范式: File 菜单 ⌘⇧S → 弹 NSSharingServicePicker (AirDrop / Messages / Mail / Add to Photos)
// 单图分享走 cell context menu ShareLink (V6.19.0 加), 不进此 sheet
// 走 NotificationCenter 触发 (跟 P4.2 batchRenameSheet 同模式)
extension View {
    @MainActor
    func shareSheet(model: ContentViewModel) -> some View {
        self
            // V6.20.0 (code audit fix #7): binding setter 在 sheet dismiss 时清空 model.grid.sharingURLs
            //   之前 setter 是 _ in {} → URLs 永不清理 → 第二次 ⌘⇧E 选不同图仍弹老 URLs
            //   同时 fix: viewDidAppear 不再 fire 第二次 picker bug (sheet 重新 present 时 SwiftUI
            //   重新 make NSViewController, viewDidAppear 自然 fire — 之前 URLs 残留时 sheet 不重新 present)
            // V6.28: sharingURLs 在 model.grid
            .sheet(isPresented: bindable(
                model.grid.sharingURLs != nil,
                onDismiss: { model.grid.sharingURLs = nil }
            )) {
                if let urls = model.grid.sharingURLs, !urls.isEmpty {
                    SharePickerView(urls: urls)
                        .frame(minWidth: 400, minHeight: 300)
                }
            }
            // V6.19.0: File 菜单 ⌘⇧S 通过通知触发 sheet
            //   model.grid.shareSelectedURLs() 拿选中 + 单图 fallback, 无选给 toast 提示
            // V6.20.3 (code audit fix #15): debounce 0.3s — 快速连点 ⌘⇧S 不堆叠 sheet
            //   之前每次 onReceive 立即设 sharingURLs + 弹 sheet — 用户狂点会闪烁 sheet UI
            //   现在 model.grid.shouldThrottleShareRequest() 用 instance Date 状态做 throttle
            .onReceive(NotificationCenter.default.publisher(for: .shareRequested)) { _ in
                guard !model.grid.shouldThrottleShareRequest() else { return }
                let urls = model.grid.shareSelectedURLs()
                guard !urls.isEmpty else { return }
                model.grid.sharingURLs = urls
            }
    }

    // V6.94.1: MarkupSheet — P0 #3 Markup feature
    //   弹 MarkupSheet (NSBezierPath 自绘 + 工具栏), Edit menu ⌘M 触发
    //   选中 1 张图时启用 (P0 #3 标注单图模式), 0/多张图弹 toast 提示
    //   跟 shareSheet 同模式 (extension View, .sheet + bindable)
    @MainActor
    func markupSheet(model: ContentViewModel, showingSheet: Bool) -> some View {
        self.sheet(isPresented: bindable(showingSheet, onDismiss: { model.grid.showingMarkupSheet = false })) {
            if let resolved = model.grid.resolvedSingle {
                MarkupSheet(photo: resolved.photo)
            } else {
                // 0 张或多张图选 — 弹空视图, dismiss 后回到 grid
                // (理论上 .onReceive 已 check 选中, 这里兜底)
                EmptyView()
            }
        }
    }

    // V6.97.1: Crop sheet modifier — 跟 markupSheet 完全对称 wiring pattern
    //   接 showingCropSheet, 选中 1 张图时弹 CropSheet, 0/多张走兜底
    func cropSheet(model: ContentViewModel, showingSheet: Bool) -> some View {
        self.sheet(isPresented: bindable(showingSheet, onDismiss: { model.grid.showingCropSheet = false })) {
            if let resolved = model.grid.resolvedSingle {
                CropSheet(photo: resolved.photo)
            } else {
                EmptyView()
            }
        }
    }

    private func bindable(_ isPresent: Bool, onDismiss: @escaping () -> Void = {}) -> Binding<Bool> {
        Binding(
            get: { isPresent },
            set: { newValue in
                if !newValue { onDismiss() }
            }
        )
    }

    /// V6.22.0 (P2 #12): 拉最近 N 张 photo URLs, 触发 ImageLoader.warmupThumbnails 预热
    ///   - .background priority 不抢主线程 (用户感知启动快)
    ///   - ModelContext.fetch @MainActor (SwiftData @Query 类比)
    ///   - count 50: warmup 大概 1-2s, 用户进入 grid 立即看到缩略图
    ///   - 失败 / 无 photo: URL 数组空, warmup 内部 0 task 启动, 安全 noop
    @MainActor
    private static func warmupRecentThumbnails(context: ModelContext?, count: Int) async {
        guard let context else { return }
        let descriptor = FetchDescriptor<Photo>(
            sortBy: [SortDescriptor(\Photo.importedAt, order: .reverse)]
        )
        // V6.22.0: fetch 限 count — 大库 (5k+) 只 fetch 50, 避免 startup latency spike
        var fetch = descriptor
        fetch.fetchLimit = count
        let photos = (try? context.fetch(fetch)) ?? []
        let urls = photos.map { $0.fileURL }
        guard !urls.isEmpty else { return }
        // .background: 最低 priority, 让主线程滚动/响应优先
        await Task(priority: .background) {
            await ImageLoader.warmupThumbnails(urls: urls, maxPixelSize: 200)
        }.value
    }

    /// V6.62 (P4.8): 删 uitestAutoImportIfNeeded (-25 LOC dead code) —
    ///   0 caller since V6.22.11 inline version adopted at .task L245-262
    ///   之前的 standalone func 已被 inline 取代, 保留无意义
}

// V6.19.0 (P0 #1): NSSharingServicePicker SwiftUI wrapper
//   NSSharingServicePicker 是 AppKit-only, 用 NSViewControllerRepresentable 包
//   onAppear 自动调 picker.show() 弹系统 share UI
struct SharePickerView: NSViewControllerRepresentable {
    let urls: [URL]

    func makeNSViewController(context: Context) -> NSViewController {
        let controller = SharePickerController(urls: urls)
        return controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}

    final class SharePickerController: NSViewController {
        let urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            // 弹 NSSharingServicePicker — AirDrop / Messages / Mail / Save / Add to Photos
            //   sheet 容器是 NSView, picker show relativeTo view
            // V6.20.3 (code audit fix #12): picker 升级为 ivar, 保证 ARC 持有直到 user dismiss
            //   之前 picker 是局部 let — closure capture 持有, 但 Apple 文档说 picker 必须 retained
            //   直到 dismissed. ivar 化避免任何边缘 case 下 ARC 早释放
            self.picker = NSSharingServicePicker(items: urls)
            // 0.1s 延迟让 sheet 动画完成再弹 picker (跟系统 Photos 行为一致)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                guard let picker = self.picker else { return }
                picker.show(relativeTo: NSRect(x: 200, y: 150, width: 1, height: 1), of: self.view, preferredEdge: .minY)
                // V6.20.3: picker show 后立即置 nil — show 调用后 NSSharingServicePicker 自己 retain
                //   我们 ivar 不再需要, 释放让 ARC 管生命周期
                self.picker = nil
            }
        }

        private var picker: NSSharingServicePicker?
    }
}

// MARK: - P4.1.1: 智能文件夹创建 sheet
//
// Photos.app "Save as Smart Album" 范式
// 入口: SidebarView Library section "+" 按钮 → onCreateSmartFolder → 设 model.showingNewSmartFolderSheet
// 此处 host sheet — ContentView 是 model @Bindable owner (跟 batchRenameSheet 同模式)
extension View {
    @MainActor
    func smartFolderCreateSheet(
        model: ContentViewModel,
        showingSheet: Binding<Bool>,
        pendingFilter: FilterState
    ) -> some View {
        self
            .sheet(isPresented: showingSheet) {
                SmartFolderCreateSheet(
                    initialFilter: pendingFilter,
                    onSave: { name, iconName, filterState in
                        // 直接调 model, 跟 createFolderFromAlert 范式一致
                        model.createSmartFolder(name: name, iconName: iconName, filterState: filterState)
                    }
                )
            }
    }

    // V6.97 P2-3: 智能文件夹编辑 sheet — 跟 create sheet 同 pattern, 多传 existingSmartFolder
    //   sheet 入口在 SidebarView (smart folder 右键菜单 "编辑筛选条件"), 触发 model.grid.editingSmartFolder
    //   onSave 调 model.updateSmartFolder 走 SwiftData update 而不是 insert
    @MainActor
    func smartFolderEditSheet(
        model: ContentViewModel,
        editingSmartFolder: Binding<SmartFolder?>,
        pendingFilter: FilterState
    ) -> some View {
        self
            .sheet(item: editingSmartFolder) { sf in
                SmartFolderCreateSheet(
                    initialFilter: pendingFilter,
                    onSave: { name, iconName, filterState in
                        model.updateSmartFolder(sf, name: name, iconName: iconName, filterState: filterState)
                    },
                    existingSmartFolder: sf
                )
            }
    }
}

// MARK: - V6.97 P2-3: smartFolderAndShareSheets 打包 5 个 modifier 解决 type-check 超时
//
// 原 ContentView body chain 13+ modifier 包含:
//   .batchRenameSheet / .smartFolderCreateSheet / .smartFolderEditSheet
//   / .shareSheet / .onReceive(.newFolderRequested) / .onReceive(.speakRequested)
//
// Swift 编译器推断 60s 超时。打包成单 modifier 后 chain 缩短 ~6, 秒过
//
// 包含:
//   1. smartFolderCreateSheet — Library section "+" 触发
//   2. smartFolderEditSheet — sidebar smart folder 右键 "编辑筛选条件" 触发
//   3. shareSheet — File 菜单 ⌘⇧E 触发 NSSharingServicePicker
//   4. onReceive(.newFolderRequested) — File 菜单 ⌘⇧N (修了 V6.20.0 silent failure)
//   5. onReceive(.speakRequested) — Edit > Speak 触发
extension View {
    @MainActor
    func smartFolderAndShareSheets(
        model: ContentViewModel,
        bindableGrid: Bindable<GridViewModel>
    ) -> some View {
        self
            .smartFolderCreateSheet(
                model: model,
                showingSheet: bindableGrid.showingNewSmartFolderSheet,
                pendingFilter: model.grid.pendingSmartFolderFilter ?? .empty
            )
            .smartFolderEditSheet(
                model: model,
                editingSmartFolder: bindableGrid.editingSmartFolder,
                pendingFilter: model.grid.pendingSmartFolderEditFilter ?? .empty
            )
            .shareSheet(model: model)
            .onReceive(NotificationCenter.default.publisher(for: .newFolderRequested)) { _ in
                model.grid.newFolderName = ""
                model.grid.showingNewFolderAlert = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .speakRequested)) { _ in
                model.grid.speakSelection()
            }
    }
}

// MARK: - V6.22.3 (P2 #10): Onboarding sheet extension
//
// V6.70 (Onboarding removal): 删 onboardingSheet extension — 新手引导取消
//   之前 15 行 (含 1 个 bindable getter + OnboardingView 调用)
//   现在直接 0 行, 整 extension 删
//   对应 OnboardingView.swift 已删, hasSeenOnboarding 字段下一步删
//   替代: 用户首启动直接看到 PhotoGridEmptyState + 导入 CTA (V6.21.2)

// MARK: - V3.5.18: 设置面板 chrome helper (从 ContentView+SettingsChrome.swift 合并过来)
//
// V6.05: 合并到 ContentView+Lifecycle.swift——co-located with usage (line ~166 .applySettingsChrome)
//   删独立的 ContentView+SettingsChrome.swift 文件
//   之前 V5.51-2 抽出来是为避免 ContentView.swift body 链 type-check 超时
//   现在 ContentView.swift 已经分段 (ContentView+Lifecycle/ToolbarSync/... 6 个文件)
//   单独文件 27 行冗余, 合并到本文件让相关 chrome helper 集中
//
// V4.13.0: 撤回 onOpenSettings + showSettings 参数——⌘, 现在走 Settings scene
//   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 路径
//   简化后只应用强调色（.tint + .environment(\.appAccent)）
extension View {
    func applySettingsChrome(tintColor: Color) -> some View {
        self
            .tint(tintColor)
            .environment(\.appAccent, tintColor)
    }
}
