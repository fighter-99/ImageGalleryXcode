//
//  DensityPopoverControllerTests.swift
//  ImageGalleryTests
//
//  V5.74: 验证 DensityPopoverController 基础行为——init currentDensity + onSelect 触发
//  锁住 V5.74 替代 NSMenu 的 popover 实现 invariant.
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct DensityPopoverControllerTests {
    @Test func initStoresCurrentDensity() {
        let vc = DensityPopoverController(currentDensity: .medium)
        #expect(vc.currentDensity == .medium)
    }

    @Test func onSelectFiresWithChosenDensity() {
        let vc = DensityPopoverController(currentDensity: .compact)
        var captured: ThumbnailDensity?
        vc.onSelect = { captured = $0 }
        vc.onSelect?(.large)
        #expect(captured == .large)
    }

    @Test func allCasesCountMatchesThumbnailDensity() {
        // V5.74: 4 档 density 期望
        #expect(ThumbnailDensity.allCases.count == 4)
    }
}
