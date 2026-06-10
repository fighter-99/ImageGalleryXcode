//
//  ThumbnailDensity.swift
//  ImageGallery
//
//  缩略图密度（Eagle 化工具栏引入）。
//  3 档离散值，替代原来的连续 Slider。
//  底层仍是 CGFloat（保持 PhotoGridView 接口不变）。
//

import Foundation

enum ThumbnailDensity: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// 对应的实际缩略图大小（pt）
    var size: CGFloat {
        switch self {
        case .small:  return 110
        case .medium: return 170
        case .large:  return 240
        }
    }

    /// 中文标签
    var label: String {
        switch self {
        case .small:  return "小"
        case .medium: return "中"
        case .large:  return "大"
        }
    }

    /// 图标：用点阵密度暗示
    /// - 小：3×3 = 9 个点（密集 = 单格小）
    /// - 中：2×2 = 4 个点
    /// - 大：1×1 = 单个大方块
    var icon: String {
        switch self {
        case .small:  return "square.grid.3x3"
        case .medium: return "square.grid.2x2"
        case .large:  return "square"
        }
    }

    /// 把任意 CGFloat 吸附到最近的档位
    static func nearest(to size: CGFloat) -> ThumbnailDensity {
        allCases.min(by: { abs($0.size - size) < abs($1.size - size) }) ?? .medium
    }

    /// V4.0.0.6: ⌘+ 快捷键——返回比当前 size 大的下一档（顶到最大返回 nil）
    static func larger(than size: CGFloat) -> ThumbnailDensity? {
        let current = nearest(to: size)
        let all = allCases
        guard let idx = all.firstIndex(of: current), idx < all.count - 1 else { return nil }
        return all[idx + 1]
    }

    /// V4.0.0.6: ⌘- 快捷键——返回比当前 size 小的下一档（顶到最小返回 nil）
    static func smaller(than size: CGFloat) -> ThumbnailDensity? {
        let current = nearest(to: size)
        let all = allCases
        guard let idx = all.firstIndex(of: current), idx > 0 else { return nil }
        return all[idx - 1]
    }
}
