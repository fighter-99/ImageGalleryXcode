//
//  ThumbnailLayoutMode.swift
//  ImageGallery
//
//  V5.17 → V5.47: 缩略图布局模式——2 选项
//  - .square: uniform square cells（V5.16.1, **iOS Photos.app Library 风格**）—— MasonryMath.groupIntoRows + .fill + cell card
//  - .squareFit: uniform square cells（V5.46, **macOS Photos.app 按比例 真版**）—— MasonryMath.groupIntoRows + .fit letterbox + 无 cell card
//
//  ⚠️ V5.41 → V5.46 → V5.47 三次认知修正:
//    V5.41: 区分 iOS Photos (1:1 方格) vs macOS Photos (justified row)
//    V5.46: macOS Photos 实际不是 justified row——是 **1:1 方格 + .fit letterbox**
//    V5.47: 用户观察 macOS Photos 真版行为后, 决定砍 justified row (.masonry) +
//           重新定义 "按比例" = letterbox 模式 (无 cell card)
//    V5.47 修正后:
//      - .square = iOS Photos.app Library 风格 (1:1 方格 + .fill 裁切 + 显式 cell card)
//      - .squareFit (displayName "按比例") = macOS Photos.app 真版 (1:1 方格 + .fit letterbox + 无 cell card)
//
//  镜像 AppearanceMode.swift pattern（Int-backed enum + displayName + icon
//    + 派生计算属性 + defaultValue）
//
//  V5.47 移除的 case:
//  - V5.39.5: 删 .masonryStretch (rawValue=2 被 .squareFit 复用)
//  - V5.47: 删 .masonry (rawValue=1)——用户决定不再保留 justified row 选项
//    - 老用户 storedLayoutModeRaw=1 (曾选 masonry) → ?? .defaultValue (.square) 平滑回退
//    - computeJustifiedMasonryRows 变成 dead code——V5.47-1 一并删 (或保留注释 V5.47+ 复用)
//    - JustifiedRowLayout.swift 模型保留 (V5.39 era 算法沉淀), 但 GridLayout dispatcher 不再调
//

import Foundation
import CoreGraphics

enum ThumbnailLayoutMode: Int, CaseIterable, Identifiable {
    case square = 0
    case squareFit = 2  // V5.46 NEW: macOS Photos.app 按比例 真版 (1:1 方格 + .fit letterbox)
                        // V5.47: rawValue 保持 2 (不重排)——兼容 V5.46 老用户
                        // V5.47: displayName 从 '方格 (完整)' 改成 '按比例' (因为 V5.47 砍了原 .masonry '按比例')

    var id: Int { rawValue }

    /// V5.20 + V5.34 + V5.46 + V5.47 默认：.square——iOS Photos.app Library 风格
    ///   - 1:1 等大 cell + image 中心裁切 (.fill)
    ///   - cell 有显式 Surface.elevated 卡片背景 (区别于 .squareFit 的无 card)
    ///   - 每行每列 cell 中心完美对齐 (正方形 grid)
    ///   - portrait 3:4 中心裁切: 保留主体居中, 上下被裁
    ///   - landscape 16:9 中心裁切: 保留主体居中, 左右被裁
    ///   - 1:1 square 显示完整
    static let defaultValue: ThumbnailLayoutMode = .square

    var displayName: String {
        switch self {
        case .square:    return "方格"
        // V5.47: 原 '方格 (完整)' 改成 '按比例'——用户决定 .squareFit 才是 macOS Photos 真版
        //   之前 .masonry (justified row) 占用了 '按比例' 名字——V5.47 砍 .masonry 后名字空出来
        //   现在 '按比例' 语义更准确: image 按原比例 letterbox 进 1:1 cell
        case .squareFit: return "按比例"
        }
    }

    /// V5.60-2: 微调 icon——用密度差异区分, 之前都是 2x2 仅 .fill 不同
    ///   .square (方格 1:1 居中裁切) → 3x3 (暗示密度高)
    ///   .squareFit (按比例 1:1 letterbox 不裁切) → 2x2 (暗示密度低)
    ///   Photos 风格: 高密度 vs 低密度视觉差异明显
    var icon: String {
        switch self {
        case .square:    return "square.grid.3x3"          // V5.60-2: 2x2 → 3x3 (高密度)
        case .squareFit: return "square.grid.2x2"          // V5.60-2: 2x2.fill → 2x2 (低密度)
        }
    }

    /// V5.39.5 简化 + V5.46 增 .squareFit 分支 + V5.47 删 .masonry 分支
    ///   - .square:    uniformWidth = rowHeight (方形 cell, MasonryMath 用, .fill 裁切)
    ///   - .squareFit: uniformWidth = rowHeight (方形 cell, MasonryMath 用, .fit letterbox, 无 cell card)
    ///
    /// stretchLastRow 字段已删——所有模式末行都保持 targetRowHeight (左对齐, Photos Days 风格)
    ///
    /// - Parameter rowHeight: 行高 (= thumbnailSize)
    /// - Returns: uniformWidth (nil = 走 aspect-based 宽度, non-nil = 固定宽度)
    func masonryParams(rowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .square:    return rowHeight
        case .squareFit: return rowHeight  // V5.46: 同样方形 cell, 但渲染走 .fit (V5.47 无 cell card)
        }
    }
}
