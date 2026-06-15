//
//  CategoryRowView.swift
//  ImageGallery
//
//  V4.83.0 NEW: 顶层 FilterPopover 4 类别行视图
//    FilterPopover 拆 2 层 popover 重构——顶层 4 类别入口
//    每个 row 显示：icon + 标题 + count badge + chevron
//
//  范式：
//    - 40pt 高（V4.79.0 categoryRowHeight, V5.63-3: 32→40——更易点击 target + 视觉 breathing）
//    - icon 15pt（V4.79.0 categoryRowIconSize）
//    - chevron 9pt（V4.79.0 categoryRowChevronSize）
//    - count badge 10pt 数字 + 16pt 高（V4.79.0 countBadgeSize/Height, V5.63-3: 11→10pt 更轻）
//    - 0 激活时 count badge 隐藏
//
//  Why NSView 子类（而非 NSStackView 内嵌 NSButton）：
//    - 子 popover 需要 row 作 anchor——NSView 能直接给 popover.show(relativeTo:of:)
//    - 内部结构稳定，外部只需 update(count:summary:) 增量更新
//
//  V5.9: 三态视觉锤（macOS Photos 选中风格）
//    1. 默认：  透明背景 + secondary icon/text
//    2. Hover： 10% labelColor 背景 + primary icon/text
//    3. Active：85% accent 背景 + 白 icon/text（子 popover 打开中）
//    之前只有 cursor 变化——行点击无任何视觉反馈
//

import AppKit

/// V4.83.0: 顶层 popover 4 类别入口行视图
///   V5.9: 三态视觉锤（hover / active / has-filter via count badge）
final class CategoryRowView: NSView {
    /// 点击回调——coordinator 接管
    var onTap: (() -> Void)?

    /// 类别标识（folder / tag / shape / rating）——用于子 popover 路由
    let category: FilterCategory

    // MARK: - 状态（V5.9 新增三态视觉）

    /// V5.9: 是否 hover（鼠标在 row 范围内）
    ///   didSet 触发 background/icon/text 颜色更新
    private var isHovered: Bool = false {
        didSet { updateAppearance() }
    }

    /// V5.9: 是否 active（子 popover 打开中 / 子 popover 锚点）
    ///   外部（coordinator）通过 setActive(_:) 切换
    /// V5.14: private(set) 让测试可读
    private(set) var isActive: Bool = false {
        didSet { updateAppearance() }
    }

    /// V5.63-2: 是否 expanded (section 展开状态)——独立于 isActive
    ///   didSet 触发 chevron 旋转 0°→90° 动画 + expand 视觉反馈
    private(set) var isExpanded: Bool = false {
        didSet {
            animateChevronRotation()
            updateAppearance()
        }
    }

    // MARK: - 子视图

    private let backgroundLayer: NSView  // V5.9: 三态背景载体
    private let iconView: NSImageView
    private let titleLabel: NSTextField
    /// V5.14: 从 private 改 internal——测试读 countBadge.stringValue
    let countBadge: NSTextField
    /// V5.14: 从 private 改 internal——测试读 countBadgeBg.isHidden
    let countBadgeBg: NSView
    private let chevronView: NSImageView
    private let mainStack: NSStackView

    // MARK: - init

