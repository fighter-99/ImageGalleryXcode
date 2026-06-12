//
//  PopoverItemFactory.swift
//  ImageGallery
//
//  V4.81.0 NEW: 抽 FilterPopoverViewController 内 6 个工厂方法
//    解决单文件 740 行胖 VC 痛点
//    为 Phase 2+ 拆 2 层 popover 重构预备（4 个子 popover 共用这些工厂）
//
//  从 FilterPopoverViewController 抽出的 6 个方法：
//    1. makeCheckItem(label:isOn:action:)           —— V4.36.x #5 范式 + V4.58.0 截断
//    2. makeOneColumnCheckList(items:itemBuilder:) —— V4.63.0 1 列化
//    3. makeSegmentRow()                            —— V4.42.0 segmentGap
//    4. makeIconOnlySegmentItem(...)                —— V4.36.x #1 + V4.68.0 isBordered=false
//    5. makeIconTextSegmentItem(...)                —— V4.45.1 icon + text
//    6. applySegmentStyle(...)                      —— V4.41.1 + V4.62.0 + V4.68.0 + V4.69.0 + V4.72.0 精修
//
//  Why 抽 enum：
//    - 6 个方法都是 static（无状态）——enum 是 Swift 命名空间惯例
//    - 跨 view controller 共用（4 个二级 popover 都需）——不能 fileprivate
//    - ClosureButton 改 internal（去掉 private）——跨文件用
//

import AppKit

/// V4.81.0: popover item 工厂——所有 FilterPopover 子 popover 共用
///   6 个方法都是 static（无状态）——enum 是 Swift 命名空间惯例
enum PopoverItemFactory {

    // MARK: - 1. checkbox + label item

