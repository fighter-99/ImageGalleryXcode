//
//  DialogModifiers.swift
//  ImageGallery
//
//  V6.100: 从 ContentView+Lifecycle.contentBodyModifiers 抽 (line 153-174)
//    batchActionDialogs (3 个 alert: batch delete / new folder / empty trash + duplicate check)
//    + applySettingsChrome (tintColor + appAccent env)
//    + exposeUndoManager
//
//  拆出理由: alert + chrome + undo 都是状态展示层, 不依赖 @Query 推 cache, 独立
//

import SwiftUI

extension View {
    /// V6.100: Dialog modifiers — alert × 3 (batch delete / new folder / empty trash + duplicate check)
    ///   + applySettingsChrome (tint) + exposeUndoManager
    ///   从 ContentView+Lifecycle.contentBodyModifiers 抽 (line 153-174, ~22 行)
    @MainActor
    func dialogModifiers(
        bindableGrid: Bindable<GridViewModel>,
        importVM: ImportViewModel,
        model: ContentViewModel,
        batchDeleteTitle: String,
        duplicateDialogTitle: String,
        retentionDays: Int,
        undoManager: ImageGalleryUndoManager,
        accentColor: AccentColor,
        onBatchDelete: @escaping () -> Void,
        onCreateFolder: @escaping () -> Void,
        onEmptyTrash: @escaping () -> Void,
        onConfirmSkipDuplicates: @escaping () -> Void,
        onConfirmImportAllDuplicates: @escaping () -> Void,
        onCancelDuplicateImport: @escaping () -> Void
    ) -> some View {
        self
            .batchActionDialogs(
                showingBatchDelete: bindableGrid.showingBatchDeleteConfirm,
                batchDeleteTitle: batchDeleteTitle,
                retentionDays: retentionDays,
                onConfirmBatchDelete: onBatchDelete,
                showingNewFolder: bindableGrid.showingNewFolderAlert,
                newFolderName: bindableGrid.newFolderName,
                onConfirmNewFolder: onCreateFolder,
                showingEmptyTrash: bindableGrid.showingEmptyTrashConfirm,
                onConfirmEmptyTrash: onEmptyTrash,
                showingDuplicateCheck: Binding(
                    get: { importVM.importDuplicateCheck != nil },
                    set: { if !$0 { importVM.importDuplicateCheck = nil } }
                ),
                duplicateDialogTitle: duplicateDialogTitle,
                onConfirmSkipDuplicates: onConfirmSkipDuplicates,
                onConfirmImportAllDuplicates: onConfirmImportAllDuplicates,
                onCancelDuplicateImport: onCancelDuplicateImport
            )
            .applySettingsChrome(tintColor: accentColor.color)
            .exposeUndoManager(undoManager)
    }
}