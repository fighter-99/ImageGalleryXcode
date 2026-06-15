//
//  DensityPopoverController.swift
//  ImageGallery
//
//  V5.74 NEW: 工具栏 density 按钮 NSPopover
//    仿 V5.72 LayoutModePopoverController pattern——Photos 单按钮单 popover 范式
//    替代 V5.39.3 NSMenu 实现——视觉统一 (跟 filter / layoutMode 风格一致)
//    4 选项: compact (极小) / small (小) / medium (中) / large (大)
//
//  V5.72 (layoutMode) pilot 验证后, V5.74/V5.75 扩到 density/sort.
//

import AppKit

/// V5.74: 工具栏 density 按钮的 popover 控制器
///   4 选项 (compact/small/medium/large) 单选, 仿 Photos 风格
final class DensityPopoverController: NSViewController {
    /// V5.74: 用户选项回调——caller 写入 UserSettings + 更新 toolbar icon
    var onSelect: ((ThumbnailDensity) -> Void)?

    /// V5.74: 当前选中的 density——画 checkmark
    private(set) var currentDensity: ThumbnailDensity

    private let stackView: NSStackView

    init(currentDensity: ThumbnailDensity) {
        self.currentDensity = currentDensity
        self.stackView = NSStackView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func loadView() {
        // V5.74: 3 层 sandwich 仿 V5.72 layoutMode + nspopover-tamc-sandwich pattern
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for density in ThumbnailDensity.allCases {
            let item = makeOptionItem(for: density)
            stackView.addArrangedSubview(item)
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

    /// V5.74: 单个选项 (icon + label + checkmark) 24pt 高
    private func makeOptionItem(for density: ThumbnailDensity) -> NSView {
        let item = DensityOptionItem(density: density)
        item.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: density.iconName, accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = density == currentDensity ? .controlAccentColor : .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: density.label)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = density == currentDensity ? .controlAccentColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = NSTextField(labelWithString: "✓")
        checkmark.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        checkmark.textColor = .controlAccentColor
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.isHidden = density != currentDensity

        item.addSubview(icon)
        item.addSubview(label)
        item.addSubview(checkmark)

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

            item.heightAnchor.constraint(equalToConstant: 24),
            item.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])

        return item
    }

    @objc private func handleItemClick(_ sender: NSClickGestureRecognizer) {
        guard let item = sender.view as? DensityOptionItem else { return }
        onSelect?(item.density)
        view.window?.contentViewController?.dismiss(nil)
    }
}

/// V5.74: 内部 NSView subclass 存 density (NSView.tag 是 readonly)
private final class DensityOptionItem: NSView {
    let density: ThumbnailDensity
    init(density: ThumbnailDensity) {
        self.density = density
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not implemented") }
}
