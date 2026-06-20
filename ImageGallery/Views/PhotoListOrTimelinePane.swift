//
//  PhotoListOrTimelinePane.swift
//  ImageGallery
//
//  V5.60-3: 合并 PhotoListPane + PhotoTimelinePane
//    两者之前字段 100% 镜像 (15 字段行号一一对应)——唯一差异是 body 转发的目标 View
//    (PhotoListView vs PhotoTimelineView)
//    新增 kind: PaneKind enum 决定转发目标——1 个 file 替代 2 个
//    节省 88 行 (44+44 → 33)
//
//  与 PhotoGridPane 区别: Grid 27 字段差异过大, 保留独立
//

import SwiftUI

/// V5.60-3: 列表 vs 时间线 mode——决定 Pane 转发到哪个具体 View
enum PhotoListOrTimelineKind {
    case list
    case timeline

    var displayName: String {
        switch self {
        case .list:     return Copy.layoutModeList
        case .timeline: return Copy.viewModeTimeline
        }
    }
}

struct PhotoListOrTimelinePane: View {
    @Binding var selection: SelectionState
    let folder: Folder?
    let tag: Tag?
    let searchText: String
    // V5.8: 砍 filterFavorites
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    let filterInTrash: Bool
    // V4.36.x: 工具栏筛选按钮 4 维 (签名一致; 本视图不实际用, photos 已由父视图预 filter)
    let selectedFolderIDs: Set<UUID>
    let selectedTagIDs: Set<UUID>
    let selectedShapes: Set<PhotoShape>
    let filterMinRating: Int
    let sortOption: SortOption
    let photos: [Photo]  // V4.36.6: 父视图预 filter 好的 photos (PhotoStats.filtered 算出)
    let kind: PhotoListOrTimelineKind  // V5.60-3: 决定转发目标 (list vs timeline)
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        // V5.60-3: kind 路由到具体 view——1 个 Pane 替代之前的 2 个
        switch kind {
        case .list:
            PhotoListView(
                photos: photos,
                selection: selection,
                onTap: onTap,
                onDoubleTap: onDoubleTap
            )
        case .timeline:
            PhotoTimelineView(
                photos: photos,
                selection: selection,
                onTap: onTap,
                onDoubleTap: onDoubleTap
            )
        }
    }
}
