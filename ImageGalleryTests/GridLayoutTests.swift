//
//  GridLayoutTests.swift
//  ImageGalleryTests
//
//  V5.29-3 → V5.39: GridLayout 单元测试 (Photos.app 架构 V5.28 安全网)
//
//  验证：
//  - 3 个 mode (.square / .masonry / .masonryStretch) 映射正确
//  - 边界: 空 / 单张 / 1 row / multi row
//  - V5.39 黄金不变量 (替换 V5.36 不变量):
//    · .square: cell 宽 = rowHeight (uniform)
//    · .masonry: actualRowHeight ≈ targetRowHeight, 末行 = targetRowHeight (左对齐)
//    · .masonryStretch: actualRowHeight ≈ targetRowHeight, 末行 scale 填满
//  - 末行行为差异: .masonry 末行不拉伸 / .masonryStretch 末行拉伸
//  - 混合 aspect: portrait/landscape/square 在同 row 不同宽
//  - row id 稳定 (首 cell id)
//
//  V5.39 不变量 vs V5.36 不变量 (变):
//    V5.36 (已删): 每个 row 严格 = availableWidth (per-row rowHeight 跨 row 巨变)
//    V5.39 (本文件): 每个 row actualRowHeight ≈ targetRowHeight (微调尽量贴满)
//                  · 非末行: scaleFactor ≈ 1, 接近 targetRowHeight
//                  · 末行 (.masonry): actualRowHeight = targetRowHeight (左对齐)
//                  · 末行 (.masonryStretch): scaleFactor > 1, 填满 width
//    视觉差异: V5.39 row 高度更整齐 (Photos 风格), V5.36 row 高度可能阶梯式变化
//
//  镜像 MasonryMathTests / ThumbnailLayoutModeTests pattern
//  (无 @MainActor, pure function test, 避开 V5.14 helper-method bug)
//
//  V5.29-3: GridLayout 加 computeRows(from: [PhotoGridItem]) 重载
//    测试用此重载——不依赖 SwiftData @Model
//

import Testing
import Foundation
import CoreGraphics
@testable import ImageGallery

// MARK: - 测试 helper

/// V5.29-3: 测试用 PhotoGridItem 工厂 (避 SwiftData @Model 依赖)
private func makeItem(aspect: CGFloat, seed: Int = 0) -> PhotoGridItem {
    PhotoGridItem(
        id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", seed))")!,
        aspectRatio: aspect,
        width: 0
    )
}

private func makeItems(count: Int, aspect: CGFloat) -> [PhotoGridItem] {
    (0..<count).map { makeItem(aspect: aspect, seed: $0) }
}

// MARK: - 测试 suite

struct GridLayoutTests {

    // MARK: - 完整性 (完整性 / 边界)

    @Test func emptyItemsReturnsNoRows() {
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        #expect(layout.computeRows(from: [PhotoGridItem]()).isEmpty)
    }

    @Test func singleItemReturnsOneRow() {
        // V5.35+ .square 模式: cellSize 由 SquareLayout.cellSize 动态算 (填满 availableWidth)
        //   n=floor((1000+8)/(200+8))=4, cellSize=(1000-3*8)/4=244
        //   即使只 1 item, cellSize 仍按"按 rowHeight 能放几个 cell"算 (V5.35 Photos 真版)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: [makeItem(aspect: 1.0, seed: 1)])
        #expect(rows.count == 1)
        #expect(rows[0].items.count == 1)
        // V5.35: rowHeight = cellSize = 244
        #expect(abs(rows[0].rowHeight - 244) < 0.01)
    }

