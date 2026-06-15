//
//  CategoryRowViewChevronSwapTests.swift
//  ImageGalleryTests
//
//  V5.68: 验证 chevron image swap 行为——applyChevronSymbol 后 currentChevronSymbol 立即更新.
//  修 V5.68 bug 'chevron 旋转视觉左移'——frameCenterRotation 0°→90° 让用户感知像箭头移,
//  改 image swap (chevron.right ↔ chevron.down) Photos 风格.
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct CategoryRowViewChevronSwapTests {
    @Test func initStateHasRightChevron() {
        // V5.68: init 时 currentChevronSymbol 默认 chevron.right
        let row = CategoryRowView(category: .folder)
        #expect(row.currentChevronSymbol == "chevron.right")
    }

    @Test func applyChevronSymbolUpdatesCurrentSymbol() {
        let row = CategoryRowView(category: .folder)
        row.applyChevronSymbol("chevron.down")
        #expect(row.currentChevronSymbol == "chevron.down")

        row.applyChevronSymbol("chevron.right")
        #expect(row.currentChevronSymbol == "chevron.right")
    }
}
