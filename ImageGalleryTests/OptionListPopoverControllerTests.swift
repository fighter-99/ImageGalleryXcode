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
        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .squareFit)
        var captured: ThumbnailLayoutMode?
        vc.onSelect = { captured = $0 }
        vc.onSelect?(.squareFit)
        #expect(captured == .squareFit)
    }

    @Test func layoutModeAllCasesCountIs2() {
        // V6.12.14: 1 → 2 (.list 加)
        // V6.12.12: 砍 .square 后剩 1 选项 (.squareFit only)
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

    @Test func customOrderIconHasVisualWeight() {
        // V5.87 invariant: customOrder icon 必须有视觉重量 (跟 clock/externaldrive 实心 icon 一致)
        //   之前 line.3.horizontal (3 条细线) 视觉重量不足, 看起来比 clock/externaldrive 小一截
        //   改 arrow.up.arrow.down (有'上下排'语义, 跟 asc/desc 主题一致, 视觉重量相当)
        #expect(SortOption.customOrder.toolbarIcon == "arrow.up.arrow.down",
                "SortOption.customOrder.icon 应是 arrow.up.arrow.down, 实际 \(SortOption.customOrder.toolbarIcon)")
    }

    // MARK: - V5.80: 选中项 bg layer (6% accent) + ✓

    @Test func selectedItemHasVisibleBackgroundLayer() {
        // V5.80: 选中项应加 6% accent bg——找 view hierarchy 中 bg color 非 nil 的 CALayer
        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .squareFit)
        vc.loadView()
        // 递归搜: 找有 backgroundColor 的 CALayer
        let hasBgLayer = findBgLayer(in: vc.view)
        #expect(hasBgLayer,
                "V5.80: 选中项 selectionBackgroundLayer 应有 bg color (6% accent)")
    }

    // MARK: - V5.96 → V5.97: 点选项后 currentItem 立即更新 + row 视觉同步刷新

    @Test func currentItemIsMutableFromInsideClass() {
        // V5.97 invariant: internal(set) var currentItem——同 module 可写 (handleItemClick + 测试)
        //   V5.96 之前是 private(set), 外部 setter 不可达, 测试无法验证刷新逻辑
        //   (V5.96 注释说"用户能看到新选中状态"实际是错的——stored property 赋值不触发重绘)
        let vc1 = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .squareFit)
        #expect(vc1.currentItem == .squareFit)

        // 不同 init 值应存不同 currentItem
        let vc2 = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .squareFit)
        #expect(vc2.currentItem == .squareFit, "V5.97: init(currentItem:) 应存传入值")
    }

    // V5.97 invariant: 切 currentItem → 所有 row 视觉立即同步
    //   V5.96 stored property 赋值不触发 AppKit 重绘——用户报告: 工具栏更新, popover 视觉冻结
    //   V5.97 didSet → refreshSelectionVisuals() 立即遍历 stackView 子视图
    @Test func settingCurrentItemRefreshesRowVisuals() {
        // V6.14.7: 重写 — V6.12.14 删 .square 加 .list, 现 2 case (.squareFit / .list)
        //   之前 V5.97 写的 filter 都用 .squareFit (应该是 .square vs .squareFit), setter 写 .squareFit
        //   (跟初始同值, didSet 不触发) → no-op, 测期待新选中=旧选中矛盾
        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: .squareFit)
        _ = vc.view  // 强制 loadView 跑, 才有 stackView 跟 subviews

        // 初始: .squareFit 选中, .list 取消
        let initialStates = vc._rowStatesForTesting
        #expect(initialStates.count == 2, "V6.12.14: 2 case layoutMode 应出 2 row")
        let initFit = try? #require(initialStates.first { $0.item == .squareFit })
        let initList = try? #require(initialStates.first { $0.item == .list })
        #expect(initFit?.isCheckmarkHidden == false, "V5.97: 初始 .squareFit ✓ 应显示")
        #expect(initFit?.hasSelectionBackground == true, "V5.97: 初始 .squareFit bg 应有 accent")
        #expect(initFit?.iconTintIsAccent == true, "V5.97: 初始 .squareFit icon 应 accent")
        #expect(initList?.isCheckmarkHidden == true, "V5.97: 初始 .list ✓ 应隐藏")
        #expect(initList?.hasSelectionBackground == false, "V5.97: 初始 .list bg 应为空")
        #expect(initList?.iconTintIsAccent == false, "V5.97: 初始 .list icon 应 labelColor")

        // 切到 .list——didSet → refreshSelectionVisuals() 同步刷新
        vc.currentItem = .list

        #expect(vc.currentItem == .list, "V5.97: setter 应存新值")
        let updatedStates = vc._rowStatesForTesting
        let afterFit = try? #require(updatedStates.first { $0.item == .squareFit })
        let afterList = try? #require(updatedStates.first { $0.item == .list })
        #expect(afterFit?.isCheckmarkHidden == true, "V5.97: 旧选中 ✓ 应隐藏")
        #expect(afterFit?.hasSelectionBackground == false, "V5.97: 旧选中 bg 应清空")
        #expect(afterFit?.iconTintIsAccent == false, "V5.97: 旧选中 icon 应变 labelColor")
        #expect(afterList?.isCheckmarkHidden == false, "V5.97: 新选中 ✓ 应显示")
        #expect(afterList?.hasSelectionBackground == true, "V5.97: 新选中 bg 应有 accent")
        #expect(afterList?.iconTintIsAccent == true, "V5.97: 新选中 icon 应变 accent")
    }

    // V5.97 invariant: 4 档 density 刷新也工作——验证 for 循环对多 row 正确
    @Test func settingCurrentItemRefreshesDensityRows() {
        // ThumbnailDensity 4 档 (V5.39.3 4 档)——比 layoutMode 2 档更彻底验证遍历
        let vc = OptionListPopoverController<ThumbnailDensity>(currentItem: .compact)
        _ = vc.view

        // 初始: .compact 选中
        let initialStates = vc._rowStatesForTesting
        #expect(initialStates.count == 4, "V5.97: 4 档 density 应出 4 row")
        let initCompact = try? #require(initialStates.first { $0.item == .compact })
        #expect(initCompact?.isCheckmarkHidden == false, "V5.97: 初始 .compact ✓ 应显示")
        #expect(initCompact?.iconTintIsAccent == true, "V5.97: 初始 .compact icon 应 accent")

        // 切到 .large——其他 3 档应都取消, .large 应选中
        vc.currentItem = .large

        let updated = vc._rowStatesForTesting
        let afterLarge = try? #require(updated.first { $0.item == .large })
        #expect(afterLarge?.isCheckmarkHidden == false, "V5.97: 切到 .large 后 ✓ 应显示")
        #expect(afterLarge?.iconTintIsAccent == true, "V5.97: 切到 .large 后 icon 应 accent")
        #expect(afterLarge?.hasSelectionBackground == true, "V5.97: 切到 .large 后 bg 应有 accent")

        // 其他 3 档 (compact/medium/extraLarge) 视觉应回到 unselected
        for item in ThumbnailDensity.allCases where item != .large {
            let row = try? #require(updated.first { $0.item == item })
            #expect(row?.isCheckmarkHidden == true, "V5.97: 切到 .large 后 \(item) ✓ 应隐藏")
            #expect(row?.iconTintIsAccent == false, "V5.97: 切到 .large 后 \(item) icon 应 labelColor")
            #expect(row?.hasSelectionBackground == false, "V5.97: 切到 .large 后 \(item) bg 应清空")
        }
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
