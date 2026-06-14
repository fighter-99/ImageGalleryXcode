//
//  MasonryMath.swift
//  ImageGallery
//
//  V5.16: 主网格 row 装箱算法——Photos.app "Aspect Ratio" 视图风格
//    - 行内 cell 高度统一（rowHeight）
//    - cell 宽度 = rowHeight × photoAspectRatio
//    - 行 reflow：cell 累加宽度超 availableWidth 时开新行
//    - 最后一行不满不补齐（Photos.app 行为）
//
//  Why 独立 enum（不放 PhotoGridView 内部 static func）：
//    V5.14 教训——@MainActor struct 内 helper 方法（private/static）触发现有
//    test bundle 失败。pure value type 在独立 enum + 测试用无 @MainActor
//    struct + 无 helper method——避开 V5.14 bug。
//
//  参考 pattern：MultiSelectMath.swift / SelectionState.swift
//

import Foundation

enum MasonryMath {
    /// 单张照片的装箱尺寸
    struct Item: Equatable {
        let id: UUID          // Photo.id——下游渲染用
        let width: CGFloat   // rowHeight × aspectRatio
        let aspectRatio: CGFloat  // Photo.width / Photo.height（1.0 fallback）
    }

    /// 一行（待渲染为 HStack）
    struct Row: Equatable {
        let items: [Item]
        /// V5.16: 行内 cell 累加宽度（含 spacing）—— 验证 reflow 用
        var totalWidth: CGFloat {
            guard !items.isEmpty else { return 0 }
            // 第 1 个 cell 0 spacing，后续每个 + spacing
            return items.reduce(0) { $0 + $1.width } + CGFloat(items.count - 1) * 0  // spacing 在 main loop 加
        }
        /// 含 cell 间距的实际渲染宽度
        func renderedWidth(spacing: CGFloat) -> CGFloat {
            guard !items.isEmpty else { return 0 }
            return items.reduce(0) { $0 + $1.width } + CGFloat(items.count - 1) * spacing
        }
    }

    /// 主装箱算法
    /// - Parameters:
    ///   - items: 全部待装箱照片（已按 sortOption 排好）
    ///   - availableWidth: 单行可用宽（容器宽 - 边距）
    ///   - rowHeight: 每行固定高
    ///   - spacing: cell 间距
    ///   - uniformWidth: V5.16.1——非 nil 时所有 cell 用此宽（Photos.app "图库" uniform square 模式）
    ///     nil 时走 masonry 模式（V5.16 默认），cell 宽 = rowHeight × item.aspectRatio
    ///   - stretchLastRow: V5.16.2——true 时末行不满则把多余宽均分到末行每个 cell
    ///     (Flickr / 500px 风格：消除"空右缘"但不破坏行高)
    ///     默认 false（V5.16 行为）——保持 Photos.app "末尾不满"传统
    /// - Returns: 行数组——每行 cell 总宽（含 spacing）≤ availableWidth
    ///   stretchLastRow=true 时末行总宽 = availableWidth（精确填满）
    static func groupIntoRows(
        items: [Item],
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        spacing: CGFloat,
        uniformWidth: CGFloat? = nil,
        stretchLastRow: Bool = false
    ) -> [Row] {
        guard availableWidth > 0, rowHeight > 0 else { return [] }

        var rows: [Row] = []
        var current: [Item] = []
        var currentWidth: CGFloat = 0  // 当前行已用宽（含 spacing）

        for item in items {
            // V5.16.1: uniformWidth 模式 vs masonry 模式
            //   uniformWidth=200 → 所有 cell 200pt 宽（方形 cell）—— image letterbox
            //   uniformWidth=nil → cell 宽 = rowHeight × aspectRatio（masonry）
            let cellWidth = uniformWidth ?? (rowHeight * item.aspectRatio)
            let projectedWidth: CGFloat
            if current.isEmpty {
                projectedWidth = cellWidth
            } else {
                projectedWidth = currentWidth + spacing + cellWidth
            }

            // 当前行非空 + 加上这个 cell 超 availableWidth → 开新行
            if !current.isEmpty && projectedWidth > availableWidth {
                rows.append(Row(items: current))
                current = [item]
                currentWidth = cellWidth
            } else {
                current.append(item)
                currentWidth = projectedWidth
            }
        }
        if !current.isEmpty { rows.append(Row(items: current)) }

        // V5.16.2: 末行拉宽——把多余宽均分到末行每个 cell
        if stretchLastRow, !rows.isEmpty, let lastRow = rows.last, lastRow.items.count > 0 {
            let lastRowWidth = lastRow.renderedWidth(spacing: spacing)
            let extra = availableWidth - lastRowWidth
            if extra > 0 {
                // extra 含 spacing：每 cell += extra/count + 每 cell 之间补 spacing/count
                //   简单做法：perCellExtra = extra / count（cell 数决定）—— 末行整行宽恰 = availableWidth
                let perCellExtra = extra / CGFloat(lastRow.items.count)
                let stretchedItems = lastRow.items.map { item in
                    Item(
                        id: item.id,
                        width: item.width + perCellExtra,
                        aspectRatio: item.aspectRatio
                    )
                }
                rows[rows.count - 1] = Row(items: stretchedItems)
            }
        }

        return rows
    }

