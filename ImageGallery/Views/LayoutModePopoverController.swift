//
//  LayoutModePopoverController.swift
//  ImageGallery
//
//  V5.72 NEW: 工具栏 layoutMode 按钮 NSPopover
//    仿 Photos 单按钮单 popover 范式 (跟 filter popover V5.63-1 风格统一)
//    替代 V5.39.3 NSMenu 实现——统一视觉 (transl material + 圆角 + checkmark)
//    2 选项: .square (方格 1:1 居中裁切) / .squareFit (按比例 1:1 letterbox)
//
//  V5.72 范围: 仅 layoutMode, pilot 验证 pattern. V5.73/V5.74 扩到 density/sort.
//

import AppKit

/// V5.72: 工具栏 layoutMode 按钮的 popover 控制器
///   2 选项 (square / squareFit) 单选, 仿 Photos 风格
final class LayoutModePopoverController: NSViewController {
    /// V5.72: 用户选项回调——caller 写入 UserSettings + 更新 toolbar icon
    var onSelect: ((ThumbnailLayoutMode) -> Void)?

    /// V5.72: 当前选中的 layoutMode——画 checkmark
    private(set) var currentMode: ThumbnailLayoutMode

    // MARK: - 子视图

    private let stackView: NSStackView

    // MARK: - init

    init(currentMode: ThumbnailLayoutMode) {
        self.currentMode = currentMode
        self.stackView = NSStackView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V5.72: 3 层 sandwich 仿 filter popover + nspopover-tamc-sandwich pattern
        //   container → visualEffect → stack
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2  // V5.72: 2pt 紧凑 (Photos 选项间距)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // 填充 2 个选项
        for mode in ThumbnailLayoutMode.allCases {
            let item = makeOptionItem(for: mode)
            stackView.addArrangedSubview(item)
        }

        visualEffect.addSubview(stackView)
        container.addSubview(visualEffect)

        NSLayoutConstraint.activate([
            // 2. visualEffect 撑满 container
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 3. stackView 12pt padding (V5.63-4 sectionContentPadding) + 4pt 上下
            stackView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -4)
        ])

        self.view = container
    }

    /// V5.72: 单个选项 (icon + label + checkmark) 28pt 高
    private func makeOptionItem(for mode: ThumbnailLayoutMode) -> NSView {
        let item = LayoutModeOptionItem(mode: mode)
        item.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: mode.icon, accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = mode == currentMode ? .controlAccentColor : .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: mode.displayName)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = mode == currentMode ? .controlAccentColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        // V5.72: 选中时画 ✓ 标记, 未选中不显示 (24pt 宽预留空间)
        let checkmark = NSTextField(labelWithString: "✓")
        checkmark.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        checkmark.textColor = .controlAccentColor
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.isHidden = mode != currentMode

        item.addSubview(icon)
        item.addSubview(label)
        item.addSubview(checkmark)

        // 整 item 可点击——row click 触发 onSelect
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleItemClick(_:)))
        item.addGestureRecognizer(click)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: item.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: item.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: item.centerYAnchor),

            checkmark.trailingAnchor.constraint(equalTo: item.trailingAnchor, constant: -4),
            checkmark.centerYAnchor.constraint(equalTo: item.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 16),

            item.heightAnchor.constraint(equalToConstant: 24),  // V5.72: 24pt 紧凑 item
            item.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])

        return item
    }

    // MARK: - 事件

    /// V5.72: 点 item 触发 onSelect + 关闭 popover
    @objc private func handleItemClick(_ sender: NSClickGestureRecognizer) {
        guard let item = sender.view as? LayoutModeOptionItem else { return }
        onSelect?(item.mode)
        // 关闭 popover——找最近的 NSPopover
        view.window?.contentViewController?.dismiss(nil)
    }
}

/// V5.72: 内部 NSView subclass 存 mode (NSView.tag 是 readonly)
private final class LayoutModeOptionItem: NSView {
    let mode: ThumbnailLayoutMode
    init(mode: ThumbnailLayoutMode) {
        self.mode = mode
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not implemented") }
}
