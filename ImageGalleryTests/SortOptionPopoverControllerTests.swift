//
//  SortOptionPopoverControllerTests.swift
//  ImageGalleryTests
//
//  V5.75: 验证 SortOptionPopoverController 基础行为——init currentOption + onSelect 触发
//  锁住 V5.75 替代 NSMenu 的 popover 实现 invariant.
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct SortOptionPopoverControllerTests {
    @Test func initStoresCurrentOption() {
        let vc = SortOptionPopoverController(currentOption: .filenameAsc)
        #expect(vc.currentOption == .filenameAsc)
    }

    @Test func onSelectFiresWithChosenOption() {
        let vc = SortOptionPopoverController(currentOption: .importedAtDesc)
        var captured: SortOption?
        vc.onSelect = { captured = $0 }
        vc.onSelect?(.customOrder)
        #expect(captured == .customOrder)
    }

    @Test func allCasesCountMatchesSortOption() {
        // V5.75: 7 种排序 (3 字段 × 2 方向 + 1 自定义)
        #expect(SortOption.allCases.count == 7)
    }
}
