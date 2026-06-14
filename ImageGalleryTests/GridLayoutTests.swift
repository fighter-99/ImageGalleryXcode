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
        // V5.36: per-row height 算——3 items (1:1, 3:4, 4:3) 都在 1 row
        // 整行 aspectSum = 1.0 + 0.75 + 1.333 = 3.083
        // rowHeight = (1000 - 2×8) / 3.083 = 984/3.083 ≈ 319.18pt
        // cell widths: 319.18 × aspect
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
        // cell 宽 = 该 row 的 rowHeight × aspect (per-row 算的 rowHeight)
        // V5.36: rowHeight 跨 row 不固定, 这里 3 items 一行, rowHeight ≈ 319.18
        let expectedRowHeight: CGFloat = 984.0 / 3.083
        let expected1: CGFloat = (expectedRowHeight * 1.0 * 100).rounded() / 100   // ≈ 319.18
        let expected2: CGFloat = (expectedRowHeight * 0.75 * 100).rounded() / 100  // ≈ 239.39
        let expected3: CGFloat = (expectedRowHeight * 1.333 * 100).rounded() / 100  // ≈ 425.54
        #expect(abs(rows[0].items[0].width - expected1) < 0.5, "1:1 cell 宽 ≈ rowHeight")
        #expect(abs(rows[0].items[1].width - expected2) < 0.5, "3:4 cell 宽 ≈ rowHeight × 0.75")
        #expect(abs(rows[0].items[2].width - expected3) < 0.5, "4:3 cell 宽 ≈ rowHeight × 1.333")
        // 黄金不变量: 整行 cell 累加宽 + 间距 = availableWidth
        let totalWidth: CGFloat = rows[0].items.reduce(0) { $0 + $1.width } + CGFloat(rows[0].items.count - 1) * 8
        #expect(abs(totalWidth - 1000) < 0.5, "整行 cell + spacing 累加 = availableWidth")
    }

    // V5.36 注释: 旧测试 "masonryModeLastRowHasGaps" 删除
    //   - 旧算法 (V5.16 groupIntoRows 固定 rowHeight): 末行不满, 留空
    //   - 新算法 (V5.36 packJustifiedRows per-row height): 每个 row 都填满, 末行也填满
    //   - 新黄金不变量: 每个 row 严格 = availableWidth
    @Test func masonryModeEveryRowFillsAvailableWidth() {
        // V5.36 黄金不变量: 每个 row 整行宽 = availableWidth
        let items = makeItems(count: 7, aspect: 0.75)  // 7 张 3:4 portrait
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        // 每个 row 整行宽 (含 spacing) ≈ availableWidth
        for row in rows {
            let totalWidth = row.items.reduce(0) { $0 + $1.width } + CGFloat(row.items.count - 1) * 8
            #expect(abs(totalWidth - 1000) < 0.5, "V5.36 黄金不变量: 每个 row 严格填满")
        }
    }

    @Test func masonryModePerRowHeightVariesByAspect() {
        // V5.36: rowHeight 跨 row 不固定, 取决于该 row 内的 aspect 分布
        // 4 张 1:1 + 1 张 16:9: 2 row (4+1=4 容不下 5, 5 容不下 4 张 1:1)
        //   实际: row1 容 4 张 1:1, row2 容 1 张 16:9
        //   row1 rowHeight = (1000 - 3×8) / 4 = 976/4 = 244
        //   row2 rowHeight = (1000 - 0×8) / 1.778 = 562.43
        let items: [PhotoGridItem] = [
            makeItem(aspect: 1.0, seed: 1),
            makeItem(aspect: 1.0, seed: 2),
            makeItem(aspect: 1.0, seed: 3),
            makeItem(aspect: 1.0, seed: 4),
            makeItem(aspect: 1.778, seed: 5),  // 16:9
        ]
        let layout = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        )
        let rows = layout.computeRows(from: items)
        #expect(rows.count == 2)
        // row1: 4 张 1:1, rowHeight = 976/4 = 244
        #expect(abs(rows[0].rowHeight - 244.0) < 0.5, "row1 height = 244 (1:1 x 4)")
        // row2: 1 张 16:9, rowHeight = 1000/1.778 = 562.43
        #expect(abs(rows[1].rowHeight - 562.43) < 1.0, "row2 height ≈ 562 (16:9 x 1)")
    }

    // MARK: - .masonryStretch mode (V5.36: 等价 .masonry, 保留为用户多选项)

    @Test func masonryStretchModeBehavesIdenticalToMasonry() {
        // V5.36: .masonryStretch 与 .masonry 在新算法下等价 (没有'末行拉满'需要)
        // 两者应输出相同结构
        let items = makeItems(count: 7, aspect: 0.75)
        let masonryRows = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonry
        ).computeRows(from: items)
        let stretchRows = GridLayout(
            availableWidth: 1000, rowHeight: 200, cellSpacing: 8, layoutMode: .masonryStretch
        ).computeRows(from: items)
        // 两者都应每个 row 严格填满, 且 item count / per-item 宽可能因 rowHeight 算不同
        #expect(masonryRows.count == stretchRows.count, "V5.36: row 数相同")
        for (m, s) in zip(masonryRows, stretchRows) {
            #expect(m.items.count == s.items.count, "row 内 item 数相同")
            #expect(abs(m.rowHeight - s.rowHeight) < 0.5, "rowHeight 相同 (V5.36 算法等价)")
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
