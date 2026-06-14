//
//  GridLayout.swift
//  ImageGallery
//
//  V5.29 → V5.47: 纯 layout 算法——输入 + 布局参数 → [GridRow]
//    镜像 macOS Photos.app "NSCollectionViewLayout 算 frame" 模式
//    - 算法与 view 渲染完全分离
//    - 纯函数, 可独立测试
//    - 不依赖 SwiftUI View / SwiftData context
//
//  Why 独立 struct (不放 PhotoGridView 内部 helper)：
//    V5.14 教训——@MainActor struct 内 helper 方法触 test bundle 失败
//    pure value type + 无 @MainActor + 测试用普通 struct——避开 V5.14 bug
//
//  V5.39 重构 + V5.47 简化：
//    - V5.39: .square 走 MasonryMath.groupIntoRows, .masonry 走 JustifiedRowLayout.packRows
//    - V5.47: 删 .masonry case + computeJustifiedMasonryRows 整段 (dead code)
//      · 用户决定不再保留 justified row 选项
//      · 现在所有模式都走 .square 路径 (1:1 方格 + dynamic cellSize)
//      · .square vs .squareFit 差异在 PhotoThumbnailView 渲染分支 + cell card
//    - JustifiedRowLayout.swift 模型保留 (V5.39 era 算法沉淀)——但 GridLayout dispatcher 不再调
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
    /// V5.36 → V5.39 → V5.39.5: 按 layoutMode 分发到不同算法
    ///   - .square:    V5.35 算法 (cellSize 动态算填满宽, 所有 cell 1:1, .fill 渲染)
    ///   - .squareFit: V5.35 算法 (1:1 cell 同 .square, 但 .fit letterbox 渲染——V5.46 路由同 .square)
    /// V5.39.5: 删 .masonryStretch case——用户删"按比例（满行）"模式
    /// V5.47: 删 .masonry case + computeJustifiedMasonryRows 整段——用户决定不再保留 justified row
    ///   现在所有模式都走 V5.35 算法 (1:1 方格 + dynamic cellSize 填满)
    ///   .square vs .squareFit 差异在 PhotoThumbnailView 渲染分支 (.fill vs .fit) + cell card (.square 有, .squareFit 无)
    func computeRows(from items: [PhotoGridItem]) -> [GridRow] {
        switch layoutMode {
        case .square, .squareFit:
            return computeUniformSquareRows(items: items)
        }
    }

    // MARK: - .square 模式 (V5.35 算法)

    /// V5.35: .square 模式——cellSize 动态算填满 availableWidth
    ///   - 所有 cell cellSize × cellSize (1:1 方形)
    ///   - greedy line break (累计超 availableWidth 时换行)
    ///   - 末行不满时留空 = 窗口色 (Photos 不拉满)
    private func computeUniformSquareRows(items: [PhotoGridItem]) -> [GridRow] {
        let cellSize = SquareLayout.cellSize(
            availableWidth: availableWidth,
            rowHeight: rowHeight,
            cellSpacing: cellSpacing
        )
        let masonryItems = items.map { item in
            MasonryMath.Item(
                id: item.id,
                width: cellSize,
                aspectRatio: item.aspectRatio
            )
        }
        let masonryRows = MasonryMath.groupIntoRows(
            items: masonryItems,
            availableWidth: availableWidth,
            rowHeight: cellSize,
            spacing: cellSpacing,
            uniformWidth: cellSize,
            stretchLastRow: false  // 末行不满时留空, 不拉满
        )
        return masonryRows.map { row in
            let gridItems: [PhotoGridItem] = row.items.map { mItem in
                PhotoGridItem(id: mItem.id, aspectRatio: mItem.aspectRatio, width: mItem.width)
            }
            return GridRow(items: gridItems, rowHeight: cellSize)
        }
    }

    // V5.47: 删 .masonry / .masonryStretch 模式 + computeJustifiedMasonryRows 整段——dead code
    //   JustifiedRowLayout.swift 保留 (V5.39 era 算法沉淀, 注释 + 测试还在)
    //   任何 .masonry 引用都走 .square 路径 (1:1 方格)

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
