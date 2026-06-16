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
    /// V5.97: internal(set) + didSet → refreshSelectionVisuals()——保证 row 视觉跟 currentItem 同步
    ///   V5.96 stored property 赋值不触发 AppKit 重绘, row 视觉冻结到下次 loadView()
    ///   (用户报告: 工具栏立即更新, popover 下次开才显示新选中)
    ///   internal(set) 让测试可写——锁住"setter 触发视觉刷新" invariant
    internal(set) var currentItem: T {
        didSet {
            guard oldValue != currentItem else { return }
            refreshSelectionVisuals()
        }
    }

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
        rowView.layer?.addSublayer(bgLayer)
        // 存 bgLayer 到 rowView, layout 时更新 frame
        rowView.selectionBackgroundLayer = bgLayer

        let icon = NSImageView(image: NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) ?? NSImage())
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: item.displayName)
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        let checkmark = NSTextField(labelWithString: "✓")
        // V5.86: 12pt → 16pt 跟 icon (16x16) 匹配——macOS Photos 选中态风格
        //   之前 12pt 视觉比 icon 小 4pt, 看起来 icon/checkmark 视觉权重不一致
        //   现在 2-tier hierarchy: icon+checkmark 同 16pt, label 13pt
        checkmark.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        checkmark.textColor = .controlAccentColor
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        // V5.97: 把视觉引用挂到 rowView, refreshSelectionVisuals() 后续能更新
        //   之前这些是 let 局部变量, handleItemClick 改 currentItem 后没人通知重绘
        rowView.iconView = icon
        rowView.labelView = label
        rowView.checkmarkView = checkmark

        // V5.97: 统一入口——初始创建 + 后续刷新走同一函数, 锁住视觉一致性
        applySelectionVisuals(isSelected: isSelected, bgLayer: bgLayer,
                              icon: icon, label: label, checkmark: checkmark)

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
        // V5.97: setter 触发 didSet → refreshSelectionVisuals()——row 视觉立刻同步
        //   V5.96 注释承诺"body 重渲染", 但 stored property 赋值不触发 AppKit 重绘
        //   (V5.96 实际只延后了 dismiss, 让 popover 多停留 0.15s——并不能修原 bug)
        currentItem = selectedItem
        onSelect?(selectedItem)
        // V5.96: 0.15s 延迟 dismiss——让用户看到新选中状态再关闭(Photos 范式)
        //   0.15s 视觉感知阈值: < 0.1s 用户感觉不到, 0.1-0.2s 刚好"闪过"
        // V5.97: 视觉刷新现在是 0ms (didSet 同步触发), 0.15s 留作"确认感"——点完看一眼再收
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.view.window?.contentViewController?.dismiss(nil)
        }
    }

    /// V5.97: 共享视觉更新逻辑——makeOptionItem 初始化 + refreshSelectionVisuals 复用
    ///   锁住 4 个视觉 (bg / icon tint / label color / checkmark hidden) 跟 isSelected 一致
    private func applySelectionVisuals(isSelected: Bool,
                                       bgLayer: CALayer,
                                       icon: NSImageView,
                                       label: NSTextField,
                                       checkmark: NSTextField) {
        bgLayer.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
            : nil
        icon.contentTintColor = isSelected ? .controlAccentColor : .labelColor
        label.textColor = isSelected ? .controlAccentColor : .labelColor
        checkmark.isHidden = !isSelected
    }

    /// V5.97: currentItem 改变时遍历所有 row, 同步选中视觉
    ///   替代 V5.96 注释承诺但未实现的"body 重渲染"——NSView 子树没有 KVO,
    ///   必须手动遍历 stackView.arrangedSubviews 重画
    private func refreshSelectionVisuals() {
        for row in stackView.arrangedSubviews {
            // OptionItemView<T> 私有类——同文件 cast 安全
            // 用 perform(#selector) 太绕, 直接 as? + force-unwrap 视觉引用 (makeOptionItem 必填)
            guard let typed = row as? OptionItemView<T>,
                  let bgLayer = typed.selectionBackgroundLayer,
                  let icon = typed.iconView,
                  let label = typed.labelView,
                  let checkmark = typed.checkmarkView else { continue }
            applySelectionVisuals(
                isSelected: typed.item == currentItem,
                bgLayer: bgLayer,
                icon: icon,
                label: label,
                checkmark: checkmark
            )
        }
    }
}

/// V5.77: 内部 generic NSView subclass 存 item (NSView.tag 是 readonly)
/// V5.80: 加 selectionBackgroundLayer 引用 + layout override 更新 bg frame
/// V5.97: 加 iconView/labelView/checkmarkView 引用——refreshSelectionVisuals() 需更新视觉
///   之前 makeOptionItem 里这些是 let 局部变量, handleItemClick 改 currentItem 后没人通知重绘
private final class OptionItemView<T: OptionListItem>: NSView {
    let item: T
    /// V5.80: 选中背景层 (6% accent bg) 引用——在 layout() 时更新 frame
    var selectionBackgroundLayer: CALayer?
    /// V5.97: 视觉引用——让 refreshSelectionVisuals() 能即时切换 4 个视觉 (bg/icon/label/checkmark)
    var iconView: NSImageView?
    var labelView: NSTextField?
    var checkmarkView: NSTextField?

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

// MARK: - V5.97: 测试 hook——返回 row 视觉状态快照
extension OptionListPopoverController {
    /// V5.97: 测试用——单一 row 的视觉状态
    ///   锁住 invariant: 切换 currentItem 后, 4 个视觉 (✓/bg/icon tint) 立即同步
    struct RowState {
        let item: T
        let isCheckmarkHidden: Bool
        let hasSelectionBackground: Bool
        let iconTintIsAccent: Bool
    }

    /// V5.97: 测试用——返回当前所有 row 的视觉状态
    ///   内部访问 private OptionItemView<T>——同文件 cast 安全
    var _rowStatesForTesting: [RowState] {
        stackView.arrangedSubviews.compactMap { row -> RowState? in
            guard let typed = row as? OptionItemView<T> else { return nil }
            return RowState(
                item: typed.item,
                isCheckmarkHidden: typed.checkmarkView?.isHidden ?? true,
                hasSelectionBackground: typed.selectionBackgroundLayer?.backgroundColor != nil,
                iconTintIsAccent: typed.iconView?.contentTintColor == .controlAccentColor
            )
        }
    }
}
