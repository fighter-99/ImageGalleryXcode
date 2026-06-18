//
//  PhotoGridLayoutView.swift
//  ImageGallery
//
//  V5.29: 接收 [GridRow] 渲染 LazyVStack——从 PhotoGridView 拆出
//    镜像 macOS Photos.app "NSCollectionView 渲染 cell" 模式
//    - layout 算法在 GridLayout (model 层)
//    - cell 渲染在 PhotoRowView (单行)
//    - 本 view 是 layout 算法 → cell 渲染的胶水
//
//  V5.16: masonry 装箱 + 渲染多行——平铺/分组布局共用
//  V5.18: showDateCaption 决定 cell 下方是否显示日期 caption
//  V5.27: 砍 computeLayoutParams helper + SquareLayout.cellSize (回归 V5.16.1 行为)
//  V5.29: masonryRowsView 内的 LazyVStack 部分抽到此, 算法部分由 GridLayout.computeRows 接管
//

import SwiftUI

struct PhotoGridLayoutView: View {
    let rows: [GridRow]
    let rowSpacing: CGFloat
    let cellSpacing: CGFloat
    // V5.18: 日期 caption 开关——date grouped 传 true, 平铺传 false
    let showDateCaption: Bool
    let photos: [Photo]
    // V5.39.7: 透传排序 + 重排回调 (customOrder 拖拽重排依赖)
    //   必须放在 photos 之后, selection 之前——SwiftUI call site 顺序约束
    let sortOption: SortOption
    let onReorder: () -> Void
    // V5.46: 透传布局模式 (决定 cell 内 image .fill vs .fit letterbox)
    let layoutMode: ThumbnailLayoutMode
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    let onDelete: (Photo) -> Void
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void
    // V6.22.1 (P2 #2): 旋转回调 — 透传到 PhotoRowView
    let onRotate: (Photo, Bool) -> Void

    var body: some View {
        // V5.39.1: 改用 LazyVStack(spacing: rowSpacing) 直接设行间距
        //   - V5.37 用 .padding(.vertical, rowSpacing/2) 兜底, 但 cell letterbox 透明 (V5.27)
        //     → 行间隙也透明 → 视觉上看不到
        //   - V5.39.1 改用 LazyVStack spacing 直接设, 走 SwiftUI 原生 LazyVStack 行间隙渲染
        //   - cell 内容 (image + cornerRadius) 自带视觉边界, rowSpacing 8pt 足够可见
        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(rows) { row in
                PhotoRowView(
                    row: row,
                    cellSpacing: cellSpacing,
                    showDateCaption: showDateCaption,
                    photos: photos,
                    // V5.39.7: 透传排序 + 重排回调 (customOrder 拖拽重排依赖)
                    //   在 photos 之后, selection 之前——SwiftUI call site 顺序约束
                    sortOption: sortOption,
                    onReorder: onReorder,
                    // V5.46: 透传布局模式
                    layoutMode: layoutMode,
                    selection: selection,
                    folders: folders,
                    allTags: allTags,
                    retentionDays: retentionDays,
                    onDelete: onDelete,
                    onTap: onTap,
                    onDoubleTap: onDoubleTap,
                    // V6.22.1 (P2 #2): 旋转回调透传到 PhotoRowView
                    onRotate: onRotate
                )
            }
        }
    }
}
