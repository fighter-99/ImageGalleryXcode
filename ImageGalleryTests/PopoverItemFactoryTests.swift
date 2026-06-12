//
//  PopoverItemFactoryTests.swift
//  ImageGalleryTests
//
//  V5.13：PopoverItemFactory 6 工厂方法测试（V4.81.0 抽）。
//  测 button 类型/isBordered/tintColor/action 触发 + 容器 stack 配置。
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct PopoverItemFactoryTests {
    // MARK: - 1. makeCheckItem

    @Test func makeCheckItemIsSwitchTypeAndNotBordered() {
        let button = PopoverItemFactory.makeCheckItem(
            label: "测试",
            isOn: true,
            action: {}
        )
        // V4.36.x #5: 强制 isBordered = false 绕 AppKit bezel 渲染
        #expect(button.isBordered == false)
        // switch type（checkbox）—— 通过 state + cell 行为验证
        //   注：NSButton.ButtonType 在 Swift overlay 未暴露 getter
        //   用 cell 存在 + state 行为作 invariant
        #expect(button.cell != nil)
        // state = on
        #expect(button.state == .on)
        // title 保留 label
        #expect(button.title == "测试")
    }

    @Test func makeCheckItemIsOffState() {
        let button = PopoverItemFactory.makeCheckItem(
            label: "off",
            isOn: false,
            action: {}
        )
        #expect(button.state == .off)
    }

    @Test func makeCheckItemHasUniformLabelColor() {
        // 统一文字颜色 labelColor（不随 state 变）——V4.36.x #5 范式
        let buttonOn = PopoverItemFactory.makeCheckItem(label: "a", isOn: true, action: {})
        let buttonOff = PopoverItemFactory.makeCheckItem(label: "a", isOn: false, action: {})
        #expect(buttonOn.contentTintColor == .labelColor)
        #expect(buttonOff.contentTintColor == .labelColor)
    }

    @Test func makeCheckItemTruncatesLongTextMiddle() {
        // V4.58.0: cell.lineBreakMode = .byTruncatingMiddle
        let button = PopoverItemFactory.makeCheckItem(
            label: "很长的文件夹名会被中间省略号截断",
            isOn: false,
            action: {}
        )
        #expect(button.cell?.lineBreakMode == .byTruncatingMiddle)
        #expect(button.cell?.truncatesLastVisibleLine == true)
    }

    @Test func makeCheckItemActionClosureFires() {
        // action 触发 closure
        var called = false
        let button = PopoverItemFactory.makeCheckItem(label: "x", isOn: false) {
            called = true
        }
        // 验 wiring：target 是 button 自身 + action selector 存在
        #expect(button.target === button)
        #expect(button.action != nil)
        // perform action selector on target —— ClosureButton.invoke 是 @objc 可 perform
        _ = button.perform(button.action!)
        #expect(called == true)
    }

    // MARK: - 2. makeOneColumnCheckList

    @Test func makeOneColumnCheckListIsVerticalStackWithFillDistribution() throws {
        // V4.63.0: 1 列化——orientation = .vertical, distribution = .fill, spacing = 2
        // T 必须是 AnyObject——用 NSString 包装
        let items: [NSString] = ["a", "b", "c"].map { $0 as NSString }
        let view = PopoverItemFactory.makeOneColumnCheckList(items: items) { s in
            NSButton(title: s as String, target: nil, action: nil)
        }
        // 签名返回 NSView，需 cast NSStackView
        let vStack = try #require(view as? NSStackView)
        #expect(vStack.orientation == .vertical)
        #expect(vStack.alignment == .leading)
        #expect(vStack.distribution == .fill)
        #expect(vStack.spacing == 2)
    }

    @Test func makeOneColumnCheckListBuildsNItems() throws {
        // items.count == N → vStack 包含 N 个 arrangedSubview
        let items: [NSString] = ["a", "b", "c", "d", "e"].map { $0 as NSString }
        let view = PopoverItemFactory.makeOneColumnCheckList(items: items) { s in
            NSButton(title: s as String, target: nil, action: nil)
        }
        let vStack = try #require(view as? NSStackView)
        #expect(vStack.arrangedSubviews.count == 5)
    }

    // MARK: - 3. makeSegmentRow

    @Test func makeSegmentRowIsHorizontalFillEqually() {
        // V4.42.0: 形状段 3 个 icon-only 按钮，分布均匀
        let stack = PopoverItemFactory.makeSegmentRow()
        #expect(stack.orientation == .horizontal)
        #expect(stack.distribution == .fillEqually)
        #expect(stack.alignment == .centerY)
        #expect(stack.spacing == PopoverStyle.segmentGap)  // 6pt
    }

    // MARK: - 4. makeIconOnlySegmentItem

    @Test func makeIconOnlySegmentItemIsNotBordered() {
        // V4.68.0: isBordered = false 完全去掉 bezel 渲染
        let button = PopoverItemFactory.makeIconOnlySegmentItem(
            icon: "star",
            isActive: true,
            action: {}
        )
        #expect(button.isBordered == false)
    }

    @Test func makeIconOnlySegmentItemActiveSetsAccentBackground() {
        // applySegmentStyle active 路径：layer.backgroundColor = active accent
        let button = PopoverItemFactory.makeIconOnlySegmentItem(
            icon: "star",
            isActive: true,
            action: {}
        )
        // wantsLayer 必须 true（applySegmentStyle 设）
        #expect(button.wantsLayer == true)
        // layer cornerRadius = itemCornerRadius (4pt)
        #expect(button.layer?.cornerRadius == PopoverStyle.itemCornerRadius)
        // background 是 accent
        #expect(button.layer?.backgroundColor == PopoverStyle.activeBackgroundAppKit.cgColor)
    }

    @Test func makeIconOnlySegmentItemInactiveHasClearBackground() {
        let button = PopoverItemFactory.makeIconOnlySegmentItem(
            icon: "star",
            isActive: false,
            action: {}
        )
        #expect(button.layer?.backgroundColor == NSColor.clear.cgColor)
    }

    // MARK: - 6. applySegmentStyle

    @Test func applySegmentStyleWithIconTintOverrideUsesPalette() {
        // V4.69.0: 评分 ⭐ iconTintOverride 用 paletteColors 路径（gold baked）
        let button = NSButton()
        PopoverItemFactory.applySegmentStyle(
            button,
            isActive: false,
            text: nil,
            symbolName: "star.fill",
            iconTintOverride: .systemYellow
        )
        // paletteColors 路径下 contentTintColor 设为 nil（让 palette 接管）
        #expect(button.contentTintColor == nil)
        // image 已设置
        #expect(button.image != nil)
    }

    @Test func applySegmentStyleWithoutOverrideUsesContentTint() {
        // 非 paletteColors 路径下 contentTintColor = labelColor (inactive)
        let button = NSButton()
        PopoverItemFactory.applySegmentStyle(
            button,
            isActive: false,
            text: nil,
            symbolName: "rectangle",
            iconTintOverride: nil
        )
        #expect(button.contentTintColor == PopoverStyle.inactiveTextAppKit)
        #expect(button.image != nil)
    }
}