    @Test func manyItemsProducesMultipleRows() {
        // 100 张 1:1 photo, 240pt cell + 8pt spacing, available 1000pt → 4 cell/row → 25 row
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 240, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: makeItems(count: 100, aspect: 1.0))
        // n = floor((1000+8)/(240+8)) = 4 cell/row
        #expect(rows.count == 25)
    }

    // MARK: - .square mode: uniform cells = rowHeight

    @Test func squareModeCellWidthEqualsRowHeight() {
        // V5.35+ 行为: .square 模式 cell 宽 = cellSize (动态算填满 availableWidth)
        //   与 V5.16.1 (cell 宽 = rowHeight) 不同——V5.35 取消固定方形
        //   cellSize = (1000 - 3*8) / 4 = 244 (n=4 cells/row)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 240, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: makeItems(count: 10, aspect: 1.0))
        for row in rows {
            for item in row.items {
                #expect(abs(item.width - 244) < 0.01, "V5.35+ .square cell 宽 = cellSize = 244")
            }
        }
    }

    @Test func squareModeFirstRowFillsAvailableWidth() {
        // V5.35+ 黄金不变量: 满 row 累计宽 + 间距 = availableWidth (精确填满)
        //   n=4 cell/row, cellSize=244 → 总宽 = 4*244 + 3*8 = 1000
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 240, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: makeItems(count: 10, aspect: 1.0))
        let firstRowWidth = rows[0].renderedWidth(spacing: 8)
        #expect(abs(firstRowWidth - 1000) < 0.5, "V5.35+ 满 row 严格填满 availableWidth")
    }

    @Test func squareModeLastRowMayNotFill() {
        // 末行 3 张, 不拉伸 (V5.27 行为: macOS Photos 末行不拉满)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 240, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: makeItems(count: 7, aspect: 1.0))
        // 4 + 3 row, 末 row 3 cell
        #expect(rows.count == 2)
        #expect(rows[1].items.count == 3)
        // 末 row 宽 = 3*240 + 2*8 = 736, 不等于 availableWidth 1000
        #expect(rows[1].renderedWidth(spacing: 8) < 1000, "末行不拉满 (V5.27 行为)")
    }

    // MARK: - .masonry mode (V5.39 黄金不变量)

    @Test func masonryModeCellWidthBasedOnAspect() {
        // V5.39.1 黄金不变量:
        //   · cell 宽 = actualRowHeight × aspect
        //   · 唯一行 (也是末行) → 拉伸填满 (V5.36 行为, V5.39.1 修复)
        //   · actualRowHeight = 200 × 1000 / (200 × 3.083 + 2×8) ≈ 319.10
        //   · cell 宽 = actualRowHeight × aspect
        // 3 items (1.0, 0.75, 1.333) 都 fit 在 1 row, 该 row 既是 row 1 也是末行
        let items: [PhotoGridItem] = [
            makeItem(aspect: 1.0, seed: 1),
            makeItem(aspect: 0.75, seed: 2),  // 3:4 portrait
            makeItem(aspect: 1.333, seed: 3),  // 4:3 landscape
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        // 3 items 全在 1 row
        #expect(rows.count == 1, "3 items 全 fit 在 1 row (唯一 row, 也是末行)")
        #expect(rows[0].items.count == 3)
        // V5.39.1: 唯一行拉伸, actualRowHeight ≈ 319.10 (不 = 200)
        let aspectSum = 1.0 + 0.75 + 1.333
        let expectedRowHeight: CGFloat = 200.0 * (1000.0 - 2.0 * 8.0) / (200.0 * aspectSum)
        #expect(abs(rows[0].rowHeight - expectedRowHeight) < 0.5,
                "V5.39.1 唯一行拉伸: actualRowHeight ≈ \(expectedRowHeight), actual=\(rows[0].rowHeight)")
        // V5.39.1 黄金不变量: cell 宽 = actualRowHeight × aspect
        let h = rows[0].rowHeight
        #expect(abs(rows[0].items[0].width - h * 1.0) < 0.01,
                "1:1 cell 宽 = \(h) × 1.0 = \(h * 1.0), actual=\(rows[0].items[0].width)")
        #expect(abs(rows[0].items[1].width - h * 0.75) < 0.01,
                "3:4 cell 宽 = \(h) × 0.75 = \(h * 0.75), actual=\(rows[0].items[1].width)")
        #expect(abs(rows[0].items[2].width - h * 1.333) < 0.01,
                "4:3 cell 宽 = \(h) × 1.333 = \(h * 1.333), actual=\(rows[0].items[2].width)")
    }

    @Test func masonryModeLastRowKeepsTargetRowHeight() {
        // V5.39 黄金不变量 (替换 V5.36 黄金不变量):
        //   · .masonry 模式: 末行 actualRowHeight = targetRowHeight (左对齐, 不 scale)
        //   · 末行 cell 实际宽 = targetRowHeight × cell.aspectRatio (可能 < cellWidth 在 scale 模式下)
        // 7 张 3:4 portrait @ targetRowHeight=200, availableWidth=1000, spacing=8:
        //   pack: 6 items 一行 (200×4.5+5×8=940 ≤ 1000; 加第 7 个 200×5.25+6×8=1098 > 1000)
        //   Row 1: 6 items, actualRowHeight = 200 × 1000/940 = 212.77
        //   Row 2 (末行, stretchLastRow=false): 1 item, actualRowHeight = 200 (保持 target)
        let items = makeItems(count: 7, aspect: 0.75)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        #expect(rows.count == 2)
        // Row 1: 6 cells, actualRowHeight 微调 (> 200)
        #expect(rows[0].items.count == 6)
        #expect(rows[0].rowHeight > 200, "非末行 actualRowHeight 略 > targetRowHeight (scaleFactor ≈ 1.06)")
        // Row 2: 1 cell, actualRowHeight 严格 = targetRowHeight (左对齐 Photos 真版)
        #expect(rows[1].items.count == 1)
        #expect(abs(rows[1].rowHeight - 200) < 0.01, "V5.39 黄金不变量: 末行 actualRowHeight = targetRowHeight")
    }

    @Test func masonryModeActualRowHeightCloseToTarget() {
        // V5.39: 非末行 actualRowHeight 接近 targetRowHeight, scaleFactor 在 0.9~1.1 之间
        // 4 张 1:1 + 1 张 16:9: 2 row
        //   Row 1: 4 1:1, aspectSum=4
        //     theoreticalWidth = 200×4 + 3×8 = 824
        //     scaleFactor = 1000/824 = 1.2136
        //     actualRowHeight = 200 × 1.2136 = 242.72
        //   Row 2 (末): 1 16:9, actualRowHeight = 200 (保持 target)
        let items: [PhotoGridItem] = [
            makeItem(aspect: 1.0, seed: 1),
            makeItem(aspect: 1.0, seed: 2),
            makeItem(aspect: 1.0, seed: 3),
            makeItem(aspect: 1.0, seed: 4),
            makeItem(aspect: 1.778, seed: 5),
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        #expect(rows.count == 2)
        // Row 1 actualRowHeight 在 [180, 260] 范围内 (V5.39 接近 target, 不会阶梯式巨变)
        #expect(rows[0].rowHeight > 200, "Row 1 actualRowHeight > 200 (scaleFactor > 1)")
        #expect(rows[0].rowHeight < 260, "Row 1 actualRowHeight 接近 target (V5.39 不应阶梯)")
        // Row 2 末行 = target
        #expect(abs(rows[1].rowHeight - 200) < 0.01, "Row 2 末行 = targetRowHeight")
    }

    // MARK: - V5.39.5: 删 .masonryStretch mode 测试
    //   - masonryStretchLastRowScalesToFill 删 (.masonryStretch case 已删)
    //   - masonryAndMasonryStretchDifferInLastRow 删 (末行行为差异不再存在)

    // MARK: - 跨宽测试

    @Test func narrowWindowOneItemPerRow() {
        // 极窄窗口: 1 cell / row
        let items = makeItems(count: 5, aspect: 1.0)
        let layout = GridLayout(
            availableWidth: 100, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: items)
        // 100 / 200 < 1 → 1 cell / row → 5 row
        #expect(rows.count == 5)
    }

    @Test func wideWindowManyItemsPerRow() {
        // 极宽窗口: 8 cell / row
        let items = makeItems(count: 20, aspect: 1.0)
        let layout = GridLayout(
            availableWidth: 2000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: items)
        // 2000 / 208 = 9.6 → 9 cell / row → 20 / 9 = 3 row (9, 9, 2)
        #expect(rows.count == 3)
        #expect(rows[0].items.count == 9)
        #expect(rows[1].items.count == 9)
        #expect(rows[2].items.count == 2)
    }

    // MARK: - 混合 aspect 在同 row

    @Test func mixedAspectRatiosInOneRow() {
        // portrait/landscape/square 混排, 同 row
        let items: [PhotoGridItem] = [
            makeItem(aspect: 0.75, seed: 1),   // 3:4 portrait
            makeItem(aspect: 1.0, seed: 2),    // 1:1
            makeItem(aspect: 1.5, seed: 3),    // 3:2 landscape
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        // 3 个 cell 总宽 = 150 + 200 + 300 + 2*8 = 666 < 1000, 全在第 1 row
        #expect(rows[0].items.count == 3)
        // 不同 aspect → 不同 width
        #expect(rows[0].items[0].width != rows[0].items[1].width)
        #expect(rows[0].items[1].width != rows[0].items[2].width)
    }

    // MARK: - Identifiable 稳定性

    @Test func rowIdIsFirstItemId() {
        // V5.29-2: GridRow.id = 首 cell id——SwiftUI ForEach 需要稳定 id
        let items: [PhotoGridItem] = [
            makeItem(aspect: 1.0, seed: 10),
            makeItem(aspect: 1.0, seed: 20),
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: items)
        #expect(rows[0].id == items[0].id)
    }

    @Test func itemsPreserveOriginalAspectRatio() {
        // 验证: 算完 width 后 aspectRatio 字段不变
        let items: [PhotoGridItem] = [
            makeItem(aspect: 0.75, seed: 1),
            makeItem(aspect: 1.5, seed: 2),
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        #expect(rows[0].items[0].aspectRatio == 0.75)
        #expect(rows[0].items[1].aspectRatio == 1.5)
    }

    // MARK: - Equatable 一致性

    @Test func sameInputsProduceSameRows() {
        // 纯函数: 同样输入应产生同样输出
        let items = makeItems(count: 5, aspect: 1.0)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        let rows1 = layout.computeRows(from: items)
        let rows2 = layout.computeRows(from: items)
        #expect(rows1 == rows2)
    }

    // MARK: - V5.39.1 不变量: cells 不溢出 + 唯一行拉伸

    @Test func masonryModeSingleWideItemStretchesToFit() {
        // V5.39.1 修复: 唯一行 (1 张图) 总是拉伸填满 (V5.36 行为)
        //   原 V5.39 bug: 末行+stretchLastRow=false 时 actualRowHeight=targetRowHeight=200
        //     → cell width = 200 × 10 = 2000 > 1000, 溢出!
        //   V5.39.1 加 isOnlyRow 拉伸 + 末行溢出 fallback
        let items = [makeItem(aspect: 10.0, seed: 1)]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        #expect(rows.count == 1)
        // 唯一行 → 拉伸: actualRowHeight × aspect × 1 + 0×spacing = availableWidth
        //   actualRowHeight = 1000 / 10 = 100
        //   cell width = 100 × 10 = 1000 ✓
        #expect(abs(rows[0].rowHeight - 100) < 0.5,
                "V5.39.1: 唯一行(1张) actualRowHeight 拉伸到 fit availableWidth")
        #expect(abs(rows[0].items[0].width - 1000) < 0.5,
                "V5.39.1: 唯一行(1张) cell 宽 = availableWidth (无溢出)")
    }

    @Test func masonryModeLastRowWideItemDoesNotOverflow() {
        // V5.39.1 修复: 末行 + stretchLastRow=false + 极宽图不溢出
        //   场景: 2 张 10:1 极宽图, availableWidth=1000
        //   pack: Item 1 入 row1 (aspectSum=10, theoreticalWidth=200×10+0=2000)
        //     Item 2: newTheoreticalWidth=200×20+8=4008 > 1000 → finalize row1
        //   Row 1 (非末): actualRowHeight=1000/10=100, cell width=1000
        //   Row 2 (末): 1 张 10:1, theoreticalWidth=2000 > 1000 → overflow fallback
        //     actualRowHeight=1000/10=100, cell width=1000
        let items = [
            makeItem(aspect: 10.0, seed: 1),
            makeItem(aspect: 10.0, seed: 2),
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        #expect(rows.count == 2)
        // Row 1: 1 cell at actualRowHeight=100, cell width=1000
        #expect(abs(rows[0].rowHeight - 100) < 0.5)
        #expect(abs(rows[0].items[0].width - 1000) < 0.5)
        // Row 2: 末行 1 cell, overflow fallback: actualRowHeight=100, cell width=1000
        //   V5.39 bug 会让 actualRowHeight=200, cell width=2000 (溢出!)
        //   V5.39.1 fallback: 即使 stretchLastRow=false, overflow 时压缩到 fit
        #expect(rows[1].rowHeight <= 200, "V5.39.1 末行不溢出: actualRowHeight ≤ targetRowHeight")
        #expect(rows[1].items[0].width <= 1000.5,
                "V5.39.1 末行不溢出: cell 宽 ≤ availableWidth + spacing, actual=\(rows[1].items[0].width)")
    }

    @Test func masonryModeNoOverflowInvariant() {
        // V5.39.1 黄金不变量: 任何 row 的 cell 总宽 + spacing ≤ availableWidth
        //   这是 V5.39.1 关键不变量——保证 cell 永远不溢出
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        // 各种 aspect 组合, 包括极宽/极窄
        let scenarios: [[CGFloat]] = [
            [1.0],                  // 唯一行, 1张
            [1.0, 1.0, 1.0],        // 唯一行, 3张
            [10.0],                 // 唯一行, 1张 极宽
            [10.0, 10.0, 10.0],     // 多张 极宽
            [0.3, 0.3, 0.3, 0.3],   // 多张 极窄 (portrait)
            [1.0, 10.0, 1.0],       // 混合
            [5.0, 0.2, 5.0, 0.2],   // 极宽+极窄
        ]
        for aspects in scenarios {
            let items = aspects.enumerated().map { makeItem(aspect: $1, seed: $0) }
            let rows = layout.computeRows(from: items)
            for row in rows {
                let totalImageWidth = row.items.map(\.width).reduce(0, +)
                let totalSpacing = CGFloat(max(0, row.items.count - 1)) * 8
                let totalWidth = totalImageWidth + totalSpacing
                #expect(totalWidth <= 1000.5,
                        "V5.39.1 不变量: row 总宽 ≤ availableWidth (aspects=\(aspects), actual=\(totalWidth))")
            }
        }
    }

    // MARK: - V5.39.5: 删 masonryStretchModeNoOverflow (.masonryStretch case 已删)
    //   masonryStretchLastRowScalesToFill 和 masonryAndMasonryStretchDifferInLastRow 也已删 (更早)

    // MARK: - V5.27 行为契约

    @Test func squareModeEqualToMasonryParamsUniformWidth() {
        // V5.35+ 行为契约: .square mode cell 宽 = cellSize (动态算)
        //   cellSize = (1000 - (n-1)*8) / n, n = floor((1000+8)/(rowHeight+8))
        //   与 V5.16.1 (cell 宽 = rowHeight) 不同——V5.35 取消固定方形
        for rowHeight in [CGFloat(80), 120, 180, 240, 360] {
            // V5.35+: cellSize 动态算
            let n = max(1, Int(floor((1000 + 8) / (rowHeight + 8))))
            let cellSize = (1000 - CGFloat(n - 1) * 8) / CGFloat(n)
            let layout = GridLayout(
                availableWidth: 1000, rowHeight: rowHeight, cellSpacing: 8, layoutMode: .square
            )
            let rows = layout.computeRows(from: makeItems(count: 3, aspect: 1.0))
            for row in rows {
                for item in row.items {
                    #expect(abs(item.width - cellSize) < 0.01,
                            "rowHeight=\(rowHeight) → cellSize=\(cellSize) (n=\(n))")
                }
            }
        }
    }

    @Test func layoutModeParamAffectsCellWidths() {
        // 同 items + 同尺寸下, 不同 mode → 不同 cell 宽
        let items = makeItems(count: 3, aspect: 0.5)  // 极 portrait (2:1)
        let squareRows = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        ).computeRows(from: items)
        let masonryRows = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        ).computeRows(from: items)
        // V5.35+ square: cell 宽 = cellSize = (1000 - 3×8)/4 = 244
        #expect(abs(squareRows[0].items[0].width - 244) < 0.01)
        // V5.39 masonry: cell 宽 = actualRowHeight × 0.5
        //   aspectSum=1.5, theoreticalWidth=200×1.5+2×8=316
        //   scaleFactor=1000/316≈3.165, actualRowHeight=200×3.165≈632.91
        //   cell width = 632.91 × 0.5 ≈ 316.46
        let masonryActualRowHeight = masonryRows[0].rowHeight
        let expectedMasonryWidth: CGFloat = (masonryActualRowHeight * 0.5 * 100).rounded() / 100
        #expect(abs(masonryRows[0].items[0].width - expectedMasonryWidth) < 0.5,
                "V5.39 masonry: cell 宽 = actualRowHeight × aspect ≈ \(expectedMasonryWidth)")
    }
}
