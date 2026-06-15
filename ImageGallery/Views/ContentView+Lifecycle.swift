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
            .onChange(of: filterState.activeCount) { _, count in
                ToolbarController.shared.filterActiveCount = count
            }
            .onChange(of: filterState) { _, _ in
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
    }
}
