//
//  JustifiedRowLayout.swift
//  ImageGallery
//
//  V5.38 → V5.39.1: 完全复刻 macOS Photos.app 风格的图片网格布局算法——生产版
//
//  Spec (5 个核心步骤, 来自 user 原始 spec):
//    1. 按顺序累加图片, 计算该行总宽高比之和 (aspectSum)
//    2. 计算当前行理论宽度 = (目标行高 × aspectSum) + (间距 × (图片数-1))
//    3. 当理论宽度 > 容器宽度时, 完成该行 (不加新 cell)
//    4. 计算实际缩放系数 = 容器可用宽度 / 理论宽度
//    5. 该行每张图片:
//       - 实际高度 = 目标行高 × 缩放系数
//       - 实际宽度 = 实际高度 × 图片自身宽高比
//
//  V5.39 改进:
//    - 加 stretchLastRow 参数 (true=末行也填满, false=末行保持 targetRowHeight 左对齐)
//    - 接 MasonryMath.Item (id, width, aspectRatio) 作 input——统一 GridLayout 输入类型
//    - 末行不拉伸时, 即使 theoreticalWidth < availableWidth, 也不上调 actualRowHeight
//    - 输出 [JustifiedRow] 含 rowHeight (actualRowHeight) + 算好的 cell widths——
//      GridLayout 直接桥接到 PhotoGridItem
//
//  V5.39.1 修复: 末行 + stretchLastRow=false 时 cells 不溢出
//    - 原 V5.39 末行保持 targetRowHeight 不变, 但若 cellWidth = targetRowHeight × aspect
//      超过 availableWidth, 就会溢出 (e.g. 1 张 10:1 图, cell 宽 = 2000 > 1000)
//    - V5.36 公式 (rowHeight = (availableWidth - nGaps×spacing) / aspectSum) 天然不溢出
//    - V5.39.1 加 overflow fallback: 末行若 theoreticalWidth > availableWidth,
//      压缩 rowHeight 到 (availableWidth - totalSpacing) / aspectSum, 保持不溢出
//    - 否则保持 targetRowHeight (Photos 行为: 末行左对齐, 不强制填满)
//
//  V5.39.1 跟 V5.36 关系:
//    - V5.36 (已删): rowHeight = (availableWidth - nGaps×spacing) / aspectSum (per-row 算)
//    - V5.39.1: 非末行/末行+stretchLastRow=true/唯一行 → 拉伸填满 (同 V5.36)
//            末行+stretchLastRow=false 且不溢出 → 保持 targetRowHeight (新增)
//            末行+stretchLastRow=false 且溢出 → 压缩到 fit (防溢出, 新增)
//    - V5.39.1 替换 V5.36, 不变量: 任何 row 的 cell 总宽 + spacing ≤ availableWidth
//
//  Why 独立文件 (不放 GridLayout 内):
//    - pure value type + 无 @MainActor + 无 helper method
//    - V5.14 教训——@MainActor struct 内 helper 方法触 test bundle 失败
//    - 镜像 MasonryMath / SelectionState / MultiSelectMath 模式
//

import Foundation
import CoreGraphics

// MARK: - 行 (row)

/// V5.39: 一行 cells, 含算好的实际 cell width/height + 行高
struct JustifiedRow: Equatable, Identifiable {
    let id: UUID
    let items: [MasonryMath.Item]
    let targetRowHeight: CGFloat
    let actualRowHeight: CGFloat
    let spacing: CGFloat
    let theoreticalWidth: CGFloat  // 缩放前的理论宽 (调试用)

    init(items: [MasonryMath.Item], targetRowHeight: CGFloat, actualRowHeight: CGFloat, spacing: CGFloat, theoreticalWidth: CGFloat) {
        self.id = items.first?.id ?? UUID()
        self.items = items
        self.targetRowHeight = targetRowHeight
        self.actualRowHeight = actualRowHeight
        self.spacing = spacing
        self.theoreticalWidth = theoreticalWidth
    }

