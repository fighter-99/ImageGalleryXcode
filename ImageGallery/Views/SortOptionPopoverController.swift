//
//  SortOptionPopoverController.swift
//  ImageGallery
//
//  V5.75 NEW: 工具栏 sort 按钮 NSPopover
//    仿 V5.72 LayoutModePopoverController pattern——Photos 单按钮单 popover 范式
//    替代 V5.39.3 NSMenu 实现——视觉统一 (跟 filter / layoutMode / density 风格一致)
//    7 选项: importedAtDesc/Asc, filenameAsc/Desc, fileSizeDesc/Asc, customOrder
//

import AppKit

/// V5.75: 工具栏 sort 按钮的 popover 控制器
///   7 选项单选, 仿 Photos 风格
final class SortOptionPopoverController: NSViewController {
    /// V5.75: 用户选项回调——caller 写入 UserSettings + 更新 toolbar icon
    var onSelect: ((SortOption) -> Void)?

    /// V5.75: 当前选中的 sortOption——画 checkmark
    private(set) var currentOption: SortOption

    private let stackView: NSStackView

    init(currentOption: SortOption) {
        self.currentOption = currentOption
        self.stackView = NSStackView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func loadView() {
        // V5.75: 3 层 sandwich 仿 V5.72 layoutMode
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for option in SortOption.allCases {
            let item = makeOptionItem(for: option)
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

    /// V5.75: 单个选项 (direction icon + label + checkmark) 24pt 高
    private func makeOptionItem(for option: SortOption) -> NSView {
        let item = SortOptionItem(option: option)
        item.translatesAutoresizingMaskIntoConstraints = false

        // V5.75: direction icon (arrow.up/down/line.3.horizontal) 替代 layoutMode/density 的分类 icon
        let icon = NSImageView(image: NSImage(systemSymbolName: option.directionIcon, accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = option == currentOption ? .controlAccentColor : .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: option.label)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = option == currentOption ? .controlAccentColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = NSTextField(labelWithString: "✓")
        checkmark.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        checkmark.textColor = .controlAccentColor
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.isHidden = option != currentOption

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
            item.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])

        return item
    }

    @objc private func handleItemClick(_ sender: NSClickGestureRecognizer) {
        guard let item = sender.view as? SortOptionItem else { return }
        onSelect?(item.option)
        view.window?.contentViewController?.dismiss(nil)
    }
}

/// V5.75: 内部 NSView subclass 存 option (NSView.tag 是 readonly)
private final class SortOptionItem: NSView {
    let option: SortOption
    init(option: SortOption) {
        self.option = option
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not implemented") }
}
