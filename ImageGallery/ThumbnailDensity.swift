//
//  ThumbnailDensity.swift
//  ImageGallery
//
//  缩略图密度（Eagle 化工具栏引入）。
//  3 档离散值，替代原来的连续 Slider。
//  底层仍是 CGFloat（保持 PhotoGridView 接口不变）。
//
//  V5.18: 4 档加 .compact 70pt（Photos.app "Months" 视图风格）
//    - 用户在 1 屏想看更多图时切到 .compact
//    - 4x3 12-cell 网格图标暗示密度更高
//    - 4 档比 3 档视觉更多选择但仍能塞进 1 个 popover 段
//

import Foundation

enum ThumbnailDensity: String, CaseIterable, Identifiable {
    case compact  // V5.18: 70pt——4x3 网格密度
    case small
    case medium
    case large

    var id: String { rawValue }

    /// 对应的实际缩略图大小（pt）
    /// V5.16: medium 170→200（行高 200pt 视觉更宽裕，缩略图原值即 200pt）
    /// V5.18: 加 .compact 70pt（Months 视图风格，1 屏看更多图）
    var size: CGFloat {
        switch self {
        case .compact: return 70
        case .small:   return 110
        case .medium:  return 200
        case .large:   return 240
        }
    }

    /// 中文标签
    var label: String {
        switch self {
        case .compact: return "极小"
        case .small:   return "小"
        case .medium:  return "中"
        case .large:   return "大"
        }
    }

    /// 图标：用点阵密度暗示
    /// - 极小 (70pt):  4×3 = 12 个点（密集 = 单格最小）
    /// - 小   (110pt): 3×3 = 9 个点
    /// - 中   (200pt): 2×2 = 4 个点
    /// - 大   (240pt): 1×1 = 单个大方块
    /// V5.18: .compact 加 .fill 后缀——实心方块视觉密度比 outline 强
    ///   4x3.fill vs 3x3 区分更明显，避免"差不多大小"
    var icon: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"
        case .small:   return "square.grid.3x3"
        case .medium:  return "square.grid.2x2"
        case .large:   return "square"
        }
    }

    /// V5.31 NEW: toolbar segment 图标 (4 段离散按钮)——区别于 popover icon
    ///   - 4 段全部 .fill 实心 (popover 是 mix, 区分场景)
    ///   - 4 段宽度差异明显: 4x3 / 3x2 / 2x2 / 1x1 (递增)
    ///   - 单元数递减暗示 cell 变大
    var iconName: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"   // 12 cells visible
        case .small:   return "square.grid.3x2.fill"   // 6 cells
        case .medium:  return "square.grid.2x2.fill"   // 4 cells
        case .large:   return "square.fill"            // 1 cell
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