    /// V4.36.x #5 + V4.58.0: checkbox item
    ///   - 统一文字颜色 labelColor（不随 state 变）
    ///   - V4.58.0: cell.lineBreakMode = .byTruncatingMiddle 长名截断
    static func makeCheckItem(
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: label, action: action)
        button.setButtonType(.switch)
        button.state = isOn ? .on : .off
        button.isBordered = false
        // 统一文字颜色（不随 state 变）
        button.contentTintColor = .labelColor
        // V4.58.0: 中间省略号截断（macOS Photos 风格——长文件夹名截中间"旅行照..."）
        button.cell?.lineBreakMode = .byTruncatingMiddle
        button.cell?.truncatesLastVisibleLine = true
        return button
    }

    // MARK: - 2. 1 列 checkbox list 容器

    /// V4.63.0: 1 列 checkbox 列表
    ///   - distribution = .fill 子 view 撑满 VStack 宽度
    ///   - spacing 2pt 1 列时 row 间距紧凑
    static func makeOneColumnCheckList<T: AnyObject, Button: NSButton>(
        items: [T],
        itemBuilder: (T) -> Button
    ) -> NSView {
        let vStack = NSStackView()
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.distribution = .fill  // V4.63.0: 子 view 撑满 VStack 宽度
        vStack.spacing = 2  // V4.63.0: 1 列时 row 间距 2pt 紧凑
        vStack.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            vStack.addArrangedSubview(itemBuilder(item))
        }
        return vStack
    }

    // MARK: - 3. segment row 容器

    /// V4.42.0: 单行 segment——形状段 3 个 icon-only 按钮
    static func makeSegmentRow() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = PopoverStyle.segmentGap
        stack.distribution = .fillEqually
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    // MARK: - 4. icon-only segment item（形状/评分）

    /// V4.36.x #1 + V4.68.0 彻底修: icon-only segment item
    ///   - V4.68.0: isBordered = false 完全去掉 bezel
    ///   - V4.69.0: iconTintOverride 参数——评分段 ⭐ 创建时直接传 .systemYellow
    ///   - V5.5: iconSize 参数——形状段 15pt → 22pt 让 aspect ratio 可见
    static func makeIconOnlySegmentItem(
        icon: String,
        isActive: Bool,
        iconTintOverride: NSColor? = nil,
        iconSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: "", action: action)
        // V4.68.0 彻底修: isBordered = false 完全去掉 bezel 渲染
        button.isBordered = false
        button.bezelStyle = .recessed  // 保留 isBordered=false 时无作用，但 hover/active 视觉仍 work
        applySegmentStyle(button, isActive: isActive, text: nil, symbolName: icon, iconTintOverride: iconTintOverride, iconSize: iconSize)
        return button
    }

    // MARK: - 5. icon + text segment item（V4.45.1 评分段用，V4.46.0 后改用 icon-only）

    /// V4.45.1: icon + text segment item
    ///   评分段改用真 ⭐ SF Symbol "star.fill" + "n+" 文字
    ///   之后 V4.46.0 改为纯 icon-only——本方法保留供未来扩展
    static func makeIconTextSegmentItem(
        icon: String?,
        text: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: "", action: action)
        button.bezelStyle = .recessed
        applySegmentStyle(button, isActive: isActive, text: text, symbolName: icon)
        return button
    }

    // MARK: - 6. apply segment style

    /// V4.41.1 + V4.62.0 + V4.68.0 + V4.69.0 + V4.72.0 + V5.5 精修
    ///   - active: accent bg + 白字/icon
    ///   - inactive: 透明 bg + labelColor icon
    ///   - V4.69.0: paletteColors 链式——评分 ⭐ gold baked
    ///   - V4.72.0: itemFontSize 12pt（item 不是段头）
    ///   - V5.5: iconSize 参数——形状段 15pt → 22pt 让 aspect ratio 可见
    static func applySegmentStyle(
        _ button: NSButton,
        isActive: Bool,
        text: String?,
        symbolName: String? = nil,
        iconTintOverride: NSColor? = nil,
        iconSize: CGFloat? = nil
    ) {
        // 1. 文字：active 白 / inactive labelColor
        if let text = text {
            let color = isActive ? PopoverStyle.activeTextAppKit : PopoverStyle.inactiveTextAppKit
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.systemFont(ofSize: PopoverStyle.itemFontSize, weight: .medium)
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString()
        }

        // 2. icon: paletteColors (V4.69.0 评分 gold) + contentTintColor 路径
        if let symbol = symbolName {
            let usePalette = iconTintOverride != nil
            let sizeConfig = NSImage.SymbolConfiguration(
                pointSize: iconSize ?? PopoverStyle.iconFontSize,
                weight: .medium
            )
            let finalConfig: NSImage.SymbolConfiguration
            if usePalette {
                let palette: [NSColor] = isActive ? [.white] : [iconTintOverride!]
                let paletteConfig = NSImage.SymbolConfiguration(paletteColors: palette)
                finalConfig = sizeConfig.applying(paletteConfig) ?? sizeConfig
            } else {
                finalConfig = sizeConfig
            }
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(finalConfig)
            button.image = img
            // V5.5: scaleProportionallyDown 保 aspect ratio——形状段 22pt 时 rectangle.fill
            //   vs rectangle.portrait.fill 视觉差异可见（之前 15pt 时 5px 差异看不出来）
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            if usePalette {
                button.contentTintColor = nil
            } else {
                let iconColor = isActive ? PopoverStyle.activeTextAppKit : PopoverStyle.inactiveTextAppKit
                button.contentTintColor = iconColor
            }
        } else {
            button.image = nil
        }

        // 3. 背景：V4.68.0 layer 渲染——CALayer 绕过 bezel
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = PopoverStyle.stateTransitionDuration
        button.wantsLayer = true
        button.layer?.backgroundColor = isActive
            ? PopoverStyle.activeBackgroundAppKit.cgColor
            : NSColor.clear.cgColor
        button.layer?.cornerRadius = PopoverStyle.itemCornerRadius
        button.bezelColor = isActive ? PopoverStyle.activeBackgroundAppKit : .clear
        NSAnimationContext.endGrouping()
    }
}

// MARK: - V4.81.0: ClosureButton 改 internal

/// V4.81.0: 改 internal（去掉 private）——PopoverItemFactory 跨文件用
///   NSButton closure 包装——避免 NSButton.action 只能 #selector
final class ClosureButton: NSButton {
    private let actionClosure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.actionClosure = action
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(invoke)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    @objc private func invoke() { actionClosure() }
}
