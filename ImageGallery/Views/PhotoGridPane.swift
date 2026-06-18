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
    // V5.8: 砍 filterFavorites
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    // V3.6 NEW: 回收站筛选（true = 只显示 trashedAt != nil 的项）
    let filterInTrash: Bool
    // V4.36.x: 工具栏筛选按钮 4 维（与 PhotoGridView 签名一致；透传）
    let selectedFolderIDs: Set<UUID>
    let selectedTagIDs: Set<UUID>
    let selectedShapes: Set<PhotoShape>
    let filterMinRating: Int
    // V3.6.6: 保留时长（透传给 PhotoThumbnailView 显示剩余天数 badge）
    let retentionDays: Int
    let thumbnailSize: CGFloat
    // V5.17: 缩略图布局模式（3 选项）—— 透传到 PhotoGridView.masonryRowsView
    let layoutMode: ThumbnailLayoutMode
    let sortOption: SortOption
    // V5.60-6: 滚动位置 anchor (ContentView.model.scrollAnchorPhotoID 透传)——读 only
    let scrollAnchorPhotoID: String?
    let onVisiblePhotosChange: ([Photo]) -> Void
    let onImport: () -> Void
    let onBatchDelete: () -> Void
    let onClearMultiSelect: () -> Void
    let onDoubleTap: (Photo) -> Void
    // V4.9.0: 清空所有 filter（用于"无搜索结果"等空状态次 CTA）
    let onClearFilters: () -> Void
    let onExportComplete: (Int) -> Void
    // V5.39.6: 透传到 PhotoGridView, 让 Finder 拖入文件触发 ImageImporter
    //   必须放在 exportComplete 之后——SwiftUI call site 顺序约束
    let onDropImport: ([URL]) -> Void
    // V5.39.7: 透传重排回调 (customOrder 拖拽重排后触发, 调 ContentView recomputePhotos)
    let onReorder: () -> Void
    // V5.61-1: 滚动位置变化回调——透传 PhotoGridView.scrollAnchorID 变化到 ContentView 写回 model
    let onScrollAnchorChange: (String) -> Void
    // V6.17.0: 矩形圈选 state 透传 (跟 selection 同路径, gesture 挂在 PhotoGridView 内部)
    let isMarqueeActive: Binding<Bool>
    let marqueeRect: Binding<CGRect?>

    var body: some View {
        PhotoGridView(
            selection: $selection,
            // V6.17.0: 矩形圈选 state 紧跟 selection (init 参数顺序)
            isMarqueeActive: isMarqueeActive,
            marqueeRect: marqueeRect,
            folder: folder,
            tag: tag,
            searchText: searchText,
            // V5.8: 砍 filterFavorites
            filterUnfiled: filterUnfiled,
            filterDuplicates: filterDuplicates,
            filterRecent7Days: filterRecent7Days,
            filterLargeFiles: filterLargeFiles,
            filterInTrash: filterInTrash,
            // V4.36.x: 工具栏筛选 4 维
            selectedFolderIDs: selectedFolderIDs,
            selectedTagIDs: selectedTagIDs,
            selectedShapes: selectedShapes,
            filterMinRating: filterMinRating,
            retentionDays: retentionDays,
            thumbnailSize: thumbnailSize,
            // V5.17: 透传 layoutMode → PhotoGridView.masonryRowsView dispatch
            layoutMode: layoutMode,
            sortOption: sortOption,
            scrollAnchorPhotoID: scrollAnchorPhotoID,  // V5.60-6: 滚动恢复 anchor 透传
            onScrollAnchorChange: onScrollAnchorChange,  // V5.61-1: auto-save 透传
            onVisiblePhotosChange: onVisiblePhotosChange,
            onImport: onImport,
            onBatchDelete: onBatchDelete,
            onClearMultiSelect: onClearMultiSelect,
            onDoubleTap: onDoubleTap,
            onClearFilters: onClearFilters,  // V4.9.0
            onExportComplete: onExportComplete,
            onDropImport: onDropImport,      // V5.39.6 透传
            onReorder: onReorder              // V5.39.7 透传
        )
    }
}
