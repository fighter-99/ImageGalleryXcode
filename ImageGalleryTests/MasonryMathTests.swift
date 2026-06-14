//
//  MasonryMathTests.swift
//  ImageGalleryTests
//
//  V5.16 → V5.39: MasonryMath.groupIntoRows 测试（pure function）
//  V5.39 砍除 packJustifiedRows 测试——
//  packJustifiedRows 已删 (V5.36 → 搬至 JustifiedRowLayout.swift, 用 packRows 测试)
//
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

    // MARK: - V5.16.1: uniformWidth 模式（iOS Photos.app Library 风格）
    // V5.41 修正：这是 iOS Photos.app 风格，不是 macOS Photos 真版

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

    // MARK: - V5.16.2: stretchLastRow 模式（justified + 末行拉宽）

    @Test func stretchLastRowFillsAvailableWidth() {
        // masonry 模式 + stretchLastRow=true
        // 2 张方形 (200pt 宽) + 1 张 2:3 portrait (133pt 宽)
        // 2×200+12+133=545 ≤ 800 → 1 行
        // 末行不满 800: extra = 800-545 = 255 → 3 cell 平分 = +85pt 每个
        // 末 cell 宽: 200 → 285, 200 → 285, 133 → 218
        // 验证末行精确填满 800
        let items = [
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0),
            MasonryMath.Item(id: UUID(), width: 133, aspectRatio: 2.0/3.0),
        ]
        let rows = MasonryMath.groupIntoRows(
            items: items,
            availableWidth: 800,
            rowHeight: 200,
            spacing: 12,
            stretchLastRow: true
        )
        #expect(rows.count == 1)
        // 末行总宽 = 285 + 12 + 285 + 12 + 218 = 812 — 但应 = 800
        // 实际：perCellExtra = 255/3 = 85 → 200+85=285, 200+85=285, 133+85=218
        // 285+12+285+12+218 = 812（不精确 800）— 算法稍偏
        // 实际应 = availableWidth（精确填满）—— 此测试暴露需要更精确算法
        // 用容差验证 ±2pt
        let rendered = rows[0].renderedWidth(spacing: 12)
        #expect(abs(rendered - 800) < 2, "末行应填满 800pt，actual \(rendered)")
    }

    @Test func stretchLastRowDefaultIsFalse() {
        // 不传 stretchLastRow → V5.16 默认行为：末行不满不补齐
        let items = [MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)]
        let rows = MasonryMath.groupIntoRows(
            items: items, availableWidth: 800, rowHeight: 200, spacing: 12
        )
        // 1 张 200pt → 末行总宽 200（不填满 800）
        #expect(rows[0].renderedWidth(spacing: 12) == 200)
    }

    @Test func stretchLastRowMultiRowStretchesLast() {
        // 5 张方形 @ 200pt → 800/(200+12)≈3.77 → 第 1 行 3 张 (624)
        // 第 2 行 2 张 (412) — stretchLastRow 应只拉第 2 行
        let items = (0..<5).map { _ in
            MasonryMath.Item(id: UUID(), width: 200, aspectRatio: 1.0)
        }
        let rows = MasonryMath.groupIntoRows(
            items: items,
            availableWidth: 800,
            rowHeight: 200,
            spacing: 12,
            stretchLastRow: true
        )
        #expect(rows.count == 2)
        // 第 1 行 3 cell: 200×3+12×2=624（不变，因非末行）
        #expect(rows[0].items.count == 3)
        #expect(abs(rows[0].renderedWidth(spacing: 12) - 624) < 1)
        // 第 2 行 2 cell: stretchLastRow 拉伸 → 末 cell 拉宽
        #expect(rows[1].items.count == 2)
        // 末行总宽应 = 800（精确填满）
        #expect(abs(rows[1].renderedWidth(spacing: 12) - 800) < 2)
    }
}
