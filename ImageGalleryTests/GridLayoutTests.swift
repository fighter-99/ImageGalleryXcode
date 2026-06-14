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

    // MARK: - V5.47: 删 mixedAspectRatiosInOneRow 测试——V5.47 砍 .masonry 后
    //   唯一保留的 2 模式 (.square / .squareFit) 都用 uniform 1:1 cell 宽
    //   "不同 aspect → 不同 width" 的 .masonry 行为已不存在
    //   同 row 多 cell 测试见 narrowWindowOneItemPerRow / wideWindowManyItemsPerRow

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
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
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

    // MARK: - V5.47: 删 .masonry 测试——V5.47 砍 .masonry case, dead code
    //   之前 masonryModeCellWidthBasedOnAspect / masonryModeLastRowKeepsTargetRowHeight /
    //   masonryModeActualRowHeightCloseToTarget / masonryModeSingleWideItemStretchesToFit /
    //   masonryModeLastRowWideItemDoesNotOverflow / masonryModeNoOverflowInvariant /
    //   layoutModeParamAffectsCellWidths (masonry 部分) 全部删除
    //   masonryAndMasonryStretchDifferInLastRow 已在 V5.39.5 删

    @Test func squareModeCellSizeMatchesFormula() {
        // V5.47 重命名: 之前叫 squareModeEqualToMasonryParamsUniformWidth (含 .masonry 名字已废)
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
}
