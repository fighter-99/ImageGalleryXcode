//
//  MasonryMathTests.swift
//  ImageGalleryTests
//
//  V5.16: MasonryMath.groupIntoRows 测试（pure function）
//  镜像 DragReorderMathTests.swift pattern（无 @MainActor，pure function test）
//  避 V5.14 helper-method bug
//

import Testing
import Foundation
@testable import ImageGallery

struct MasonryMathTests {
    // MARK: - 基础边界

    @Test func emptyItemsReturnsNoRows() {
        let rows = MasonryMath.groupIntoRows(
            items: [],
            availableWidth: 800,
            rowHeight: 200,
            spacing: 12
        )
        #expect(rows.isEmpty)
    }

    @Test func zeroAvailableWidthReturnsEmpty() {
        let items = [MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 0, rowHeight: 200, spacing: 12
        )
        #expect(rows.isEmpty)
    }

    @Test func zeroRowHeightReturnsEmpty() {
        let items = [MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 0, spacing: 12
        )
        #expect(rows.isEmpty)
    }

    // MARK: - 单/少张照片

    @Test func singleItemReturnsSingleRow() {
        let items = [MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        #expect(rows.count == 1)
        #expect(rows.first?.items.count == 1)
    }

    @Test func threeItemsFitOneRow() {
        // 3 张方形 (1:1) @ rowHeight 200 → 200×3 + 12×2 = 624 ≤ 800 → 1 行
        let items = (0..<3).map { _ in
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)
        }
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        #expect(rows.count == 1)
        #expect(rows.first?.items.count == 3)
    }

    // MARK: - 多张照片 reflow

