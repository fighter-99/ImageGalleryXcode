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

    @Test func sortOptionIconNameMatchesToolbarIcon() {
        // V5.78 invariant: SortOption 的 OptionListItem.iconName 必须 = toolbarIcon
        //   锁住不再手抖用 directionIcon (V5.75 回归 bug, 6 个选项全 up/down 箭头看不出字段)
        for option in SortOption.allCases {
            #expect(option.iconName == option.toolbarIcon,
                    "SortOption.\(option).iconName (\(option.iconName)) != toolbarIcon (\(option.toolbarIcon))")
        }
    }

    // MARK: - V5.80: 选中项 bg layer (6% accent) + ✓

    @Test func selectedItemHasVisibleBackgroundLayer() {
        // V5.80: 选中项应加 6% accent bg——找 view hierarchy 中 bg color 非 nil 的 CALayer
        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .square)
        vc.loadView()
        // 递归搜: 找有 backgroundColor 的 CALayer
        let hasBgLayer = findBgLayer(in: vc.view)
        #expect(hasBgLayer,
                "V5.80: 选中项 selectionBackgroundLayer 应有 bg color (6% accent)")
    }

    /// V5.80: 递归搜 view 找 backgroundColor 非 nil 的 CALayer
    private func findBgLayer(in view: NSView) -> Bool {
        if let bg = view.layer?.backgroundColor, bg != nil { return true }
        for sublayer in view.layer?.sublayers ?? [] {
            if sublayer.backgroundColor != nil { return true }
        }
        for subview in view.subviews {
            if findBgLayer(in: subview) { return true }
        }
        return false
    }
}
