//
//  RatingRowView.swift
//  ImageGallery
//
//  V5.5: 单行评分选择——5 颗星（N 实 + (5-N) 空）+ 文字标签
//    - 内联 NSStackView: 5 NSImageView (star/star.fill) + spacer + NSTextField
//    - 整行 mouseDown 触发 onTap
//    - Active 态：10% accent bg + labelColor 文字
//    - Inactive 态：透明 bg + secondaryLabelColor 文字 + 5 颗灰色星
//    - 固定高度 26pt
//
//  V5.63-1: 提取到独立文件——之前在 RatingFilterPopoverController.swift (V5.5),
//    删 4 child popover controllers 时一并删, 这里重建
//

import AppKit

/// V5.5: 单行评分选择——5 颗星 + 文字标签
///   - 内部 NSStackView: 5 NSImageView (star/star.fill) + spacer + NSTextField
///   - 整行 mouseDown 触发 onTap
final class RatingRowView: NSView {
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
        starStack.spacing = 2
        starStack.alignment = .centerY
        starStack.translatesAutoresizingMaskIntoConstraints = false
        for star in starViews {
            starStack.addArrangedSubview(star)
        }
        starStack.setContentHuggingPriority(.required, for: .horizontal)

        // V5.6: 右侧 flexible spacer——内容左对齐,剩余宽度填充
        let trailingSpacer = NSView()
        trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
        trailingSpacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        trailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // HStack: stars + spacer + label + trailingSpacer
        let rowStack = NSStackView(views: [starStack, titleLabel, trailingSpacer])
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
            heightAnchor.constraint(equalToConstant: 26)
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

        // 星颜色:active 时实心星 systemYellow, 空心星 secondaryLabelColor
        //         inactive 时全部 secondaryLabelColor
        let filledColor: NSColor = isActive ? .systemYellow : .secondaryLabelColor
        let emptyColor: NSColor = .secondaryLabelColor
        for (index, starView) in starViews.enumerated() {
            starView.contentTintColor = (index < filledCount) ? filledColor : emptyColor
        }
    }

    /// 公开更新方法 (外部 state 变化时调用)
    func setActive(_ active: Bool) {
        isActive = active
        updateAppearance()
    }
}
