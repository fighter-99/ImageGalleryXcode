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
    /// - Returns: 行数组——每行 cell 总宽（含 spacing）≤ availableWidth
    ///   最后一行不满不补齐（Photos.app 行为）
    static func groupIntoRows(
        items: [Item],
        availableWidth: CGFloat,
        rowHeight: CGFloat,
        spacing: CGFloat
    ) -> [Row] {
        guard availableWidth > 0, rowHeight > 0 else { return [] }

        var rows: [Row] = []
        var current: [Item] = []
        var currentWidth: CGFloat = 0  // 当前行已用宽（含 spacing）

        for item in items {
            let cellWidth = rowHeight * item.aspectRatio
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

        return rows
    }
}
