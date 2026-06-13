//
//  GridLayout.swift
//  ImageGallery
//
//  V5.29: 纯 layout 算法——输入 + 布局参数 → [GridRow]
//    镜像 macOS Photos.app "NSCollectionViewLayout 算 frame" 模式
//    - 算法与 view 渲染完全分离
//    - 纯函数, 可独立测试
//    - 不依赖 SwiftUI View / SwiftData context
//
//  Why 独立 struct (不放 PhotoGridView 内部 helper)：
//    V5.14 教训——@MainActor struct 内 helper 方法触 test bundle 失败
//    pure value type + 无 @MainActor + 测试用普通 struct——避开 V5.14 bug
//
//  复用 MasonryMath.groupIntoRows 低阶原语 (V5.16 已有)
//  复用 ThumbnailLayoutMode.masonryParams 模式映射 (V5.17 已有)
//
//  2 个 computeRows 重载：
//    - computeRows(from photos: [Photo]) — 生产用, 调 [PhotoGridItem] 版本
//    - computeRows(from items: [PhotoGridItem]) — 纯函数, 测试不依赖 SwiftData
//

import Foundation
import CoreGraphics

/// 纯 layout 算法——输入 + 布局参数, 输出分组后的 row 列表
struct GridLayout: Equatable {
    let availableWidth: CGFloat
    let rowHeight: CGFloat
    let cellSpacing: CGFloat
    let layoutMode: ThumbnailLayoutMode

    // MARK: - 生产入口 (从 Photo)

    /// 输入照片, 输出分组后的 rows
    func computeRows(from photos: [Photo]) -> [GridRow] {
        let items: [PhotoGridItem] = photos.map { photo in
            PhotoGridItem(
                id: photo.id,
                aspectRatio: Self.aspectRatio(of: photo),
                width: 0  // 占位, 下面覆盖
            )
        }
        return computeRows(from: items)
    }

    // MARK: - 纯函数 (从 PhotoGridItem, 测试用)

    /// 纯函数: 输入 items, 输出 rows
    /// V5.29-3: 测试入口——不依赖 SwiftData, 可独立单测
    func computeRows(from items: [PhotoGridItem]) -> [GridRow] {
        let masonryItems = items.map { item in
            MasonryMath.Item(
                id: item.id,
                width: rowHeight * item.aspectRatio,
                aspectRatio: item.aspectRatio
            )
        }
        let params = layoutMode.masonryParams(rowHeight: rowHeight)
        let masonryRows = MasonryMath.groupIntoRows(
            items: masonryItems,
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            spacing: cellSpacing,
            uniformWidth: params.uniformWidth,
            stretchLastRow: params.stretchLastRow
        )
        // 把 MasonryMath.Row.items 的最终 width 写回 PhotoGridItem.width (含末行拉伸)
        return masonryRows.map { row in
            let gridItems: [PhotoGridItem] = row.items.map { mItem in
                PhotoGridItem(
                    id: mItem.id,
                    aspectRatio: mItem.aspectRatio,
                    width: mItem.width
                )
            }
            return GridRow(items: gridItems, rowHeight: rowHeight)
        }
    }

    /// V5.16: 单张照片宽高比 (aspectRatio 为 0 或缺省时 fallback 1.0)
    static func aspectRatio(of photo: Photo) -> CGFloat {
        let h = photo.height
        guard h > 0 else { return 1.0 }
        return CGFloat(photo.width) / CGFloat(h)
    }
}

/// 单行 cell 列表
/// V5.29: Identifiable 走首个 cell id——SwiftUI ForEach 需要稳定 id
struct GridRow: Identifiable, Equatable {
    let id: UUID
    let items: [PhotoGridItem]
    let rowHeight: CGFloat

    init(items: [PhotoGridItem], rowHeight: CGFloat) {
        // 空 row 用 UUID() 兜底 (GridLayout 不会产生空 row, 但留防御)
        self.id = items.first?.id ?? UUID()
        self.items = items
        self.rowHeight = rowHeight
    }

    /// 含 cell 间距的实际渲染宽度
    func renderedWidth(spacing: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.width } + CGFloat(items.count - 1) * spacing
    }
}

/// 单 cell 数据
/// V5.29: id 走 Photo.id (UUID)——view 层用 id 做 photos.first(where:) lookup
///   命名避开 SwiftUI.GridItem (用于 LazyVGrid 冲突)
/// V5.29-3: width 默认 0——测试可直接传 aspectRatio, 算 width 由 GridLayout 接管
struct PhotoGridItem: Identifiable, Equatable {
    let id: UUID
    let aspectRatio: CGFloat
    var width: CGFloat  // 由 GridLayout 算出 (含末行拉伸), 测试可传 0
}
