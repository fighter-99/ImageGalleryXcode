//
//  OptionListPopoverControllerTests.swift
//  ImageGalleryTests
//
//  V5.77: 通用 OptionListPopoverController<T> 测试——3 个 enum (layoutMode / density / sort) 共享
//  替代 V5.72/V5.74/V5.75 各自 popover test 文件
//  锁住:
//    - init currentItem 存储
//    - onSelect 触发 closure
//    - allCases 数量不变 (V5.39.5 删 masonry, V5.39.3 4 档 density, V5.39.3 7 档 sort)
//    - 3 个 enum 都满足 OptionListItem 协议 (无 type error)
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct OptionListPopoverControllerTests {

    // MARK: - ThumbnailLayoutMode (V5.72 替代)

    @Test func layoutModeInitStoresCurrentItem() {
        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .squareFit)
        #expect(vc.currentItem == .squareFit)
    }

    @Test func layoutModeOnSelectFires() {
        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .square)
        var captured: ThumbnailLayoutMode?
        vc.onSelect = { captured = $0 }
        vc.onSelect?(.squareFit)
        #expect(captured == .squareFit)
    }

    @Test func layoutModeAllCasesCountIs2() {
        // V5.39.5 删 .masonryStretch 后剩 2 选项
        #expect(ThumbnailLayoutMode.allCases.count == 2)
    }

    // MARK: - ThumbnailDensity (V5.74 替代)

    @Test func densityInitStoresCurrentItem() {
        let vc = OptionListPopoverController<ThumbnailDensity>(currentItem: .medium)
        #expect(vc.currentItem == .medium)
    }

    @Test func densityOnSelectFires() {
        let vc = OptionListPopoverController<ThumbnailDensity>(currentItem: .compact)
        var captured: ThumbnailDensity?
        vc.onSelect = { captured = $0 }
        vc.onSelect?(.large)
        #expect(captured == .large)
    }

    @Test func densityAllCasesCountIs4() {
        // V5.39.3 加 4 档 density
        #expect(ThumbnailDensity.allCases.count == 4)
    }

    // MARK: - SortOption (V5.75 替代)

    @Test func sortOptionInitStoresCurrentItem() {
        let vc = OptionListPopoverController<SortOption>(currentItem: .filenameAsc)
        #expect(vc.currentItem == .filenameAsc)
    }

    @Test func sortOptionOnSelectFires() {
        let vc = OptionListPopoverController<SortOption>(currentItem: .importedAtDesc)
        var captured: SortOption?
        vc.onSelect = { captured = $0 }
        vc.onSelect?(.customOrder)
        #expect(captured == .customOrder)
    }

    @Test func sortOptionAllCasesCountIs7() {
        // V5.39.3 加 7 档 sort (3 字段 × 2 方向 + 1 自定义)
        #expect(SortOption.allCases.count == 7)
    }
}
