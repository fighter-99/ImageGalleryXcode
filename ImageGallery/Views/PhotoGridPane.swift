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
//  V3.6.52: 重构选中状态——3 Binding (selectedPhoto/selectedIDs/lastSelectedID) 合并为
//  1 Binding<SelectionState>（与 PhotoGridView 同步）。
//

import SwiftUI

struct PhotoGridPane: View {
    // V3.6.52: 3 Binding → 1 Binding<SelectionState>（与 PhotoGridView 同步）
    @Binding var selection: SelectionState
    let folder: Folder?
    let tag: Tag?
    let searchText: String
    let filterFavorites: Bool
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    // V3.6 NEW: 回收站筛选（true = 只显示 trashedAt != nil 的项）
    let filterInTrash: Bool
    // V3.6.6: 保留时长（透传给 PhotoThumbnailView 显示剩余天数 badge）
    let retentionDays: Int
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
            selection: $selection,
            folder: folder,
            tag: tag,
            searchText: searchText,
            filterFavorites: filterFavorites,
            filterUnfiled: filterUnfiled,
            filterDuplicates: filterDuplicates,
            filterRecent7Days: filterRecent7Days,
            filterLargeFiles: filterLargeFiles,
            filterInTrash: filterInTrash,
            retentionDays: retentionDays,
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
