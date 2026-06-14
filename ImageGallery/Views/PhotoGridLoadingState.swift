//
//  PhotoGridLoadingState.swift
//  ImageGallery
//
//  V5.29: 加载中 Shimmer 占位 grid——从 PhotoGridView 拆出
//    场景: 导入时 brief 闪烁 (SwiftData 还没返回 photos)
//    复用 V4.4.0 Shimmer modifier
//

import SwiftUI

struct PhotoGridLoadingState: View {
    let thumbnailSize: CGFloat

    /// 12 个 Shimmer 占位 cell (足够填满可见区域)
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: thumbnailSize), spacing: Spacing.xs)]
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Surface.cardBackground)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .modifier(Shimmer(duration: 1.2))
            }
        }
        // V5.31: 删 .padding(Spacing.md)——edge-to-edge 与主 grid 一致
        //   之前主 grid 删了 padding (V5.28-3), loading 还在 → 导入时 loading 切换到 photos
        //   会有 12pt 跳变 (jumping)
        //   现在 loading 和 grid 同样 edge-to-edge, 切换平滑
    }
}