    /// 含 cell 间距的实际渲染宽度 (供 View 层验证用)
    func renderedWidth() -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.width } + CGFloat(items.count - 1) * spacing
    }
}

// MARK: - 主算法

/// V5.39: Justified Row Layout 算法——完全复刻 macOS Photos.app 风格
enum JustifiedRowLayout {

    /// V5.39: 复刻 macOS Photos.app Library 风格——Justified Row Layout
    /// - Parameters:
    ///   - items: 输入 MasonryMath.Item 数组 (按 sortOption 排好, width 字段忽略——算法用 aspectRatio 重算)
    ///   - targetRowHeight: 用户偏好的行高 (thumbnailSize, 200pt 默认)
    ///   - availableWidth: 容器可用宽 (窗口宽 - sidebar)
    ///   - spacing: cell 间距
    ///   - stretchLastRow: 末行行为——
    ///     true: 末行不满时 scaleFactor > 1, cell 变大填满 (Flickr 风格)
    ///     false: 末行保持 targetRowHeight, 左对齐 (Photos 行为，默认)
    /// - Returns: [JustifiedRow], 每个 row 内 cells 已算好 width/height
    ///
    /// 算法 (按 spec 5 步):
    /// 1. 按顺序累加 item.aspectRatio, 算 aspectSum
    /// 2. theoreticalWidth = target × aspectSum + (n-1) × spacing
    /// 3. 若 theoreticalWidth > availableWidth, finalize 当前行 (不含新 item)
    /// 4. scaleFactor = availableWidth / theoreticalWidth
    /// 5. 每 cell:
    ///    - actualHeight = target × scaleFactor (stretchLastRow=false 且末行: actualHeight = target)
    ///    - actualWidth = actualHeight × item.aspectRatio
    ///
    /// 复杂度: O(n) greedy
    /// Packing 最优性: greedy 给近似最优 (Photos/Google Photos 实际都用 greedy)
    static func packRows(
        items: [MasonryMath.Item],
        targetRowHeight: CGFloat,
        availableWidth: CGFloat,
        spacing: CGFloat,
        stretchLastRow: Bool = false
    ) -> [JustifiedRow] {
        guard availableWidth > 0, targetRowHeight > 0 else { return [] }

        var rows: [JustifiedRow] = []
        var current: [MasonryMath.Item] = []
        var currentAspectSum: CGFloat = 0

        for item in items {
            if current.isEmpty {
                // 第 1 张: 直接加入 (空行无宽度, 无 check)
                current.append(item)
                currentAspectSum = item.aspectRatio
            } else {
                // 试探加入: n+1 张图, 算新 theoreticalWidth
                let newN = current.count + 1
                let newAspectSum = currentAspectSum + item.aspectRatio
                let newTheoreticalWidth = targetRowHeight * newAspectSum
                    + CGFloat(newN - 1) * spacing

                if newTheoreticalWidth <= availableWidth {
                    // 还能 fit, 加入
                    current.append(item)
                    currentAspectSum = newAspectSum
                } else {
                    // 超容器, finalize 当前行 (不含当前 item), 开新行
                    rows.append(finalizeRow(
                        items: current,
                        targetRowHeight: targetRowHeight,
                        availableWidth: availableWidth,
                        spacing: spacing,
                        isLastRow: false,
                        isOnlyRow: false  // 非唯一行 (后面还有)
                    ))
                    current = [item]
                    currentAspectSum = item.aspectRatio
                }
            }
        }
        // 末行 finalize (即使未填满也 finalize)
        if !current.isEmpty {
            let isOnlyRow = rows.isEmpty  // V5.39.1: 唯一行总是拉伸
            rows.append(finalizeRow(
                items: current,
                targetRowHeight: targetRowHeight,
                availableWidth: availableWidth,
                spacing: spacing,
                isLastRow: true,
                isOnlyRow: isOnlyRow,
                stretchLastRow: stretchLastRow
            ))
        }
        return rows
    }

