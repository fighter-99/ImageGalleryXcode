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
        onSyncTitlebarAccessory: @escaping (Bool) -> Void,
        onToggleShowDetail: @escaping (Bool) -> Void,
        onPurgeExpiredTrashOnStartup: @escaping () -> Void,
        onCheckStorage: @escaping () -> Void,
        onMigrateFavoriteToRating: @escaping () -> Void
    ) -> some View {
        self
            .appLifecycleHooks(
                thumbnailSize: model.thumbnailSize,
                sidebarSelection: sidebarSelection,
                sortOption: model.sortOption,
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
                canPrev: model.canPrev,
                canNext: model.canNext,
                hasSelection: !selection.isEmpty,
                onDelete: onDelete,
                onPrev: onPrev,
                onNext: onNext,
                onEscape: onSelectionEscape,
                onSelectAll: onSelectAll,
                onZoomIn: onZoomIn,
                onZoomOut: onZoomOut,
                hasSelectedPhoto: model.singleSelectedPhoto != nil,
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
                showingBatchDelete: bindableModel.showingBatchDeleteConfirm,
                batchDeleteTitle: batchDeleteTitle,
                retentionDays: model.settings.trashRetentionDays,
                onConfirmBatchDelete: onBatchDelete,
                showingNewFolder: bindableModel.showingNewFolderAlert,
                newFolderName: bindableModel.newFolderName,
                onConfirmNewFolder: onCreateFolder,
                showingEmptyTrash: bindableModel.showingEmptyTrashConfirm,
                onConfirmEmptyTrash: onEmptyTrash,
                showingDuplicateCheck: Binding(
                    get: { model.importDuplicateCheck != nil },
                    set: { if !$0 { model.importDuplicateCheck = nil } }
                ),
                duplicateDialogTitle: duplicateDialogTitle,
                onConfirmSkipDuplicates: onConfirmSkipDuplicates,
                onConfirmImportAllDuplicates: onConfirmImportAllDuplicates,
                onCancelDuplicateImport: onCancelDuplicateImport
            )
            .applySettingsChrome(tintColor: accentColor.color)
            .exposeUndoManager(undoManager)
            // P4.2: 批量重命名 sheet + 通知监听
            .batchRenameSheet(
                model: model,
                selection: selection,
                visiblePhotos: visiblePhotos,
                showingBatchRename: bindableModel.showingBatchRenameSheet
            )
            // P4.1.1: 智能文件夹创建 sheet
            //   sheet 入口在 SidebarView (Library section "+" 按钮), 触发 model.showingNewSmartFolderSheet
            //   此处 host sheet — ContentView 是 model @Bindable owner
            .smartFolderCreateSheet(
                model: model,
                showingSheet: bindableModel.showingNewSmartFolderSheet,
                pendingFilter: model.pendingSmartFolderFilter ?? .empty
            )
            // V6.19.0 (P0 #1): 分享 sheet — File 菜单 ⌘⇧E 触发 NSSharingServicePicker
            .shareSheet(model: model)
            // V6.19.5 (P0 #16): File 菜单 ⌘⇧N (新文件夹) + Edit > Speech (开始朗读) 监听
            // V6.20.0 (code audit fix #1): ⌘⇧N 之前调 model.createFolderFromAlert() 是 bug
            //   createFolderFromAlert() 内部 trim 空 name 后早返 (newFolderName 默认 "")
            //   → 用户按 ⌘⇧N 菜单什么都没发生 (silent failure)
            //   修: 跟 ⌘N hidden button / SidebarView "+" 按钮同路径 — 弹 alert dialog
            //   同时清空 model.newFolderName (跟 SidebarView L188 同步, 避免上次 name 残留)
            .onReceive(NotificationCenter.default.publisher(for: .newFolderRequested)) { _ in
                model.newFolderName = ""
                model.showingNewFolderAlert = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .speakRequested)) { _ in
                model.speakSelection()
            }
            .onChange(of: filterState.activeCount) { _, count in
                ToolbarController.shared.filterActiveCount = count
            }
            // V5.62-2: 外部 filterState 变化推送 (如 chip × 删除, ActiveFiltersBar 弹 Menu 删)
            //   若 child popover open, coordinator 调对应子 popover.updateState() 同步视觉
            .onChange(of: filterState) { _, newState in
                ToolbarController.shared.pushFilterStateToOpenChild(newState)
                if !selection.isEmpty {
                    onSelectionEscape()
                }
            }
            .onChange(of: showDetail) { _, newValue in
                onSyncTitlebarAccessory(newValue)
            }
            // V5.60-8: 删 V5.23 的 .onChange(of: selection.hasSelection) { showDetail = hasSelection }
            //   原因: 用户要求"详情面板常驻" (V5.60-1), V5.23 的"选即显/取消即隐" 冲突
            //   Bug 表现: 点缩略图进入 immersive → ESC 退出 → 详情面板消失 (因 hasSelection 在 re-render
            //     瞬间被认为 false, 触发 V5.23 把 showDetail 设为 false)
            //   修法: 删 onChange——showDetail 现在只受 V5.60-1 默认 (true) + 手动 toggle (⌘I/⌘⌃D/titlebar) 控制
            //   selection 仍保留 onChange (如有别处用), 但不再影响 showDetail
            .task {
                model.modelContext = modelContext
                model.allPhotos = allPhotos
                model.folders = folders
                model.allTags = allTags
            }
            .onChange(of: allPhotos) { _, new in model.allPhotos = new }
            .onChange(of: folders) { _, new in model.folders = new }
            .onChange(of: allTags) { _, new in model.allTags = new }
            // P4.1.1: smartFolders 推 model.smartFoldersCache (createSmartFolder 用 max+1 算 order)
            .onChange(of: smartFolders) { _, new in model.smartFoldersCache = new }
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
                        // 直接调 model, 跟 batchMove 一样不通过 closure 包装
                        model.batchRename(template: template)
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
            .sheet(isPresented: bindable(model.sharingURLs != nil)) {
                if let urls = model.sharingURLs, !urls.isEmpty {
                    SharePickerView(urls: urls)
                        .frame(minWidth: 400, minHeight: 300)
                }
            }
            // V6.19.0: File 菜单 ⌘⇧S 通过通知触发 sheet
            //   model.shareSelectedURLs() 拿选中 + 单图 fallback, 无选给 toast 提示
            .onReceive(NotificationCenter.default.publisher(for: .shareRequested)) { _ in
                let urls = model.shareSelectedURLs()
                guard !urls.isEmpty else { return }
                model.sharingURLs = urls
            }
    }

    private func bindable(_ isPresent: Bool) -> Binding<Bool> {
        Binding(
            get: { isPresent },
            set: { _ in }
        )
    }
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
            let picker = NSSharingServicePicker(items: urls)
            // 0.1s 延迟让 sheet 动画完成再弹 picker (跟系统 Photos 行为一致)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let view = self?.view else { return }
                picker.show(relativeTo: NSRect(x: 200, y: 150, width: 1, height: 1), of: view, preferredEdge: .minY)
            }
        }
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
}

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
