//
//  ThumbnailLayoutMode.swift
//  ImageGallery
//
//  V5.17 → V5.41: 缩略图布局模式——2 选项
//  - .square: uniform square cells（V5.16.1, **iOS Photos.app Library 风格**）—— MasonryMath.groupIntoRows
//  - .masonry: justified masonry（V5.39, **macOS Photos.app Days/Library 真版**）—— 末行保持 targetRowHeight
//
//  ⚠️ V5.41 重要认知修正:
//    历史注释（包括 V5.16.1 / V5.20 / V5.27 / V5.34 / V5.39.5）都把 .square 标为 "Photos.app Library 真版"
//    这是错的——macOS Photos.app Library 实际是 **Justified Row 布局**（变宽 cell, 跟 .masonry 对应）
//    1:1 方格是 **iOS Photos.app** 风格，不是 macOS Photos
//    V5.16.1 命名错误 + V5.20 默认决策错把 iOS Photos 行为当 macOS Photos 真版
//    V5.33 (默认 .masonry) → V5.34 (revert 回 .square) 这次的 revert 理由是错的
//    修正后:
//      - .square = iOS Photos.app Library 风格 (1:1 方格 + .fill 裁切)
//      - .masonry = macOS Photos.app Library/Days 真版 (justified row + .fill 裁切)
//
//  镜像 AppearanceMode.swift pattern（Int-backed enum + displayName + icon
//    + 派生计算属性 + defaultValue）
//
//  V5.39.5: 删 .masonryStretch case——用户反馈"满行"模式视觉上不如"按比例"自然
//    - .masonry 末行保持 targetRowHeight (左对齐) 是 macOS Photos.app "Days" 视图风格
//    - .masonryStretch 末行拉伸填满是 Flickr/500px 风格
//    - 留 2 选项 (.square / .masonry), 与 iOS Photos Library / macOS Photos Days 二元切换一致
//    - masonryParams 简化——不再需要 stretchLastRow (现在所有模式 stretchLastRow=false)
//    - rawValue 变化: .square=0 / .masonry=1 (之前 .masonryStretch=2 已删)
//    - 老用户 storedLayoutModeRaw=2 (曾选 masonryStretch) → ThumbnailLayoutMode(rawValue: 2) = nil
//      → ContentView 走 ?? .defaultValue (.square) 平滑回退
//

import Foundation
import CoreGraphics

enum ThumbnailLayoutMode: Int, CaseIterable, Identifiable {
    case square = 0
    case masonry = 1

    var id: Int { rawValue }

    /// V5.20 + V5.34 默认：.square——iOS Photos.app Library 风格 (V5.41 修正认知)
    ///   - 1:1 等大 cell + image 中心裁切 (.fill)
    ///   - 每行每列 cell 中心完美对齐 (正方形 grid)
    ///   - portrait 3:4 中心裁切: 保留主体居中, 上下被裁
    ///   - landscape 16:9 中心裁切: 保留主体居中, 左右被裁
    ///   - 1:1 square 显示完整
    /// ⚠️ V5.41 修正：这是 **iOS Photos.app** 风格，不是 macOS Photos.app Library
    ///   macOS Photos.app Library 实际是 Justified Row 布局（= 我们的 .masonry）
    ///   V5.16.1 / V5.20 / V5.27 / V5.34 注释都误把 .square 标为 "Photos.app Library 真版"——已统一修正
    static let defaultValue: ThumbnailLayoutMode = .square

    var displayName: String {
        switch self {
        case .square:  return "方格"
        case .masonry: return "按比例"
        }
    }

    var icon: String {
        switch self {
        case .square:  return "square.grid.2x2"
        case .masonry: return "rectangle.split.3x1"
        }
    }

    /// V5.39.5 简化: masonryParams 只剩 uniformWidth
    ///   - .square:  uniformWidth = rowHeight (方形 cell, MasonryMath 用)
    ///   - .masonry: uniformWidth = nil (JustifiedRowLayout 不读此字段, 仍返以保持 API 兼容)
    ///
    /// stretchLastRow 字段已删——所有模式末行都保持 targetRowHeight (左对齐, Photos Days 风格)
    ///
    /// - Parameter rowHeight: 行高 (= thumbnailSize)
    /// - Returns: uniformWidth (nil = 走 aspect-based 宽度, non-nil = 固定宽度)
    func masonryParams(rowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .square:  return rowHeight
        case .masonry: return nil
        }
    }
}
