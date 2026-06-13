//
//  GridLayoutTests.swift
//  ImageGalleryTests
//
//  V5.29-3: GridLayout 单元测试 (Photos.app 架构 V5.28 安全网)
//
//  验证：
//  - 3 个 mode (.square / .masonry / .masonryStretch) 映射正确
//  - 边界: 空 / 单张 / 1 row / multi row
//  - 黄金不变量: square 模式 cell 宽 = rowHeight, masonry 模式按 aspect
//  - 末行行为: .square 不拉满, .masonry 不拉满 (留空), .masonryStretch 拉满
//  - 混合 aspect: portrait/landscape/square 在同 row 不同宽
//  - row id 稳定 (首 cell id)
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
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: [makeItem(aspect: 1.0, seed: 1)])
        #expect(rows.count == 1)
        #expect(rows[0].items.count == 1)
        #expect(rows[0].rowHeight == 200)
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
        // V5.27 行为: .square 模式 cell 宽 = rowHeight (固定方形)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 240, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: makeItems(count: 10, aspect: 1.0))
        // 每 row 内所有 cell 宽应等于 rowHeight
        for row in rows {
            for item in row.items {
                #expect(item.width == 240, "square mode cell 宽应 = rowHeight (240)")
            }
        }
    }

    @Test func squareModeFirstRowFillsAvailableWidth() {
        // 黄金不变量: 满 row 累计宽 + 间距 ≈ availableWidth
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 240, cellSpacing: 8, layoutMode: .square
        )
        let rows = layout.computeRows(from: makeItems(count: 10, aspect: 1.0))
        // 第 1 row 满 4 cell (1000 / 248 = 4) → 总宽 = 4*240 + 3*8 = 984
        let firstRowWidth = rows[0].renderedWidth(spacing: 8)
        #expect(firstRowWidth == 984)  // 精确填满 (976 残余 16 = 4 cell 多 4pt 留给间距)
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

    // MARK: - .masonry mode: aspect-preserving, last row gaps

    @Test func masonryModeCellWidthBasedOnAspect() {
        // 1:1 (200), 3:4 portrait (150), 4:3 landscape (266.67) at rowHeight 200
        let items: [PhotoGridItem] = [
            makeItem(aspect: 1.0, seed: 1),
            makeItem(aspect: 0.75, seed: 2),  // 3:4 portrait
            makeItem(aspect: 1.333, seed: 3),  // 4:3 landscape
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        // 3 个不同 aspect 都在第 1 row
        #expect(rows[0].items.count == 3)
        // cell 宽 = rowHeight × aspect
        #expect(rows[0].items[0].width == 200)   // 1:1
        #expect(rows[0].items[1].width == 150)   // 3:4 portrait
        #expect(rows[0].items[2].width == 266.6) // 4:3 landscape (近似)
    }

    @Test func masonryModeLastRowHasGaps() {
        // 末行不满时空格 = 窗口色 (V5.27 行为, 不拉满)
        let items = makeItems(count: 7, aspect: 0.75)  // 3:4 portrait
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        // 末 row 宽 < availableWidth
        let lastRowWidth = rows.last!.renderedWidth(spacing: 8)
        #expect(lastRowWidth < 1000, "masonry 末行不满, 留空")
    }

    // MARK: - .masonryStretch mode: last row stretched to fill

    @Test func masonryStretchModeLastRowFillsAvailableWidth() {
        // 黄金不变量: stretchLastRow=true 时末行总宽 = availableWidth
        let items = makeItems(count: 7, aspect: 0.75)  // 3:4 portrait
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonryStretch
        )
        let rows = layout.computeRows(from: items)
        // 末 row 宽 = availableWidth (精确)
        let lastRowWidth = rows.last!.renderedWidth(spacing: 8)
        #expect(lastRowWidth == 1000, "masonryStretch 末行精确填满")
    }

    @Test func masonryStretchModeFirstRowNotStretched() {
        // 满 row 不拉伸, 只末 row 拉伸
        let items = makeItems(count: 7, aspect: 0.75)
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonryStretch
        )
        let rows = layout.computeRows(from: items)
        // 满 row 累计 cell 宽 = 各 cell 原宽 (rowHeight × aspect)
        let firstRow = rows[0]
        for item in firstRow.items {
            // 满 row cell 宽 = rowHeight × aspect = 200 × 0.75 = 150
            #expect(item.width == 150, "满 row cell 宽不被拉伸 (150)")
        }
    }

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

    // MARK: - V5.27 行为契约

    @Test func squareModeEqualToMasonryParamsUniformWidth() {
        // V5.27-1 行为契约: .square mode uniformWidth = rowHeight
        // V5.29 行为契约: .square mode 所有 cell 宽 = rowHeight (uniform 模式)
        for rowHeight in [CGFloat(80), 120, 180, 240, 360] {
            let layout = GridLayout(
                availableWidth: 1000, rowHeight: rowHeight, cellSpacing: 8, layoutMode: .square
            )
            let rows = layout.computeRows(from: makeItems(count: 3, aspect: 1.0))
            for row in rows {
                for item in row.items {
                    #expect(item.width == rowHeight, "rowHeight=\(rowHeight) → cell 宽=\(rowHeight)")
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
        // square: cell 宽 = 200 (固定)
        #expect(squareRows[0].items[0].width == 200)
        // masonry: cell 宽 = 200 × 0.5 = 100
        #expect(masonryRows[0].items[0].width == 100)
    }
}
