//
//  ContentView+BatchDialogs.swift
//  ImageGallery
//
//  V5.51-5: 从 ContentView.swift 抽出 batchActionDialogs modifier
//  原位置 ContentView.swift:1744-1812
//  V4.10.0 引入——把 4 个 dialog 打包成 1 个 modifier
//

import SwiftUI

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
                Button(Copy.delete, role: .destructive, action: onConfirmBatchDelete)
                Button(Copy.cancel, role: .cancel) {}
            } message: {
                // V3.6 改：删除走回收站，N 天后才永久清除
                Text(Copy.deletePhotosConfirm(retentionDays: retentionDays))
            }
            // ⌘N 新建文件夹
            .alert(Copy.newFolder, isPresented: showingNewFolder) {
                TextField(Copy.folderNamePlaceholder, text: newFolderName)
                Button(Copy.cancel, role: .cancel) { newFolderName.wrappedValue = "" }
                Button(Copy.create) {
                    onConfirmNewFolder()
                    newFolderName.wrappedValue = ""
                }
            } message: {
                Text(Copy.newFolderPrompt)
            }
            // V3.6.6: 清空回收站二次确认
            .confirmationDialog(
                "确定要清空回收站吗？",
                isPresented: showingEmptyTrash,
                titleVisibility: .visible
            ) {
                Button(Copy.empty, role: .destructive, action: onConfirmEmptyTrash)
                Button(Copy.cancel, role: .cancel) {}
            } message: {
                Text(Copy.emptyRecycleBinConfirm)
            }
            // V3.6.24: 导入时重复检测 dialog
            .confirmationDialog(
                duplicateDialogTitle,
                isPresented: showingDuplicateCheck,
                titleVisibility: .visible
            ) {
                Button(Copy.skipAll, action: onConfirmSkipDuplicates)
                Button(Copy.importAll, role: .destructive, action: onConfirmImportAllDuplicates)
                Button(Copy.cancel, role: .cancel, action: onCancelDuplicateImport)
            } message: {
                Text(Copy.newFolderHint)
            }
    }
}
