//
//  OptionListPopoverController.swift
//  ImageGallery
//
//  V5.77 NEW: 通用 option list NSPopover 控制器
//    替代 V5.72 LayoutModePopoverController + V5.74 DensityPopoverController + V5.75 SortOptionPopoverController
//    3 个 ~140 行 popover 重复 99% → 1 个 generic + 3 个 conformance (V5.77 protocol 文件)
//
//  约束: T: OptionListItem (displayName + iconName) + CaseIterable (遍历) + Equatable (识别 current)
//  Visual: 3 层 sandwich (container → NSVisualEffectView.popoverHost → VStack) + ✓ + 24pt item
//  Layout: chevron/badges 永远占位 (V5.76) 防止选中/取消视觉位移
//

import AppKit

/// V5.77: 通用 option list popover——3 行可用, 跟 layoutMode / density / sort popover 视觉一致
///   Photos 范式: 工具栏单按钮单 popover, 选中 accent color + ✓ 标记
final class OptionListPopoverController<T: OptionListItem>: NSViewController {
    /// V5.77: 用户选项回调——caller 写入 UserSettings + 更新 toolbar icon
    var onSelect: ((T) -> Void)?

    /// V5.77: 当前选中的 item——画 ✓ + accent 前景
    private(set) var currentItem: T

    /// V5.77: popover 最小宽度 (默认 140, sort 用 160 因 7 选项 label 较长)
    private let minWidth: CGFloat

    private let stackView: NSStackView

    init(currentItem: T, minWidth: CGFloat = 140) {
        self.currentItem = currentItem
        self.minWidth = minWidth
        self.stackView = NSStackView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func loadView() {
        // V5.77: 3 层 sandwich 仿 V5.72 + nspopover-tamc-sandwich pattern
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for item in T.allCases {
            let row = makeOptionItem(for: item)
            stackView.addArrangedSubview(row)
        }

        visualEffect.addSubview(stackView)
        container.addSubview(visualEffect)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -4)
        ])

        self.view = container
    }

    /// V5.77: 单个选项 (icon + label + ✓) 24pt 高——V5.76 count badge always-occupy
    ///   锁 layout 永远不变, 选中/取消无视觉位移
    /// V5.80: 选中项加 6% accent bg 视觉高亮——之前只切 icon/label accent color, 加 bg 一眼看出选中
    private func makeOptionItem(for item: T) -> NSView {
        let rowView = OptionItemView(item: item)
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.wantsLayer = true  // V5.80: bg layer 需要 rowView 是 layer-backed

        let isSelected = item == currentItem

        // V5.80: 选中背景层 (6% accent, 4pt 圆角, 2pt 边距内缩)
        //   加在 rowView 底层 (icon/label/checkmark 上层), 选中时才显示
        let bgLayer = CALayer()
        bgLayer.cornerRadius = 4
        bgLayer.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
            : nil
        rowView.layer?.addSublayer(bgLayer)
        // 存 bgLayer 到 rowView, layout 时更新 frame
        rowView.selectionBackgroundLayer = bgLayer

        let icon = NSImageView(image: NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = isSelected ? .controlAccentColor : .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: item.displayName)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = isSelected ? .controlAccentColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = NSTextField(labelWithString: "✓")
        // V5.86: 12pt → 16pt 跟 icon (16x16) 匹配——macOS Photos 选中态风格
        //   之前 12pt 视觉比 icon 小 4pt, 看起来 icon/checkmark 视觉权重不一致
        //   现在 2-tier hierarchy: icon+checkmark 同 16pt, label 13pt
        checkmark.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        checkmark.textColor = .controlAccentColor
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.isHidden = !isSelected

        rowView.addSubview(icon)
        rowView.addSubview(label)
        rowView.addSubview(checkmark)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleItemClick(_:)))
        rowView.addGestureRecognizer(click)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),

            checkmark.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -4),
            checkmark.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 16),

            rowView.heightAnchor.constraint(equalToConstant: 24),
            rowView.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth)
        ])

        return rowView
    }

    @objc private func handleItemClick(_ sender: NSClickGestureRecognizer) {
        guard let rowView = sender.view as? OptionItemView<T> else { return }
        let selectedItem = rowView.item
        // V5.96: 立即更新 currentItem——body 重渲染,新选项显示 6% accent bg + accent icon + ✓
        //   之前 dismiss 在 body 重渲染前调用,用户看不到新选中(下次开 popover 才看到)
        currentItem = selectedItem
        onSelect?(selectedItem)
        // V5.96: 0.15s 延迟 dismiss——让用户看到新选中状态再关闭(Photos 范式)
        //   0.15s 视觉感知阈值: < 0.1s 用户感觉不到, 0.1-0.2s 刚好"闪过"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.view.window?.contentViewController?.dismiss(nil)
        }
    }
}

/// V5.77: 内部 generic NSView subclass 存 item (NSView.tag 是 readonly)
/// V5.80: 加 selectionBackgroundLayer 引用 + layout override 更新 bg frame
private final class OptionItemView<T: OptionListItem>: NSView {
    let item: T
    /// V5.80: 选中背景层 (6% accent bg) 引用——在 layout() 时更新 frame
    var selectionBackgroundLayer: CALayer?

    init(item: T) {
        self.item = item
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not implemented") }

    /// V5.80: layout 时更新 bg layer frame——inset 2pt 边距 + 4pt 圆角
    override func layout() {
        super.layout()
        selectionBackgroundLayer?.frame = bounds.insetBy(dx: 2, dy: 2)
    }
}
