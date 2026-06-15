//
//  FilterUnifiedPopoverInitialStateTests.swift
//  ImageGalleryTests
//
//  V5.65: 验证 FilterUnifiedPopoverController 初始状态无展开 section (accordion 范式).
//  V5.63-1 误设 expandedSection 默认 .folder, V5.65 改 nil. 测试锁住这个 invariant.
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct FilterUnifiedPopoverInitialStateTests {
    @Test func initStateHasNoExpandedSection() {
        let vc = FilterUnifiedPopoverController(filterState: FilterState())
        #expect(vc.expandedSection == nil)
    }

    @Test func initStateWithNonEmptyFilterStateAlsoCollapsed() {
        // 即便传入有 active filter 的 state, 也不应自动展开对应 section
        let folderID = UUID()
        let state = FilterState(folders: [folderID])
        let vc = FilterUnifiedPopoverController(filterState: state)
        #expect(vc.expandedSection == nil)
    }
}
