//
//  TagFilterToggleTests.swift
//  ImageGalleryTests
//
//  V5.14: TagFilterPopoverController.handleToggle 测试。
//  V4.87.0 行为：NSScrollView 兜底 + V4.81 1 列 checkbox list + V4.80 NSVisualEffectView 包裹。
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct TagFilterToggleTests {
    @Test func handleToggleAddsTagIdToFilterState() {
        let vc = TagFilterPopoverController(filterState: FilterState(), tags: [])
        let tagID = UUID()
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(tagID)
        #expect(captured?.tags.contains(tagID) == true)
    }

    @Test func handleToggleRemovesExistingTagId() {
        let tagID = UUID()
        let vc = TagFilterPopoverController(
            filterState: FilterState(tags: [tagID]),
            tags: []
        )
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(tagID)
        #expect(captured?.tags.contains(tagID) == false)
    }

    @Test func handleToggleOnEmptyStartsWithInsert() {
        let vc = TagFilterPopoverController(filterState: FilterState(), tags: [])
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(UUID())
        #expect(captured?.tags.count == 1)
    }

    @Test func handleToggleFiresOnStateChange() {
        let vc = TagFilterPopoverController(filterState: FilterState(), tags: [])
        var callCount = 0
        vc.onStateChange = { _ in callCount += 1 }
        vc.handleToggle(UUID())
        #expect(callCount == 1)
    }

    @Test func handleToggleMultipleTagsTogglesIndependently() {
        let a = UUID(), b = UUID(), c = UUID()
        let vc = TagFilterPopoverController(filterState: FilterState(), tags: [])
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(a)
        vc.handleToggle(b)
        vc.handleToggle(c)
        #expect(captured?.tags == [a, b, c])
    }

    @Test func handleToggleTwiceRemovesFromState() {
        let tagID = UUID()
        let vc = TagFilterPopoverController(filterState: FilterState(), tags: [])
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(tagID)
        vc.handleToggle(tagID)
        #expect(captured?.tags.isEmpty == true)
    }
}
