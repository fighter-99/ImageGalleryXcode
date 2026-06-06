//
//  PhotoGridPane.swift
//  ImageGallery
//
//  三列布局的中间列：图片网格。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  这个 Pane 是"中间列"的概念包装，本身不渲染额外内容，
//  直接转发参数给 PhotoGridView。提取出来是为了让 ContentView
//  的"列布局"职责更清晰（侧栏/网格/详情三列各占一文件）。
//

import SwiftUI

struct PhotoGridPane: View {
    @Binding var selectedPhoto: Photo?
    @Binding var selectedIDs: Set<UUID>
    @Binding var lastSelectedID: UUID?
    let folder: Folder?
    let tag: Tag?
    let searchText: String
    let filterFavorites: Bool
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    let thumbnailSize: CGFloat
    let sortOption: SortOption
    let onVisiblePhotosChange: ([Photo]) -> Void
    let onImport: () -> Void
    let onBatchDelete: () -> Void
    let onClearMultiSelect: () -> Void
    let onDoubleTap: (Photo) -> Void
    let onExportComplete: (Int) -> Void

    var body: some View {
        PhotoGridView(
            selectedPhoto: $selectedPhoto,
            selectedIDs: $selectedIDs,
            lastSelectedID: $lastSelectedID,
            folder: folder,
            tag: tag,
            searchText: searchText,
            filterFavorites: filterFavorites,
            filterUnfiled: filterUnfiled,
            filterDuplicates: filterDuplicates,
            filterRecent7Days: filterRecent7Days,
            filterLargeFiles: filterLargeFiles,
            thumbnailSize: thumbnailSize,
            sortOption: sortOption,
            onVisiblePhotosChange: onVisiblePhotosChange,
            onImport: onImport,
            onBatchDelete: onBatchDelete,
            onClearMultiSelect: onClearMultiSelect,
            onDoubleTap: onDoubleTap,
            onExportComplete: onExportComplete
        )
    }
}
