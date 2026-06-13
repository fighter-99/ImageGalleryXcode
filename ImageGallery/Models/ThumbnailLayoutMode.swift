//
//  ThumbnailLayoutMode.swift
//  ImageGallery
//
//  V5.17: 缩略图布局模式——3 选项对应 MasonryMath 3 模式
//  - .square: uniform square cells（V5.16.1，Photos.app "图库"）
//  - .masonry: justified masonry（V5.16，Photos.app "Days"）—— 末行不满
//  - .masonryStretch: masonry + 末行拉宽（V5.16.2，Flickr 风格）—— 默认
//
//  镜像 AppearanceMode.swift pattern（Int-backed enum + displayName + icon
//    + 派生计算属性 + defaultValue）
//
//  masonryParams(rowHeight:) 映射到 MasonryMath 的 (uniformWidth, stretchLastRow)
//    —— 把 enum 转换逻辑收敛在 enum 本体，PhotoGridView 直接拿结果调 MasonryMath
//

import Foundation
import CoreGraphics

enum ThumbnailLayoutMode: Int, CaseIterable, Identifiable {
    case square = 0
    case masonry = 1
    case masonryStretch = 2

    var id: Int { rawValue }

    /// V5.19 默认：.masonry（Photos.app Days 风格——末行不满不补齐）
    ///   - V5.17 默认 .masonryStretch (Flickr 末行拉满) 被反馈"末行变形"
    ///   - Photos.app Days 视图不加 stretch——末行按原 aspect 渲染
    ///   - 老用户 @AppStorage 有 storedLayoutModeRaw 不会受影响（仅新装/重置生效）
    static let defaultValue: ThumbnailLayoutMode = .masonry

    var displayName: String {
        switch self {
        case .square:         return "方格"
        case .masonry:        return "按比例"
        case .masonryStretch: return "按比例（满行）"
        }
    }

    var icon: String {
        switch self {
        case .square:         return "square.grid.2x2"
        case .masonry:        return "rectangle.split.3x1"
        case .masonryStretch: return "rectangle.split.3x1.fill"
        }
    }

    /// V5.17: 映射到 MasonryMath.groupIntoRows 的两个关键参数
    /// - .square:         uniformWidth = rowHeight（方形 cell）, stretchLastRow = false
    ///   —— 方格本来已填满（或不满也无所谓），拉伸只会让方格变形
    /// - .masonry:        uniformWidth = nil（按 aspect）, stretchLastRow = false
    ///   —— Photos.app "Days" 行为，末行不满保留
    /// - .masonryStretch: uniformWidth = nil（按 aspect）, stretchLastRow = true
    ///   —— Flickr/500px 风格，末行均分多余宽
    ///
    /// - Parameter rowHeight: 行高（= thumbnailSize，与 MasonryMath 一致）
    /// - Returns: (uniformWidth, stretchLastRow) 二元组
    func masonryParams(rowHeight: CGFloat) -> (uniformWidth: CGFloat?, stretchLastRow: Bool) {
        switch self {
        case .square:
            return (uniformWidth: rowHeight, stretchLastRow: false)
        case .masonry:
            return (uniformWidth: nil, stretchLastRow: false)
        case .masonryStretch:
            return (uniformWidth: nil, stretchLastRow: true)
        }
    }
}
