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
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    let onDelete: (Photo) -> Void
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(rows) { row in
                PhotoRowView(
                    row: row,
                    cellSpacing: cellSpacing,
                    showDateCaption: showDateCaption,
                    photos: photos,
                    selection: selection,
                    folders: folders,
                    allTags: allTags,
                    retentionDays: retentionDays,
                    onDelete: onDelete,
                    onTap: onTap,
                    onDoubleTap: onDoubleTap
                )
            }
        }
    }
}
