//
//  CategoryRowView.swift
//  ImageGallery
//
//  V4.83.0 NEW: 顶层 FilterPopover 4 类别行视图
//    FilterPopover 拆 2 层 popover 重构——顶层 4 类别入口
//    每个 row 显示：icon + 标题 + count badge + chevron
//
//  范式：
//    - 32pt 高（V4.79.0 categoryRowHeight）
//    - icon 15pt（V4.79.0 categoryRowIconSize）
//    - chevron 9pt（V4.79.0 categoryRowChevronSize）
//    - count badge 11pt 数字 + 16pt 高（V4.79.0 countBadgeSize/Height）
//    - 0 激活时 count badge 隐藏
//
//  Why NSView 子类（而非 NSStackView 内嵌 NSButton）：
//    - 子 popover 需要 row 作 anchor——NSView 能直接给 popover.show(relativeTo:of:)
//    - 内部结构稳定，外部只需 update(count:summary:) 增量更新
//

import AppKit

/// V4.83.0: 顶层 popover 4 类别入口行视图
///   点击触发 onTap closure（coordinator 接管）
///   子 popover 锚定到此 view 的 bounds
final class CategoryRowView: NSView {
    /// 点击回调——coordinator 接管
    var onTap: (() -> Void)?

    /// 类别标识（folder / tag / shape / rating）——用于子 popover 路由
    let category: FilterCategory

    // MARK: - 子视图

    private let iconView: NSImageView
    private let titleLabel: NSTextField
    private let countBadge: NSTextField
    private let countBadgeBg: NSView
    private let chevronView: NSImageView
    private let mainStack: NSStackView

    // MARK: - init

    init(category: FilterCategory) {
        self.category = category

        // icon
        self.iconView = NSImageView(image: NSImage(systemSymbolName: category.icon, accessibilityDescription: nil) ?? NSImage())
        self.iconView.imageScaling = .scaleProportionallyDown
        self.iconView.contentTintColor = .secondaryLabelColor
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.setContentHuggingPriority(.required, for: .horizontal)

        // title
        self.titleLabel = NSTextField(labelWithString: category.title)
        self.titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        self.titleLabel.textColor = .labelColor
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // count badge bg (圆角矩形)
        self.countBadgeBg = NSView()
        self.countBadgeBg.wantsLayer = true
        self.countBadgeBg.layer?.cornerRadius = PopoverStyle.categoryRowCountBadgeHeight / 2  // 8pt
        self.countBadgeBg.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(PopoverStyle.categoryRowCountBadgeOpacity).cgColor  // 12% accent
        self.countBadgeBg.translatesAutoresizingMaskIntoConstraints = false

        // count badge text
        self.countBadge = NSTextField(labelWithString: "0")
        self.countBadge.font = NSFont.systemFont(ofSize: PopoverStyle.categoryRowCountBadgeSize, weight: .medium)
        self.countBadge.textColor = .labelColor
        self.countBadge.alignment = .center
        self.countBadge.translatesAutoresizingMaskIntoConstraints = false

        // chevron
        self.chevronView = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        self.chevronView.imageScaling = .scaleProportionallyDown
        self.chevronView.contentTintColor = .tertiaryLabelColor
        self.chevronView.translatesAutoresizingMaskIntoConstraints = false
        self.chevronView.setContentHuggingPriority(.required, for: .horizontal)

        // HStack 装配
        self.mainStack = NSStackView()
        self.mainStack.orientation = .horizontal
        self.mainStack.alignment = .centerY
        self.mainStack.spacing = 8
        self.mainStack.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        // count badge: 文字叠在 bg 上
        countBadgeBg.addSubview(countBadge)
        NSLayoutConstraint.activate([
            countBadge.centerXAnchor.constraint(equalTo: countBadgeBg.centerXAnchor),
            countBadge.centerYAnchor.constraint(equalTo: countBadgeBg.centerYAnchor),
            countBadgeBg.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowCountBadgeHeight),
            // min width 给数字留点呼吸
            countBadgeBg.widthAnchor.constraint(greaterThanOrEqualToConstant: 22)
        ])

        // icon (固定 15pt) | title (撑满) | count badge (固定宽) | chevron (固定 9pt)
        mainStack.addArrangedSubview(iconView)
        mainStack.addArrangedSubview(titleLabel)
        mainStack.addArrangedSubview(countBadgeBg)
        mainStack.addArrangedSubview(chevronView)

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowHeight)  // 32pt
        ])

        // icon/chevron 固定尺寸
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: PopoverStyle.categoryRowIconSize),
            iconView.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowIconSize),
            chevronView.widthAnchor.constraint(equalToConstant: PopoverStyle.categoryRowChevronSize),
            chevronView.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowChevronSize)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 更新

    /// V4.83.0: 增量更新 count/summary——rebuild 时调用
    ///   - count 0: 隐藏 count badge
    ///   - rating 类别用 summary（如 "≥4星"）优先于 count
    func update(count: Int, summary: String? = nil) {
        if let summary = summary {
            countBadge.stringValue = summary
            countBadgeBg.isHidden = false
        } else if count > 0 {
            countBadge.stringValue = "\(count)"
            countBadgeBg.isHidden = false
        } else {
            countBadgeBg.isHidden = true
        }
    }

    // MARK: - mouseDown

    /// V4.83.0: 整行点击触发 onTap——子 popover 打开逻辑由 coordinator 接管
    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    /// V4.83.0: 整行可点击——光标变 pointer
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// V4.83.0: 4 类别枚举
enum FilterCategory: String, CaseIterable {
    case folder, tag, shape, rating

    var title: String {
        switch self {
        case .folder: return "文件夹"
        case .tag: return "标签"
        case .shape: return "形状"
        case .rating: return "评分"
        }
    }

    var icon: String {
        switch self {
        case .folder: return "folder"
        case .tag: return "tag"
        case .shape: return "rectangle"
        case .rating: return "star"
        }
    }
}
