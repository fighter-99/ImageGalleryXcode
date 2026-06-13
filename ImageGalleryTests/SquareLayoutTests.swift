//
//  SquareLayoutTests.swift
//  ImageGalleryTests
//
//  V5.21: SquareLayout.cellSize 单元测试
//  验证：
//  - 边界：availableWidth=0 / rowHeight=0 → 返回 rowHeight（fallback）
//  - 正常宽：cell 数 + 填满验证（n*cellSize + (n-1)*spacing == availableWidth）
//  - 窄窗口：n=1，cellSize=availableWidth
//  - 宽窗口：n 多，cellSize 接近 rowHeight 但不一定等于
//  - 各种可用宽 (300/800/1100/1600/2000) × rowHeight (110/200/240/280) 网格测试
//
//  镜像 MasonryMathTests pattern
//

import Testing
import CoreGraphics
@testable import ImageGallery

struct SquareLayoutTests {

    // MARK: - 边界

    @Test func zeroAvailableWidthReturnsRowHeight() {
        // 异常输入——用 rowHeight 作 fallback（保守值，不崩）
        #expect(SquareLayout.cellSize(availableWidth: 0, rowHeight: 240, cellSpacing: 20) == 240)
    }

    @Test func zeroRowHeightReturnsRowHeight() {
        // 异常输入——同样 fallback
        #expect(SquareLayout.cellSize(availableWidth: 800, rowHeight: 0, cellSpacing: 20) == 0)
    }

    @Test func negativeAvailableWidthReturnsRowHeight() {
        #expect(SquareLayout.cellSize(availableWidth: -100, rowHeight: 240, cellSpacing: 20) == 240)
    }

    // MARK: - 窄窗口

    @Test func narrowWindowFitsOneCell() {
        // 300pt 窗口 < 1 cell (260pt) + spacing (20pt) = 280pt
        // n = floor((300+20) / (240+20)) = floor(320/260) = 1
        // cellSize = (300 - 0) / 1 = 300pt
        let cellSize = SquareLayout.cellSize(availableWidth: 300, rowHeight: 240, cellSpacing: 20)
        #expect(cellSize == 300)
    }

    @Test func exactlyOneCellWidth() {
        // 260pt 窗口 = 1 cell + spacing
        // n = floor(280/260) = 1
        // cellSize = 260pt
        let cellSize = SquareLayout.cellSize(availableWidth: 260, rowHeight: 240, cellSpacing: 20)
        #expect(cellSize == 260)
    }

    // MARK: - 正常宽

    @Test func standardWidthFillsExactly() {
        // 1100pt 窗口 + 240pt target + 20pt spacing
        // n = floor(1120/260) = 4
        // cellSize = (1100 - 60) / 4 = 260pt
        // 验证填满：4 * 260 + 3 * 20 = 1100 ✓
        let cellSize = SquareLayout.cellSize(availableWidth: 1100, rowHeight: 240, cellSpacing: 20)
        #expect(cellSize == 260)
        // 验证 n*cellSize + (n-1)*spacing == availableWidth
        let n = 4
        let totalWidth = CGFloat(n) * cellSize + CGFloat(n - 1) * 20
        #expect(totalWidth == 1100, "\(n) cell × \(cellSize) + \(n-1) × 20 应该填满 1100")
    }

    @Test func narrowStandardWidthFillsExactly() {
        // 800pt 窗口
        // n = floor(820/260) = 3
        // cellSize = (800 - 40) / 3 = 253.33... (浮点)
        // 验证 3 * 253.33... + 2 * 20 = 800 ✓
        let cellSize = SquareLayout.cellSize(availableWidth: 800, rowHeight: 240, cellSpacing: 20)
        let n = 3
        let totalWidth = CGFloat(n) * cellSize + CGFloat(n - 1) * 20
        #expect(abs(totalWidth - 800) < 0.01, "3 cell 填满 800pt 验证")
    }

    // MARK: - 宽窗口