    @Test func fiveSquareItemsFlowToTwoRows() {
        // 5 张方形 @ 200 → 200×5 + 12×4 = 1048 > 800
        // 应分 2 行：(4 + 1) 或 (3 + 2)
        // 800 / (200 + 12) ≈ 3.76 → 第 1 行最多 3 张
        // 200×3 + 12×2 = 624 ≤ 800 ✓
        // 200×4 + 12×3 = 836 > 800 ✗ → 第 2 行 2 张
        let items = (0..<5).map { _ in
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)
        }
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        #expect(rows.count == 2)
        #expect(rows[0].items.count == 3)
        #expect(rows[1].items.count == 2)
    }

    @Test func portraitPhotosNeedMoreRows() {
        // 8 张 3:4 (竖) → width = 200 × 0.75 = 150
        // 5×150 + 4×12 = 798 ≤ 800 → 第 1 行 5 张
        // 6th: 798+12+150=960 > 800 → 跳行 → 第 2 行 3 张
        let items = (0..<8).map { _ in
            MasonryMath.Item(id: UUID(), width: 150, aspectRatio: 0.75)
        }
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        #expect(rows.count == 2)
        #expect(rows[0].items.count == 5)
        #expect(rows[1].items.count == 3)
    }

    // MARK: - 混合 aspect

    @Test func mixedAspectReflowsCorrectly() {
        // 4 张不同 aspect @ 800pt 容器：
        //  横向 4:3 (267pt), 方形 (200pt), 方形 (200pt), 竖向 3:4 (150pt)
        // 第 1 行：267 + 12 + 200 + 12 + 200 + 12 + 150 = 853 > 800 → 分
        //   实际：267 + 12 + 200 + 12 + 200 = 691 ≤ 800 ✓ (3 张)
        //   加 12 + 150 = 853 > 800 → 跳行
        // 第 2 行：150（仅 1 张不满）
        let items = [
            MasonryMath.Item(id: UUID(), width: 267, aspectRatio: 4.0/3.0),
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: UUID(), width: 150, aspectRatio: 0.75),
        ]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        // 验证每行渲染宽度 ≤ availableWidth
        for row in rows {
            #expect(row.renderedWidth(spacing: 12) <= 800)
        }
    }

    @Test func wideLandscapeFlowsAlone() {
        // 1 张 16:9 超横 → width = 200 × 1.778 = 356
        // 第 1 行：356（1 张）
        let items = [MasonryMath.Item(id: UUID(), width: 356, aspectRatio: 16.0/9.0)]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        #expect(rows.count == 1)
        #expect(rows.first?.items.count == 1)
        #expect(rows.first?.items.first?.width == 356)
    }

    // MARK: - 边界情况

    @Test func lastRowUnderflowAccepted() {
        // 2 张 1:1 + 1 张超横（远宽于 200）→ 后者单独成行
        let items = [
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: UUID(), width: 800, aspectRatio: 4.0),  // 极宽
        ]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 600, rowHeight: 200, spacing: 12
        )
        // 第 1 行：200 + 12 + 200 = 412 ≤ 600 ✓
        // 加 12 + 800 = 1224 > 600 → 跳行
        // 第 2 行：800（单张不满）— Photos.app 行为
        #expect(rows.count == 2)
        #expect(rows[0].items.count == 2)
        #expect(rows[1].items.count == 1)
    }

    @Test func aspectRatioFallback() {
        // aspectRatio 0/负 → Item 仍可构造（width 由调用方算）
        // 验证 groupIntoRows 不因 aspectRatio 而崩
        let items = [
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 0),
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: -1),
        ]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        #expect(rows.count == 1)  // 200+12+200=412 < 800
    }

    @Test func rowTotalWidthMatchesSumOfWidthsPlusSpacing() {
        // 验证 renderedWidth 公式 = sum(widths) + (n-1) × spacing
        let items = (0..<3).map { _ in
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)
        }
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        // 1 行 3 cell：200×3 + 12×2 = 624
        #expect(rows[0].renderedWidth(spacing: 12) == 624)
    }

    @Test func itemPreservesIdThroughGrouping() {
        // 验证 id 在装箱过程中保持
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let items = [
            MasonryMath.Item(id: id1, width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: id2, width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: id3, width: 600, aspectRatio: 3.0),  // 单独成行
        ]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        // 找到 id3 应在单独行
        let id3Row = rows.first { $0.items.contains(where: { $0.id == id3 }) }
        #expect(id3Row?.items.count == 1)
        #expect(id3Row?.items.first?.id == id3)
    }

    // MARK: - V5.16.1: uniformWidth 模式（Photos.app "图库" 风格）

    @Test func uniformWidthIgnoresAspectRatio() {
        // uniformWidth=200 → 所有 cell 200pt 宽（无视 aspect）
        // 5 张不同 aspect @ availableWidth=800 → 800/(200+12)≈3.77 → 3 per row
        // 第 1 行：3 张 (3×200+2×12=624 ≤ 800)
        // 第 2 行：2 张
        let items = [
            MasonryMath.Item(id: UUID(), width: 0, aspectRatio: 4.0/3.0),  // 4:3
            MasonryMath.Item(id: UUID(), width: 0, aspectRatio: 1.0),        // 1:1
            MasonryMath.Item(id: UUID(), width: 0, aspectRatio: 2.0/3.0),  // 2:3
            MasonryMath.Item(id: UUID(), width: 0, aspectRatio: 16.0/9.0), // 16:9
            MasonryMath.Item(id: UUID(), width: 0, aspectRatio: 0.75),      // 3:4
        ]
        let rows = MasonryMath.groupIntoRows(
            items: items,
            availableWidth: 800,
            rowHeight: 200,
            spacing: 12,
            uniformWidth: 200
        )
        #expect(rows.count == 2)
        #expect(rows[0].items.count == 3)
        #expect(rows[1].items.count == 2)
        // 验证每行渲染宽 ≤ 800（uniformWidth 模式 cell 宽固定 200）
        for row in rows {
            let n = CGFloat(row.items.count)
            let rendered = n * 200 + (n - 1) * 12
            #expect(rendered <= 800)
        }
    }

    @Test func uniformWidthNilDefaultsToAspectMode() {
        // 不传 uniformWidth → 走原 V5.16 masonry 算法
        let items = [MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        // masonry 行为：1 张 1 行
        #expect(rows.count == 1)
        // 验证 Item.width 仍 = 200（aspect 模式按 rowHeight × aspectRatio 算）
        #expect(rows[0].items.first?.width == 200)
    }

    @Test func uniformWidthWithThreeSquares() {
        // 3 张方形 @ 200pt 宽 + 8pt spacing → 200×3+8×2=616 ≤ 800 → 1 行
        let items = (0..<3).map { _ in
            MasonryMath.Item(id: UUID(), width: 0, aspectRatio: 1.0)
        }
        let rows = MasonryMath.groupIntoRows(
            items: items,
            availableWidth: 800,
            rowHeight: 200,
            spacing: 8,
            uniformWidth: 200
        )
        #expect(rows.count == 1)
        #expect(rows[0].items.count == 3)
    }
}
