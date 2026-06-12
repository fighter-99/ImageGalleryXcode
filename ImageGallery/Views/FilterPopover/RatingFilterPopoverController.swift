//
//  RatingFilterPopoverController.swift
//  ImageGallery
//
//  V4.88.0 NEW: Rating 二级 popover
//    FilterPopover 拆 2 层 popover 重构 Phase 2
//    顶层 FilterTopPopoverViewController 点 rating 行 → 显示本 popover
//
//  V5.5: macOS Photos 风格重构——单行 6 icon → 6 行每行 5 星
//    之前 6 个独立 segment item 排 1 行——大黄星像 emoji + 蓝圆"全部"对比生硬
//    现在 6 行纵向——每行 5 颗星（N 实 + (5-N) 空）+ 文字标签
//    视觉渐进：○○○○○ → ●○○○○ → ●●○○○ → ●●●○○ → ●●●●○ → ●●●●●
//    macOS Photos 评分侧边栏风格——一眼数出 N
//
//  范式：
//    - 1 全部行（5 空心星 + "全部"） + 5 评分行（N 实 + (5-N) 空 + "≥N 星"）
//    - 152pt 宽 × 6×26pt + 5×2pt spacing + 24pt padding ≈ 190pt 高
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 私有 RatingRowView 替代 segment item——5 星 inline 排版
//

import AppKit

/// V4.88.0: Rating 二级 popover
///   V5.5: 6 行 5 星评级（macOS Photos 风格）替代 V4.88.0 单行 6 icon
final class RatingFilterPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState

    // MARK: - 子视图引用（V5.5: viewDidLayout 计算 content height 用）

    private var rowContainer: NSStackView?

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 152
    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 2
    private static let padding: CGFloat = PopoverStyle.padding
    private static let starSize: CGFloat = 14
    private static let starSpacing: CGFloat = 2

    // MARK: - init

    init(filterState: FilterState) {
        self.filterState = filterState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V5.2 范式：container → visualEffect → rowStack 三明治结构
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        // V5.5: 6 行纵向——每行 RatingRowView
        let rowStack = NSStackView()
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = Self.rowSpacing
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        let contentWidth = Self.preferredWidth - 2 * Self.padding

        // 全部行：5 颗空心 + "全部" 文字
        rowStack.addArrangedSubview(RatingRowView(
            filledCount: 0,
            label: "全部",
            isActive: filterState.minRating == 0,
            width: contentWidth
        ) { [weak self] in
            self?.handleToggle(0)
        })

        // 5 评分行：N 实 + (5-N) 空 + "≥N 星" 文字
        for n in 1...5 {
            rowStack.addArrangedSubview(RatingRowView(
                filledCount: n,
                label: "≥\(n) 星",
                isActive: filterState.minRating == n,
                width: contentWidth
            ) { [weak self] in
                self?.handleToggle(n)
            })
        }

        self.rowContainer = rowStack
        container.addSubview(visualEffect)
        visualEffect.addSubview(rowStack)
        NSLayoutConstraint.activate([
            // 1. visualEffect 撑满 container
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 2. rowStack 在 visualEffect 内 12pt padding
            rowStack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.padding),
            rowStack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.padding),
            rowStack.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.padding),
            rowStack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -Self.padding)
        ])
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // V5.1 范式：高度按内容收缩——6 行 + spacing + padding
        let contentHeight = (rowContainer?.fittingSize.height ?? 0) + 2 * Self.padding
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: contentHeight
        )
    }

    // MARK: - 状态同步

    /// V4.88.0: 接收外部 filterState 变化
    ///   当前无独立 button 缓存——updateState 需重建（active 视觉同步）
    ///   当前 sub-popover 关闭后即丢弃——coordinator 重建——updateState 不会触发
    func updateState(_ newState: FilterState) {
        self.filterState = newState
    }

    // MARK: - toggle

    private func handleToggle(_ rating: Int) {
        filterState.minRating = rating
        onStateChange?(filterState)
    }
}

// MARK: - V5.5: RatingRowView——单行 5 星 + 文字标签

/// V5.5: 单行评分选择——5 颗星（N 实 + (5-N) 空）+ 文字标签
///   - 内联 NSStackView: 5 NSImageView (star/star.fill) + spacer + NSTextField
///   - 整行 mouseDown 触发 onTap
///   - Active 态：10% accent bg + labelColor 文字
///   - Inactive 态：透明 bg + secondaryLabelColor 文字 + 5 颗灰色星
///   - 固定高度 26pt
private final class RatingRowView: NSView {
    private let filledCount: Int
    private let onTap: () -> Void

    private let titleLabel: NSTextField
    private var starViews: [NSImageView] = []
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var isActive: Bool

    init(filledCount: Int, label: String, isActive: Bool, width: CGFloat, onTap: @escaping () -> Void) {
        self.filledCount = filledCount
        self.isActive = isActive
        self.onTap = onTap
        self.titleLabel = NSTextField(labelWithString: label)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = PopoverStyle.itemCornerRadius

        // 文字 label
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 5 颗星
        for i in 1...5 {
            let symbolName = i <= filledCount ? "star.fill" : "star"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            let imageView = NSImageView(image: image ?? NSImage())
            imageView.imageScaling = .scaleProportionallyDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 14).isActive = true
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            starViews.append(imageView)
        }

        // 5 星 horizontal stack
        let starStack = NSStackView()
        starStack.orientation = .horizontal
        starStack.spacing = RatingFilterPopoverController.StarSpacingValue
        starStack.alignment = .centerY
        starStack.translatesAutoresizingMaskIntoConstraints = false
        for star in starViews {
            starStack.addArrangedSubview(star)
        }
        starStack.setContentHuggingPriority(.required, for: .horizontal)

        // HStack: stars + spacer + label
        let rowStack = NSStackView(views: [starStack, titleLabel])
        rowStack.orientation = .horizontal
        rowStack.spacing = 12
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        // 固定宽 + 固定高
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: RatingFilterPopoverController.RowHeightValue)
        ])

        // TrackingArea 用于 hover 状态
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        onTap()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - 视觉

    private func updateAppearance() {
        // 背景
        if isActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        } else {
            layer?.backgroundColor = .clear
        }

        // 星颜色：active 时实心星 systemYellow，空心星 secondaryLabelColor
        //         inactive 时全部 secondaryLabelColor
        let filledColor: NSColor = isActive ? .systemYellow : .secondaryLabelColor
        let emptyColor: NSColor = .secondaryLabelColor
        for (index, starView) in starViews.enumerated() {
            starView.contentTintColor = (index < filledCount) ? filledColor : emptyColor
        }
    }

    // 公开更新方法（外部 state 变化时调用）
    func setActive(_ active: Bool) {
        isActive = active
        updateAppearance()
    }
}

extension RatingFilterPopoverController {
    // V5.5: 暴露 row 内部常量给 RatingRowView（同一文件 extension 共享 fileprivate）
    fileprivate static var RowHeightValue: CGFloat { Self.rowHeight }
    fileprivate static var StarSpacingValue: CGFloat { Self.starSpacing }
}
