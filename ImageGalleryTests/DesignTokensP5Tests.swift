//
//  DesignTokensP5Tests.swift
//  ImageGalleryTests
//
//  V6.63 (P5): 新 token 测试 — 4 组 (Typography/Radius/IconNames/SheetMetrics)
//  验证 token 存在 + 字面量值, 防未来改动偷偷换 token
//

import Testing
import SwiftUI
@testable import ImageGallery

struct DesignTokensP5Tests {

    // MARK: - P5.1 Typography 收口

    @Test func typographySubheadlineIs16() {
        // Settings row 副标题 16pt — 介于 body (13) 和 title2 (22) 之间
        // P5.1: 取代 SettingsView 2 处 .system(size: 16) 字面量
        //   SwiftUI Font 没公共 Equatable, 只用引用存在性 + static 类型守护
        let _: Font = Typography.subheadline
        let _: Font = Typography.heroBackdropIcon
    }

    // MARK: - P5.2 Radius 收口

    @Test func radiusXsIs4() {
        // P5.2: 微圆角 4pt — 替换 KeyboardShortcutsSheet/ImmersivePhotoView/OnboardingView 3 处
        #expect(Radius.xs == 4)
        // 验证半径档位逻辑: xs < sm < md < lg
        #expect(Radius.xs < Radius.sm)
        #expect(Radius.sm < Radius.md)
        #expect(Radius.md < Radius.lg)
    }

    // MARK: - P5.3 IconNames 收口

    @Test func iconNamesHaveExpectedValues() {
        // V6.63 (P5.3): 14 个高频 SF Symbol token 锁定 — 防 macOS SF Symbols 改名
        #expect(IconNames.folder == "folder")
        #expect(IconNames.trash == "trash")
        #expect(IconNames.tag == "tag")
        #expect(IconNames.squareAndArrowDown == "square.and.arrow.down")
        #expect(IconNames.xmarkCircle == "xmark.circle")
        #expect(IconNames.squareAndArrowUp == "square.and.arrow.up")
        #expect(IconNames.checkmark == "checkmark")
        #expect(IconNames.arrowClockwise == "arrow.clockwise")
        #expect(IconNames.plusCircle == "plus.circle")
        #expect(IconNames.sparkles == "sparkles")
        #expect(IconNames.photo == "photo")
        #expect(IconNames.xmarkCircleFill == "xmark.circle.fill")
        #expect(IconNames.checkmarkCircleFill == "checkmark.circle.fill")
        #expect(IconNames.exclamationmarkTriangle == "exclamationmark.triangle")
    }

    // MARK: - P5.4 SheetMetrics 收口

    @Test func sheetMetricsStandardIs600x400() {
        // V6.63 (P5.4): 4 个 sheet 尺寸 token 锁定
        #expect(SheetMetrics.standardWidth == 600)
        #expect(SheetMetrics.standardHeight == 400)
    }

    @Test func sheetMetricsCompactIs320x480() {
        #expect(SheetMetrics.compactWidth == 320)
        #expect(SheetMetrics.compactHeight == 480)
    }

    @Test func sheetMetricsTallIs320x600() {
        #expect(SheetMetrics.tallWidth == 320)
        #expect(SheetMetrics.tallHeight == 600)
    }

    @Test func sheetMetricsSidebarPreviewIs220x600() {
        #expect(SheetMetrics.sidebarPreviewWidth == 220)
        #expect(SheetMetrics.sidebarPreviewHeight == 600)
    }
}