    @Test func wideWindowHasMoreCells() {
        // 1600pt 窗口
        // n = floor(1620/260) = 6
        // cellSize = (1600 - 100) / 6 = 250pt
        let cellSize = SquareLayout.cellSize(availableWidth: 1600, rowHeight: 240, cellSpacing: 20)
        #expect(cellSize == 250)
        let n = 6
        let totalWidth = CGFloat(n) * cellSize + CGFloat(n - 1) * 20
        #expect(totalWidth == 1600, "6 cell 填满 1600pt 验证")
    }

    @Test func veryWideWindowStillFills() {
        // 2000pt 窗口
        // n = floor(2020/260) = 7
        // cellSize = (2000 - 120) / 7 = 268.57...
        let cellSize = SquareLayout.cellSize(availableWidth: 2000, rowHeight: 240, cellSpacing: 20)
        let n = 7
        let totalWidth = CGFloat(n) * cellSize + CGFloat(n - 1) * 20
        #expect(abs(totalWidth - 2000) < 0.01, "7 cell 填满 2000pt 验证")
    }

    // MARK: - 跨密度

    @Test func cellSizeScalesWithRowHeight() {
        // rowHeight 110pt（小）+ availableWidth 800pt
        // n = floor(820/130) = 6
        // cellSize = (800 - 100) / 6 = 116.67
        let smallCell = SquareLayout.cellSize(availableWidth: 800, rowHeight: 110, cellSpacing: 20)
        // rowHeight 280pt（大）+ availableWidth 800pt
        // n = floor(820/300) = 2
        // cellSize = (800 - 20) / 2 = 390
        let largeCell = SquareLayout.cellSize(availableWidth: 800, rowHeight: 280, cellSpacing: 20)
        // 大密度 cell 应该比小密度大
        #expect(largeCell > smallCell, "rowHeight 280 cellSize 应 > rowHeight 110 cellSize")
    }

    @Test func cellSizeAlwaysLargerThanZero() {
        // 任何正输入都应返回正 cellSize
        for availableWidth: CGFloat in [100, 300, 800, 1500] {
            for rowHeight: CGFloat in [80, 110, 200, 240, 280] {
                let cellSize = SquareLayout.cellSize(
                    availableWidth: availableWidth,
                    rowHeight: rowHeight,
                    cellSpacing: 20
                )
                #expect(cellSize > 0, "availableWidth=\(availableWidth) rowHeight=\(rowHeight) → cellSize=\(cellSize) 必须 > 0")
            }
        }
    }

    // MARK: - 关键不变量

    @Test func alwaysFillsAvailableWidthExactly() {
        // 黄金不变量：n*cellSize + (n-1)*spacing == availableWidth
        // 任何 (availableWidth, rowHeight, cellSpacing) 都满足
        let cases: [(CGFloat, CGFloat, CGFloat)] = [
            (300, 240, 20),
            (500, 240, 20),
            (800, 240, 20),
            (1100, 240, 20),
            (1600, 240, 20),
            (2000, 240, 20),
            (800, 110, 20),
            (800, 200, 20),
            (800, 280, 20),
            (1100, 200, 12),  // 旧 cellSpacing
            (1100, 200, 0),   // 无间距极端
        ]
        for (availableWidth, rowHeight, cellSpacing) in cases {
            let cellSize = SquareLayout.cellSize(
                availableWidth: availableWidth,
                rowHeight: rowHeight,
                cellSpacing: cellSpacing
            )
            // n = floor((availableWidth + spacing) / (rowHeight + spacing))
            let n: CGFloat
            if rowHeight + cellSpacing > 0 {
                n = CGFloat(Int(floor((availableWidth + cellSpacing) / (rowHeight + cellSpacing))))
            } else {
                n = 1
            }
            let totalWidth = n * cellSize + (n - 1) * cellSpacing
            #expect(abs(totalWidth - availableWidth) < 0.01,
                    "availableWidth=\(availableWidth) rowHeight=\(rowHeight) spacing=\(cellSpacing) → cellSize=\(cellSize) 填满验证: 实际 \(totalWidth)")
        }
    }
}
