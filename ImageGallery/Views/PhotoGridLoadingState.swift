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
        .padding(Spacing.md)
    }
}
