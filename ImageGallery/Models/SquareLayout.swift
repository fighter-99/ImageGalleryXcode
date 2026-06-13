//
//  SquareLayout.swift
//  ImageGallery
//
//  V5.21: .square 模式 cell 大小计算——填满 availableWidth 保持方形
//    - Photos.app Library 视图风格：每行 cell 严格填满整宽，无 ragged right edge
//    - 老逻辑：cell 宽 = rowHeight 固定（240pt）→ 1100pt 可用宽只放 4 cell，剩 80pt 空
//    - 新逻辑：动态算 n 个 cell 填满，cellWidth = (availableWidth - (n-1)*spacing) / n
//
//  Why 独立 enum（不放 PhotoGridView 内部 helper）：
//    V5.14 教训——@MainActor struct 内 helper 方法（private/static）触发现有
//    test bundle 失败。pure value type 在独立 enum + 无 @MainActor + 无 helper method
//    ——避开 V5.14 bug。镜像 MasonryMath / SelectionState pattern。
//

import Foundation
import CoreGraphics

enum SquareLayout {
    /// V5.21: .square 模式 cell 大小计算
    /// - Parameters:
    ///   - availableWidth: 单行可用宽（容器宽 - 边距）
    ///   - rowHeight: 用户偏好的目标 rowHeight (V5.20 默认 240pt)
    ///   - cellSpacing: cell 间距（V5.19 20pt）
    /// - Returns: cell 边长（width = height，1:1 方形）
    ///
    /// 算法：
    /// 1. n = floor((availableWidth + spacing) / (rowHeight + spacing))
    ///    —— 算"按目标 rowHeight 能放几个 cell"
    /// 2. cellWidth = (availableWidth - (n-1) * spacing) / n
    ///    —— 把"剩余宽"均分到每个 cell
    ///
    /// 例子（availableWidth=1100, rowHeight=240, spacing=20）：
    /// - n = floor(1120/260) = 4
    /// - cellWidth = (1100 - 60) / 4 = 260pt
    /// - 验证：4 * 260 + 3 * 20 = 1100pt ✓ 完美填满
    ///
    /// 例子（availableWidth=800, rowHeight=240, spacing=20）：
    /// - n = floor(820/260) = 3
    /// - cellWidth = (800 - 40) / 3 = 253pt
    /// - 验证：3 * 253 + 2 * 20 = 799pt ≈ 800pt ✓
    ///
    /// 例子（availableWidth=300, rowHeight=240, spacing=20）：
    /// - n = floor(320/260) = 1
    /// - cellWidth = (300 - 0) / 1 = 300pt
    /// - 验证：1 * 300 + 0 * 20 = 300pt ✓（窄窗口自适应放大）
    static func cellSize(availableWidth: CGFloat, rowHeight: CGFloat, cellSpacing: CGFloat) -> CGFloat {
        guard availableWidth > 0, rowHeight > 0 else { return rowHeight }
        let cellPlusSpacing = rowHeight + cellSpacing
        // floor((availableWidth + spacing) / (rowHeight + spacing)) = n 个 cell 填满
        let n = max(1, Int(floor((availableWidth + cellSpacing) / cellPlusSpacing)))
        // 把可用宽扣掉 cell 间距后均分到 n 个 cell
        return (availableWidth - CGFloat(n - 1) * cellSpacing) / CGFloat(n)
    }
}
