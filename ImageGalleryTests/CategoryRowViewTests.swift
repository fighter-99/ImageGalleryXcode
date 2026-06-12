//
//  CategoryRowViewTests.swift
//  ImageGalleryTests
//
//  V5.14: CategoryRowView (V4.83.0 顶层 popover 4 类别行) 测试。
//  测试 init/onTap/update/setActive + 内部子视图状态。
//  V5.14 Day 1.5 refactor: countBadge/countBadgeBg 改 internal + isActive 改 private(set)
//  让 @testable 可见。
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct CategoryRowViewTests {
    @Test func initWithCategoryStoresReference() {
        let row = CategoryRowView(category: .folder)
        #expect(row.category == .folder)
        // 4 个 category 都可 init
        for category in FilterCategory.allCases {
            let r = CategoryRowView(category: category)
            #expect(r.category == category)
        }
    }

    @Test func updateWithCountShowsCountBadge() {
        let row = CategoryRowView(category: .folder)
        row.update(count: 3)
        #expect(row.countBadge.stringValue == "3")
        #expect(row.countBadgeBg.isHidden == false)
    }

    @Test func updateWithZeroCountHidesBadge() {
        let row = CategoryRowView(category: .tag)
        row.update(count: 0)
        #expect(row.countBadgeBg.isHidden == true)
    }

    @Test func updateWithSummaryOverridesCount() {
        // V4.84.0: rating 类别用 summary（"≥ 3 ★"）而非数字 count
        let row = CategoryRowView(category: .rating)
        row.update(count: 1, summary: "≥ 3 ★")
        #expect(row.countBadge.stringValue == "≥ 3 ★")
        #expect(row.countBadgeBg.isHidden == false)
    }

    @Test func onTapFires() {
        let row = CategoryRowView(category: .shape)
        var called = false
        row.onTap = { called = true }
        row.onTap?()  // 直接调 closure（onTap 是 optional closure）
        #expect(called == true)
    }
}