    /// V5.39.1: 内部 helper——finalize 一行, 算 cell 实际尺寸
    ///   - theoreticalWidth = target × aspectSum + (n-1) × spacing
    ///   - scaleFactor = availableWidth / theoreticalWidth
    ///   - actualHeight = target × scaleFactor
    ///   - 每 cell: actualWidth = actualHeight × item.aspectRatio
    ///
    ///   拉伸决策 (V5.39.1 三态):
    ///   - isOnlyRow=true: 唯一行, 总是拉伸填满 (V5.36 行为)
    ///   - 非末行 (isLastRow=false): 总是拉伸填满 (Photos 真版: 完整行必须填满)
    ///   - 末行 + stretchLastRow=true: 拉伸填满 (Flickr 风格)
    ///   - 末行 + stretchLastRow=false: 保持 targetRowHeight, 左对齐
    ///     · 但若 theoreticalWidth > availableWidth (cell 会溢出), 压缩到 fit
    ///     · 这是 V5.39.1 关键修复: 避免 1 张极宽图 (e.g. 10:1) 时 cell 宽超出 availableWidth
    private static func finalizeRow(
        items: [MasonryMath.Item],
        targetRowHeight: CGFloat,
        availableWidth: CGFloat,
        spacing: CGFloat,
        isLastRow: Bool,
        isOnlyRow: Bool,
        stretchLastRow: Bool = false
    ) -> JustifiedRow {
        let n = items.count
        let aspectSum = items.reduce(0.0) { $0 + $1.aspectRatio }
        let totalSpacing = CGFloat(max(0, n - 1)) * spacing
        let theoreticalWidth = targetRowHeight * aspectSum + totalSpacing
        // 唯一行 / 非末行 / 末行+stretch: 拉伸填满
        let isStretched = isOnlyRow || !isLastRow || stretchLastRow
        // 末行+不拉伸: 保持 targetRowHeight, 但 cells 不允许溢出
        let wouldOverflow = !isStretched && theoreticalWidth > availableWidth
        let actualRowHeight: CGFloat
        // V6.58 (audit P1.5): aspectSum <= 0 fallback — 之前除零保护让 scaleFactor=1.0
        //   然后 cellWidth = targetRowHeight * 0 = 0, 整行 cell 不可见
        //   现在 aspectSum <= 0 → 等分 availableWidth (每 cell 一份, 视觉上是空白行)
        if aspectSum <= 0 {
            let perCellWidth = n > 0 ? (availableWidth - totalSpacing) / CGFloat(n) : 0
            return JustifiedRow(
                items: items.map { item in
                    MasonryMath.Item(
                        id: item.id,
                        width: perCellWidth,
                        aspectRatio: perCellWidth / targetRowHeight
                    )
                },
                targetRowHeight: targetRowHeight,
                actualRowHeight: targetRowHeight,
                spacing: spacing,
                theoreticalWidth: theoreticalWidth
            )
        }
        if isStretched || wouldOverflow {
            // 拉伸 (或压缩到 fit) 填满 availableWidth
            let availableWidthForCells = availableWidth - totalSpacing
            let theoreticalImageWidth = targetRowHeight * aspectSum
            let scaleFactor = theoreticalImageWidth > 0 ? availableWidthForCells / theoreticalImageWidth : 1.0
            actualRowHeight = targetRowHeight * scaleFactor
        } else {
            // 保持 targetRowHeight (theoreticalWidth ≤ availableWidth, 不溢出)
            actualRowHeight = targetRowHeight
        }
        let finalizedItems: [MasonryMath.Item] = items.map { item in
            let cellHeight = actualRowHeight
            let cellWidth = cellHeight * item.aspectRatio
            return MasonryMath.Item(
                id: item.id,
                width: cellWidth,
                aspectRatio: item.aspectRatio
            )
        }
        return JustifiedRow(
            items: finalizedItems,
            targetRowHeight: targetRowHeight,
            actualRowHeight: actualRowHeight,
            spacing: spacing,
            theoreticalWidth: theoreticalWidth
        )
    }
}
