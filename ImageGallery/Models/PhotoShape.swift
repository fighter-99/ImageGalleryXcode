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

enum PhotoShape: String, CaseIterable, Identifiable, Hashable, Codable {
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

    /// V4.45.1: icon 用 .fill 变体——显示实际形状 silhouette (macOS Photos 风格)
    ///   之前 "rectangle" 是空心 outline——用户需想象是横图
    ///   现在 "rectangle.fill" 是实心形状——一眼看出 landscape/portrait/square
    var icon: String {
        switch self {
        case .landscape: return "rectangle.fill"
        case .portrait: return "rectangle.portrait.fill"
        case .square: return "square.fill"
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
