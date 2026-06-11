//
//  PhotoShape.swift
//  ImageGallery
//
//  V4.36.x: 形状分类——从 Photo.width/height 派生
//  用于工具栏筛选按钮的「形状」维度（landscape/portrait/square）
//
//  设计：enum + static func（与 PhotoShape / PhotoStats 同样模式）
//  - 无状态、无依赖 → 单元测试零成本
//  - 「等号归 square」对齐 macOS Photos.app 行为
//

import SwiftUI

enum PhotoShape: String, CaseIterable, Identifiable, Hashable {
    case landscape  // width > height
    case portrait   // height > width
    case square     // width == height

    var id: String { rawValue }

    /// 边界判定：等号归 square（macOS Photos.app 行为）
    static func from(width: Int, height: Int) -> PhotoShape {
        if width > height { return .landscape }
        if height > width { return .portrait }
        return .square
    }

    var icon: String {
        switch self {
        case .landscape: return "rectangle"
        case .portrait: return "rectangle.portrait"
        case .square: return "square"
        }
    }

    var label: String {
        switch self {
        case .landscape: return "横图"
        case .portrait: return "竖图"
        case .square: return "方形"
        }
    }
}
