//
//  PopoverStyleTokensTests.swift
//  ImageGalleryTests
//
//  V5.13：DesignTokens 静态 token 验证——间距/圆角/popover 视觉/工具栏/侧栏。
//  Token 是 V4.41-V4.79 视觉迭代沉淀，数字背后是 macOS Photos 紧凑感对齐决策，
//  测试锁住这些数字防意外改动。
//

import Testing
import SwiftUI
import AppKit
@testable import ImageGallery

struct PopoverStyleTokensTests {
    // MARK: - Spacing 间距系统

    @Test func spacingTokensAreFourMultiples() {
        #expect(Spacing.xs == 4)
        #expect(Spacing.sm == 8)
        #expect(Spacing.md == 12)
        #expect(Spacing.lg == 16)
        #expect(Spacing.xl == 20)
        #expect(Spacing.xxl == 24)
    }

    // MARK: - Radius 圆角系统

    @Test func radiusTokensAreCorrect() {
        #expect(Radius.sm == 6)
        #expect(Radius.md == 8)
        #expect(Radius.lg == 12)
        #expect(Radius.thumb == 8)  // V5.39.1: 0 → 8 (selection 框正方形 + square/masonry 圆角统一)
    }

    // MARK: - PopoverStyle 布局

    // V6.28 cleanup: popoverLayoutTokensMatchVersionedDecisions 删 (引用 V6.23 已删 dead tokens
    //   width/padding/columnGap — 0 caller, V6.23 dead code 清理时已删 token)
    //   sectionSpacing 仍 valid (10pt) — V4.64.0 紧凑感, 由其他 test 间接覆盖

    // MARK: - PopoverStyle item 高度/圆角/字号

    @Test func popoverItemTokensArePhotosCompact() {
        #expect(PopoverStyle.itemHeight == 24)         // V4.71.0
        #expect(PopoverStyle.itemCornerRadius == 4)    // V4.64.0
        #expect(PopoverStyle.itemFontSize == 12)       // V4.72.0
        #expect(PopoverStyle.iconFontSize == 15)       // V4.64.0
        #expect(PopoverStyle.sortItemFontSize == 13)   // V4.64.0
    }

    // MARK: - PopoverStyle 段头

    // V6.28 cleanup: popoverHeaderTokens 删 3 行 (headerFontSize/headerIconSize/headerIconSpacing)
    //   3 个 token V6.23 dead code 清理时已删 (注释自己说"未用")
    //   保留 headerUppercased + headerSeparatorHeight 验证
    @Test func popoverHeaderTokens() {
        #expect(PopoverStyle.headerUppercased == true)
        #expect(PopoverStyle.headerSeparatorHeight == 1)  // V4.53.0
    }

    // MARK: - PopoverStyle item padding + 段内间距

    @Test func popoverSegmentGapTokens() {
        #expect(PopoverStyle.segmentGap == 6)             // V4.42.0
        #expect(PopoverStyle.columnRowGap == 4)           // V4.42.0
        #expect(PopoverStyle.itemVerticalPadding == 6)    // V4.52.0
        #expect(PopoverStyle.itemHorizontalPadding == 8)  // V4.52.0
    }

    // MARK: - PopoverStyle 状态过渡 + host 圆角边框

    @Test func popoverHostAndTransitionTokens() {
        #expect(PopoverStyle.stateTransitionDuration == 0.15)  // V4.43.1
        #expect(PopoverStyle.hostCornerRadius == 12)           // V4.79.0
        #expect(PopoverStyle.hostBorderWidth == 0.5)           // V4.67.0
    }

    // MARK: - PopoverStyle 4 类别行专用（V4.79.0 NEW）

    @Test func popoverCategoryRowTokens() {
        #expect(PopoverStyle.categoryRowHeight == 40)              // V5.63-3: 32 → 40
        #expect(PopoverStyle.categoryRowIconSize == 15)
        #expect(PopoverStyle.categoryRowChevronSize == 9)
        #expect(PopoverStyle.categoryRowCountBadgeSize == 10)      // V5.63-3: 11 → 10
        #expect(PopoverStyle.categoryRowCountBadgeHeight == 16)
        #expect(PopoverStyle.categoryRowCountBadgeOpacity == 0.10)  // V5.63-3: 0.12 → 0.10
    }

    // MARK: - ToolbarStyle

    @Test func toolbarStyleTokens() {
        #expect(ToolbarStyle.height == 52)
        #expect(ToolbarStyle.heightCompact == 28)  // V4.0.2
        #expect(ToolbarStyle.spacing == 8)
    }

    // MARK: - SidebarStyle 行 + icon

    @Test func sidebarStyleRowTokens() {
        #expect(SidebarStyle.rowHeight == 28)
        #expect(SidebarStyle.rowHorizontalPadding == 8)
        #expect(SidebarStyle.rowBackgroundInset == 4)
        #expect(SidebarStyle.rowCornerRadius == Radius.sm)  // 与其他 UI 统一
        #expect(SidebarStyle.rowIconTextSpacing == 8)
        #expect(SidebarStyle.rowTextCountSpacing == 4)
    }

    @Test func sidebarStyleIconTokens() {
        #expect(SidebarStyle.iconSize == 13)
        #expect(SidebarStyle.iconFrameWidth == 18)
    }

    // MARK: - SearchFieldMetrics + StatusBarMetrics + WindowChrome

    @Test func searchAndStatusBarMetrics() {
        #expect(SearchFieldMetrics.width == 150)         // V5.81: 180 → 150
        #expect(SearchFieldMetrics.widthExpanded == 360)
        #expect(SearchFieldMetrics.height == 30)
        #expect(StatusBarMetrics.height == 24)
        #expect(StatusBarMetrics.progressBarHeight == 3)
        #expect(StatusBarMetrics.popoverWidth == 360)
    }

    @Test func windowChromeAndModeMetrics() {
        #expect(WindowChrome.topInset == 0)
        #expect(WindowChrome.navButtonPadding == 12)
        #expect(WindowModeMetrics.viewerToolbarHeight == 32)
        #expect(WindowModeMetrics.viewerImagePadding == 40)
    }

    // MARK: - SidebarStyle 智能 folder 语义色

    @Test func sidebarStyleIconColorsAreFiveDistinctColors() {
        // 色板：HLS 60°+ 间隔（橙/蓝/紫/橙重复——4 类别中 trash 复用 orange）
        // V5.8 砍 iconColorFavorite 后剩 4 个色（duplicate/recent/large/trash）
        // 这里只验 duplicate ≠ recent ≠ large（避免重复用 orange）
        #expect(SidebarStyle.iconColorDuplicate != SidebarStyle.iconColorRecent)
        #expect(SidebarStyle.iconColorRecent != SidebarStyle.iconColorLarge)
        #expect(SidebarStyle.iconColorDuplicate != SidebarStyle.iconColorLarge)
    }
}
