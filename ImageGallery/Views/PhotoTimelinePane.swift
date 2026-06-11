//
//  PhotoTimelinePane.swift
//  ImageGallery
//
//  V4.36.6: 中间列的时间线模式包装——与 PhotoGridPane/PhotoListPane 平级
//    之前 3 视图模式只有 grid 实现, 切换 list/timeline 不生效
//    现在 3 视图 (grid/list/timeline) 都有 Pane 包装, ContentView.gridPane 用 viewMode switch
//
//  Pane 概念: 中间列的"列"包装, 转发参数给具体 view, 不渲染额外内容
//  与 PhotoGridPane 区别: 调用 PhotoTimelineView(时间线) 而非 PhotoGridView(网格)
//

import SwiftUI

struct PhotoTimelinePane: View {
    @Binding var selection: SelectionState
    let folder: Folder?
    let tag: Tag?
    let searchText: String
    let filterFavorites: Bool
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    let filterInTrash: Bool
    // V4.36.x: 工具栏筛选按钮 4 维（签名一致；本视图不实际用，photos 已由父视图预 filter）
    let selectedFolderIDs: Set<UUID>
    let selectedTagIDs: Set<UUID>
    let selectedShapes: Set<PhotoShape>
    let filterMinRating: Int
    let sortOption: SortOption
    let photos: [Photo]  // V4.36.6: 父视图预 filter 好的 photos (PhotoStats.filtered 算出)
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        PhotoTimelineView(
            photos: photos,
            selection: selection,
            onTap: onTap,
            onDoubleTap: onDoubleTap
        )
    }
}
