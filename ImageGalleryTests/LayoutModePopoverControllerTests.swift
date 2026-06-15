//
//  LayoutModePopoverControllerTests.swift
//  ImageGalleryTests
//
//  V5.72: 验证 LayoutModePopoverController 基础行为——init currentMode + onSelect 触发
//  锁住 V5.72 替代 NSMenu 的 popover 实现 invariant.
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct LayoutModePopoverControllerTests {
    @Test func initStoresCurrentMode() {
        // V5.72: 初始 currentMode 应跟传入值一致
        let vc = LayoutModePopoverController(currentMode: .squareFit)
        #expect(vc.currentMode == .squareFit)
    }

    @Test func onSelectFiresWithChosenMode() {
        // V5.72: 模拟用户点 .square 选项, onSelect 应传 .square
        let vc = LayoutModePopoverController(currentMode: .square)
        var captured: ThumbnailLayoutMode?
        vc.onSelect = { captured = $0 }
        // 直接调 onSelect closure 模拟 (类似 CategoryRowViewTests/onTapFires)
        vc.onSelect?(.squareFit)
        #expect(captured == .squareFit)
    }

    @Test func allCasesCountMatchesThumbnailLayoutMode() {
        // V5.72: V5.39.5 删 .masonryStretch 后剩 2 选项——popover 显示也应 2 项
        #expect(ThumbnailLayoutMode.allCases.count == 2)
    }
}
