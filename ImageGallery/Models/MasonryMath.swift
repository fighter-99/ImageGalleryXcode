//
//  MasonryMath.swift
//  ImageGallery
//
//  V5.16 → V5.47: 主网格 row 装箱算法
//    - 行内 cell 高度统一（rowHeight）
//    - cell 宽度 = rowHeight × photoAspectRatio (.masonry 模式——V5.47 已删, dead code)
//    - cell 宽度 = rowHeight (.square 模式, V5.16.1, iOS Photos.app Library 风格)
//    - cell 宽度 = rowHeight (.squareFit 模式, V5.46, 1:1 + .fit letterbox)
//    - 行 reflow：cell 累加宽度超 availableWidth 时开新行
//    - 最后一行不满不补齐（Photos 通用行为）
//    - stretchLastRow=true 时末行均分多余宽 (V5.16.2, Flickr 风格——V5.47 无 caller)
//
//  ⚠️ V5.41 + V5.47 认知修正: 见 ThumbnailLayoutMode.swift header
//    - .square 模式 = iOS Photos.app Library (1:1 方格), 不是 macOS Photos 真版
//    - .squareFit 模式 (V5.46) = macOS Photos.app 按比例 真版 (1:1 + .fit letterbox)
//    - .masonry 模式 (V5.39) = Justified Row——V5.47 砍
//
//  V5.39 砍除 V5.36 packJustifiedRows + JustifiedRow struct——
//    V5.36 算法搬至 JustifiedRowLayout.swift (user spec 形式, targetRowHeight × scaleFactor)
//  V5.47: stretchLastRow 参数已无 caller——保留 groupIntoRows API 兼容
//    MasonryMath 只保留 .square / .squareFit 模式需要的 groupIntoRows + Item/Row
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
    ///   - uniformWidth: V5.16.1——非 nil 时所有 cell 用此宽（iOS Photos.app Library 风格 uniform square 模式）
    ///     nil 时走 masonry 模式（V5.16 默认），cell 宽 = rowHeight × item.aspectRatio
    ///   - stretchLastRow: V5.16.2——true 时末行不满则把多余宽均分到末行每个 cell
    ///     (Flickr / 500px 风格：消除"空右缘"但不破坏行高)
    ///     默认 false（V5.16 行为）——保持 Photos 通用"末尾不满"传统
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
}
