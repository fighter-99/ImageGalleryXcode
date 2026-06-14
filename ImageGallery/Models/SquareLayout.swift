//
//  SquareLayout.swift
//  ImageGallery
//
//  V5.35: 带回 V5.21 的 .square 模式动态 cell 大小算法
//    - User 反馈 V5.34-1 (固定 200pt cell) 有大量右侧空白, 不像 Photos
//    - Photos.app Library 真版: cell 边长 = (availableWidth - (n-1)*spacing) / n, 严格填满
//    - 所有 cell 一致大小, 中心完美对齐
//    - 末行不满时留空 = 窗口色 (Photos 不拉满)
//
//  V5.21 加, V5.27-1 误判为'Flickr 末行拉满'删除, V5.35 改回
//  V5.35 跟 V5.21 区别: 不带 stretchLastRow (那是 .masonryStretch 模式)
//
//  Why 独立 enum (不放 PhotoGridView 内部 helper)：
//    V5.14 教训——@MainActor struct 内 helper 方法触 test bundle 失败
//    pure value type 在独立 enum + 无 @MainActor + 无 helper method
//

import Foundation
import CoreGraphics

enum SquareLayout {
    /// V5.35: .square 模式 cell 大小计算——填满 availableWidth
    /// - Parameters:
    ///   - availableWidth: 单行可用宽（容器宽 - 边距）
    ///   - rowHeight: 用户偏好的目标 rowHeight (V5.30 默认 200pt)
    ///   - cellSpacing: cell 间距 (V5.28-3 8pt → V5.27-4 8pt, V5.28-3 后 4pt)
    /// - Returns: cell 边长（width = height，1:1 方形）
    ///
    /// 算法：
    /// 1. n = floor((availableWidth + spacing) / (rowHeight + spacing))
    ///    —— 算"按目标 rowHeight 能放几个 cell"
    /// 2. cellWidth = (availableWidth - (n-1) * spacing) / n
    ///    —— 把"可用宽"均分到 n 个 cell
    ///
    /// 例子（availableWidth=1100, rowHeight=200, spacing=4）：
    /// - n = floor((1100+4) / (200+4)) = floor(1104/204) = 5 cell / row
    /// - cellWidth = (1100 - 4*4) / 5 = 1084 / 5 = 216.8pt
    /// - 验证: 5 * 216.8 + 4 * 4 = 1100 ✓ 完美填满
    ///
    /// 例子（availableWidth=800, rowHeight=200, spacing=4）：
    /// - n = floor((800+4) / (200+4)) = floor(804/204) = 3 cell / row
    /// - cellWidth = (800 - 2*4) / 3 = 792 / 3 = 264pt
    /// - 验证: 3 * 264 + 2 * 4 = 800 ✓
    ///
    /// 例子（availableWidth=300, rowHeight=200, spacing=4, 极窄窗口）：
    /// - n = floor((300+4) / (200+4)) = floor(304/204) = 1 cell / row
    /// - cellWidth = (300 - 0) / 1 = 300pt
    /// - 验证: 1 * 300 + 0 * 4 = 300 ✓（窄窗口自适应放大）
    static func cellSize(availableWidth: CGFloat, rowHeight: CGFloat, cellSpacing: CGFloat) -> CGFloat {
        guard availableWidth > 0, rowHeight > 0 else { return rowHeight }
        let cellPlusSpacing = rowHeight + cellSpacing
        // floor((availableWidth + spacing) / (rowHeight + spacing)) = n 个 cell 填满
        let n = max(1, Int(floor((availableWidth + cellSpacing) / cellPlusSpacing)))
        // 把可用宽扣掉 cell 间距后均分到 n 个 cell
        return (availableWidth - CGFloat(n - 1) * cellSpacing) / CGFloat(n)
    }
}
