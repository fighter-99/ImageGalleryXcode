//
//  ThumbnailLayoutMode.swift
//  ImageGallery
//
//  V5.17 → V5.46: 缩略图布局模式——3 选项
//  - .square: uniform square cells（V5.16.1, **iOS Photos.app Library 风格**）—— MasonryMath.groupIntoRows + .fill
//  - .masonry: justified masonry（V5.39, Justified Row 布局）—— 末行保持 targetRowHeight + .fill
//  - .squareFit: uniform square cells（V5.46 NEW, **macOS Photos.app 按比例 真版**）—— MasonryMath.groupIntoRows + .fit
//
//  ⚠️ V5.41 重要认知修正 + V5.46 二次修正:
//    V5.41: 区分 iOS Photos (1:1 方格) vs macOS Photos (justified row)
//    V5.46: macOS Photos 实际不是 justified row——是 **1:1 方格 + .fit letterbox**
//      - 横屏图: image 顶满 cell 宽 (letterbox 上下)
//      - 竖屏图: image 顶满 cell 高 (letterbox 左右)
//      - 每行数量一致 (因为 1:1 方格) + 中心对齐 (因为方格)
//    .masonry (justified row) 仍是有效选项, 但不是 Photos 真版
//    V5.16.1 命名错误 + V5.20 默认决策错把 iOS Photos 行为当 macOS Photos 真版
//    V5.33 (默认 .masonry) → V5.34 (revert 回 .square) 这次的 revert 理由还是错的
//    V5.46 修正后:
//      - .square = iOS Photos.app Library 风格 (1:1 方格 + .fill 裁切)
//      - .masonry = Justified Row (变宽 cell, 适合内容流浏览, 不严格 Photos 真版)
//      - .squareFit = macOS Photos.app 按比例 真版 (1:1 方格 + .fit letterbox, 不裁切)
//
//  镜像 AppearanceMode.swift pattern（Int-backed enum + displayName + icon
//    + 派生计算属性 + defaultValue）
//
//  V5.39.5: 删 .masonryStretch case
//  V5.46: 增 .squareFit case (rawValue 复用 2——之前 .masonryStretch 用过, 已删)
//    - 老用户 storedLayoutModeRaw=2 (曾选 masonryStretch) → V5.46 前 ?? .square 平滑回退
//    - V5.46 后 storedLayoutModeRaw=2 → .squareFit (新模式比 masonryStretch 更接近 rawValue=2 的原始意图: 1:1 方格)
//    - 这意味着 V5.46 后老用户**自动升级**到 .squareFit——比 V5.39.5 平滑回退到 .square 更合理
//

import Foundation
import CoreGraphics

enum ThumbnailLayoutMode: Int, CaseIterable, Identifiable {
    case square = 0
    case masonry = 1
    case squareFit = 2  // V5.46 NEW: macOS Photos.app 按比例 真版 (1:1 方格 + .fit letterbox)

    var id: Int { rawValue }

    /// V5.20 + V5.34 + V5.46 默认：.square——iOS Photos.app Library 风格
    ///   - 1:1 等大 cell + image 中心裁切 (.fill)
    ///   - 每行每列 cell 中心完美对齐 (正方形 grid)
    ///   - portrait 3:4 中心裁切: 保留主体居中, 上下被裁
    ///   - landscape 16:9 中心裁切: 保留主体居中, 左右被裁
    ///   - 1:1 square 显示完整
    /// ⚠️ V5.41 + V5.46 修正：这是 **iOS Photos.app** 风格，不是 macOS Photos.app 按比例
    ///   macOS Photos.app 按比例真版 = .squareFit (V5.46 NEW) (1:1 + .fit letterbox)
    ///   macOS Photos.app Library justified row = .masonry
    ///   V5.16.1 / V5.20 / V5.27 / V5.34 注释都误把 .square 标为 "Photos.app Library 真版"——已统一修正
    static let defaultValue: ThumbnailLayoutMode = .square

    var displayName: String {
        switch self {
        case .square:    return "方格"
        case .masonry:   return "按比例"
        case .squareFit: return "方格 (完整)"
        }
    }

    var icon: String {
        switch self {
        case .square:    return "square.grid.2x2"
        case .masonry:   return "rectangle.split.3x1"
        case .squareFit: return "square.grid.2x2.fill"  // V5.46: .fill 暗示不裁切
        }
    }

    /// V5.39.5 简化 + V5.46 增 .squareFit 分支
    ///   - .square:    uniformWidth = rowHeight (方形 cell, MasonryMath 用, .fill 裁切)
    ///   - .squareFit:  uniformWidth = rowHeight (方形 cell, MasonryMath 用, .fit letterbox)
    ///   - .masonry:   uniformWidth = nil (JustifiedRowLayout 不读此字段, 仍返以保持 API 兼容)
    ///
    /// stretchLastRow 字段已删——所有模式末行都保持 targetRowHeight (左对齐, Photos Days 风格)
    ///
    /// - Parameter rowHeight: 行高 (= thumbnailSize)
    /// - Returns: uniformWidth (nil = 走 aspect-based 宽度, non-nil = 固定宽度)
    func masonryParams(rowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .square:    return rowHeight
        case .squareFit: return rowHeight  // V5.46: 同样方形 cell, 但渲染走 .fit
        case .masonry:   return nil
        }
    }
}
