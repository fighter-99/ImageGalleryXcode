//
//  ThumbnailLayoutMode.swift
//  ImageGallery
//
//  V5.17 → V5.39.5: 缩略图布局模式——2 选项
//  - .square: uniform square cells（V5.16.1，Photos.app "图库"）—— MasonryMath.groupIntoRows
//  - .masonry: justified masonry（V5.39，targetRowHeight × scaleFactor）—— 末行保持 targetRowHeight
//
//  镜像 AppearanceMode.swift pattern（Int-backed enum + displayName + icon
//    + 派生计算属性 + defaultValue）
//
//  V5.39.5: 删 .masonryStretch case——用户反馈"满行"模式视觉上不如"按比例"自然
//    - .masonry 末行保持 targetRowHeight (左对齐) 是 Photos.app "Days" 视图风格
//    - .masonryStretch 末行拉伸填满是 Flickr/500px 风格
//    - 留 2 选项 (.square / .masonry), 与 macOS Photos Library/Days 二元切换一致
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

    /// V5.34 默认：.square——回到 Photos.app Library 真版
    ///   - Photos.app Library 实际是: 1:1 等大 cell + image 中心裁切
    ///   - 每行每列 cell 中心完美对齐 (正方形 grid)
    ///   - portrait 3:4 中心裁切: 保留主体居中, 上下被裁
    ///   - landscape 16:9 中心裁切: 保留主体居中, 左右被裁
    ///   - 1:1 square 显示完整
    /// V5.39.5 仍保留 .square 默认——和 macOS Photos.app Library 视图一致
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