    init(category: FilterCategory) {
        self.category = category

        // V5.9: 背景层——三态背景颜色承载
        self.backgroundLayer = NSView()
        self.backgroundLayer.wantsLayer = true
        self.backgroundLayer.layer?.cornerRadius = PopoverStyle.itemCornerRadius
        self.backgroundLayer.translatesAutoresizingMaskIntoConstraints = false

        // icon
        self.iconView = NSImageView(image: NSImage(systemSymbolName: category.icon, accessibilityDescription: nil) ?? NSImage())
        self.iconView.imageScaling = .scaleProportionallyDown
        self.iconView.contentTintColor = .secondaryLabelColor
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.setContentHuggingPriority(.required, for: .horizontal)

        // title
        // V5.63-3: 13pt regular → 14pt medium——section title 字号权重提升, 仿 macOS Photos
        self.titleLabel = NSTextField(labelWithString: category.title)
        self.titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        self.titleLabel.textColor = .labelColor
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // count badge bg (圆角矩形)
        // V5.63-3: 20% → 10% accent——配合整行 4% labelColor tint, 视觉层次:
        //   整行 4% (最弱) > count badge 10% (中等) > active 100% (最强)
        self.countBadgeBg = NSView()
        self.countBadgeBg.wantsLayer = true
        self.countBadgeBg.layer?.cornerRadius = PopoverStyle.categoryRowCountBadgeHeight / 2  // 8pt
        self.countBadgeBg.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(PopoverStyle.categoryRowCountBadgeOpacity).cgColor  // V5.63-3: 0.20 → 0.10
        self.countBadgeBg.translatesAutoresizingMaskIntoConstraints = false

        // count badge text
        // V5.63-3: .semibold → .regular + 字号 11→10pt——Mac 原生感更轻, 不抢 title
        self.countBadge = NSTextField(labelWithString: "0")
        self.countBadge.font = NSFont.systemFont(ofSize: PopoverStyle.categoryRowCountBadgeSize, weight: .regular)
        self.countBadge.textColor = .labelColor
        self.countBadge.alignment = .center
        self.countBadge.translatesAutoresizingMaskIntoConstraints = false

        // chevron
        // V4.95.0: tertiaryLabelColor → secondaryLabelColor——在 transl material 上更明显
        //   之前 tertiaryLabelColor 太弱——截图 11 chevron 几乎不可见
        //   secondaryLabelColor 在 V4.79.0 categoryRowChevronSize 9pt 仍有足够视觉重量
        self.chevronView = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        self.chevronView.imageScaling = .scaleProportionallyDown
        self.chevronView.contentTintColor = .secondaryLabelColor
        self.chevronView.translatesAutoresizingMaskIntoConstraints = false
        self.chevronView.setContentHuggingPriority(.required, for: .horizontal)

        // HStack 装配
        self.mainStack = NSStackView()
        self.mainStack.orientation = .horizontal
        self.mainStack.alignment = .centerY
        self.mainStack.spacing = 8
        self.mainStack.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        // V5.9: 背景层在最底层——撑满 row
        addSubview(backgroundLayer)
        NSLayoutConstraint.activate([
            backgroundLayer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            backgroundLayer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            backgroundLayer.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            backgroundLayer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])

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
            // V5.67: trailing -12→-18 (3pt buffer)——scroller 出现在 x=241..256 (右侧 15pt)
            //   chevron + count badge 不应重叠 scroller; -18 让 chevron 右边缘在 238, scroller 左边在 241, gap 3pt
            //   V5.63-2 commit message 说 'chevron 12pt 缩进' 但实际未改代码, 现补回
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowHeight)  // 40pt
        ])

        // icon/chevron 固定尺寸
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: PopoverStyle.categoryRowIconSize),
            iconView.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowIconSize),
            chevronView.widthAnchor.constraint(equalToConstant: PopoverStyle.categoryRowChevronSize),
            chevronView.heightAnchor.constraint(equalToConstant: PopoverStyle.categoryRowChevronSize)
        ])

        // V5.9: 初始外观（默认态）
        updateAppearance()
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

    // MARK: - V5.9: 三态视觉切换

    /// V5.9: 外部（coordinator）切换 active 状态——子 popover 打开时 true
    ///   关闭 active 由 coordinator 在 popoverDidClose 回调
    /// V5.63-2: unified popover 模式下不再使用——保留字段兼容性
    func setActive(_ active: Bool) {
        isActive = active
    }

    /// V5.63-2: section 展开/折叠状态切换——chevron 旋转 0°→90° 动画
    ///   独立于 setActive——用 expand 状态做轻量视觉反馈 (6% accent bg)
    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    /// V5.63-2: chevron 旋转动画 (NSImageView.frameCenterRotation)
    ///   collapsed: 0° (chevron.right)
    ///   expanded: 90° (chevron.down 视觉)
    private func animateChevronRotation() {
        let targetRotation: CGFloat = isExpanded ? 90 : 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            chevronView.animator().frameCenterRotation = targetRotation
        }
    }

    /// V5.9 + V5.63-2: 四态视觉更新
    ///   优先级: expanded > active > hover > default
    ///   V5.63-2: expanded 态新加——6% accent bg (轻量高亮) + primary chevron
    ///   active 态保持 V5.9 (85% accent, 保留以备子 popover 模式)
    ///   颜色: 背景 / icon / title / chevron
    private func updateAppearance() {
        if isExpanded {
            // Expanded 态 (V5.63-2): 6% accent bg + primary 前景——轻量高亮
            //   不复用 V5.9 active 态 (85% accent 太重, 与 Photos 风格不符)
            backgroundLayer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
            iconView.contentTintColor = .labelColor
            titleLabel.textColor = .labelColor
            chevronView.contentTintColor = .labelColor  // chevron 高亮 (旋转 90° 后更明显)
        } else if isActive {
            // Active 态 (V5.9): 85% accent bg + 白前景 (macOS Photos 选中风格)
            backgroundLayer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            iconView.contentTintColor = .white
            titleLabel.textColor = .white
            chevronView.contentTintColor = .white
        } else if isHovered {
            // Hover 态: 10% labelColor bg + primary 前景
            backgroundLayer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            iconView.contentTintColor = .labelColor
            titleLabel.textColor = .labelColor
            chevronView.contentTintColor = .secondaryLabelColor
        } else {
            // 默认态: 透明 bg + secondary 前景
            backgroundLayer.layer?.backgroundColor = .clear
            iconView.contentTintColor = .secondaryLabelColor
            titleLabel.textColor = .labelColor
            chevronView.contentTintColor = .secondaryLabelColor
        }
    }

    // MARK: - 鼠标事件

    /// V4.83.0: 整行点击触发 onTap——子 popover 打开逻辑由 coordinator 接管
    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    /// V4.83.0: 整行可点击——光标变 pointer
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - V5.9: Hover 检测

    /// V5.9: 注册 tracking area——mouseEntered/Exited 触发 isHovered 切换
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
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