    // MARK: - V5.36: Justified Row Layout (Photos.app Library 真版)

    /// V5.36: JustifiedRow——per-row height, aspect-preserving
    ///   - row 内 cell 高度严格相等 (= rowHeight)
    ///   - row 内 cell 宽度 = rowHeight × aspectRatio
    ///   - 整行 width 严格 = availableWidth (Photos 行为)
    ///   - rowHeight 跨 row 不固定, 由该 row 内的 photos 决定
    struct JustifiedRow: Equatable {
        let items: [Item]
        let rowHeight: CGFloat
        let spacing: CGFloat

        init(items: [Item], availableWidth: CGFloat, spacing: CGFloat) {
            self.items = items
            self.spacing = spacing
            let n = items.count
            let spacingTotal = CGFloat(max(n - 1, 0)) * spacing
            // rowHeight 公式: n×spacing + sumOfAspects × rowHeight = availableWidth
            // → rowHeight = (availableWidth - n×spacing) / sumOfAspects
            // 验证: 整行 width = spacingTotal + sumOfAspects × rowHeight
            //                 = (n-1)×spacing + sumOfAspects × (availableWidth - (n-1)×spacing) / sumOfAspects
            //                 = (n-1)×spacing + availableWidth - (n-1)×spacing
            //                 = availableWidth ✓
            let aspectSum = items.reduce(0.0) { $0 + $1.aspectRatio }
            self.rowHeight = aspectSum > 0
                ? (availableWidth - spacingTotal) / aspectSum
                : 0
        }
    }

    /// V5.36: Photos.app Library 真版算法——greedy pack + per-row height
    ///   - 输入: photos (按 sortOption 排好) + availableWidth + spacing
    ///   - 输出: [JustifiedRow], 每个 row 严格填满 availableWidth
    ///   - 区别 V5.16 groupIntoRows: 那个固定 rowHeight, 末行不满;
    ///     新的 per-row 算 rowHeight, 每个 row 都填满
    ///   - 镜像 macOS Photos.app Library, Google Photos, Flickr justified grid
    ///
    /// 算法 (greedy + justified):
    /// 1. 当前行累计 aspect sum
    /// 2. 加下个 item: 若 (nGaps × spacing + newAspectSum) ≤ availableWidth, 加进去
    /// 3. 否则 finalize 当前行: rowHeight = (availableWidth - nGaps × spacing) / aspectSum
    /// 4. 开新行
    ///
    /// 例子 (3 张 16:9 + 1 张 4:3, availableWidth=1000, spacing=4):
    /// - Item 1 (16:9=1.78): current=[1], aspectSum=1.78, 总宽 at h=1 = 1.78 ≤ 1000 ✓
    /// - Item 2 (16:9=1.78): nGaps=1, 新总宽 = 1×4 + (1.78+1.78) = 7.56 ≤ 1000 ✓
    ///   current=[1,2], aspectSum=3.56
    /// - Item 3 (16:9=1.78): nGaps=2, 新总宽 = 2×4 + (3.56+1.78) = 9.12 ≤ 1000 ✓
    ///   current=[1,2,3], aspectSum=5.34
    /// - Item 4 (4:3=1.33): nGaps=3, 新总宽 = 3×4 + (5.34+1.33) = 12.67 ≤ 1000 ✓
    ///   current=[1,2,3,4], aspectSum=6.67
    /// - Finalize: rowHeight = (1000 - 3×4) / 6.67 = 988/6.67 ≈ 148.13pt
    ///   Cell widths: 148.13×1.78 = 263.6, 263.6, 263.6, 148.13×1.33 = 197.0
    ///   验证: 3×4 + 263.6 + 263.6 + 263.6 + 197.0 = 999.8 ≈ 1000 ✓
    static func packJustifiedRows(
        items: [Item],
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [JustifiedRow] {
        guard availableWidth > 0, !items.isEmpty else { return [] }

        var rows: [JustifiedRow] = []
        var current: [Item] = []
        var currentAspectSum: CGFloat = 0

        for item in items {
            if current.isEmpty {
                current.append(item)
                currentAspectSum = item.aspectRatio
            } else {
                // n current items, n-1 gaps, 加 1 item 后 = n+1 items, n gaps
                let nGaps = current.count
                let newAspectSum = currentAspectSum + item.aspectRatio
                // Width at h=1: nGaps × spacing + newAspectSum (sum of aspects at h=1)
                let totalWidthAtH1 = CGFloat(nGaps) * spacing + newAspectSum
                if totalWidthAtH1 <= availableWidth {
                    current.append(item)
                    currentAspectSum = newAspectSum
                } else {
                    rows.append(JustifiedRow(items: current, availableWidth: availableWidth, spacing: spacing))
                    current = [item]
                    currentAspectSum = item.aspectRatio
                }
            }
        }
        if !current.isEmpty {
            rows.append(JustifiedRow(items: current, availableWidth: availableWidth, spacing: spacing))
        }
        return rows
    }
}
