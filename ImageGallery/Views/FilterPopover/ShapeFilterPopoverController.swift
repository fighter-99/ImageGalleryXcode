//
//  ShapeFilterPopoverController.swift
//  ImageGallery
//
//  V4.88.0 NEW: Shape 二级 popover
//    FilterPopover 拆 2 层 popover 重构 Phase 2
//    顶层 FilterTopPopoverViewController 点 shape 行 → 显示本 popover
//
//  范式：
//    - 3 个 icon-only PhotoShape (landscape/portrait/square)
//    - 180pt 宽 × 60pt 高（V5.5 缩窄 + 增高——容纳 22pt icon）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 共享 PopoverItemFactory enum（V4.81.0）的 makeIconOnlySegmentItem / makeSegmentRow
//
//  V5.5: 3 个 icon 视觉混淆修复
//    - 之前 iconFontSize 15pt——rectangle.fill / rectangle.portrait.fill / square.fill
//      在 15pt 下像素约 15×10/10×15/15×15——白色填充在 transl 上视觉差异仅 5px
//      用户截图 19 反馈"3 个 icon 全是一个样"
//    - 现在 22pt——20×13/13×20/20×20——aspect ratio 9px 差异明显可见
//    - 同时 preferredWidth 240→180pt——3 item 不需要 240pt 宽
//

import AppKit

/// V4.88.0: Shape 二级 popover——3 个 PhotoShape (landscape/portrait/square)
///   V5.5: 22pt icon + 180pt 宽——让 aspect ratio 视觉清晰
final class ShapeFilterPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 180
    private static let preferredHeight: CGFloat = 60
    private static let shapeIconSize: CGFloat = 22
    private static let padding: CGFloat = PopoverStyle.padding

    // MARK: - init

    init(filterState: FilterState) {
        self.filterState = filterState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V4.88.0: NSVisualEffectView 包裹——V4.80.0 popoverHost() helper
        let visualEffect = NSVisualEffectView.popoverHost()
        // V4.88.0: 单行 segment row——3 icon-only 按钮
        let row = PopoverItemFactory.makeSegmentRow()
        for shape in PhotoShape.allCases {
            let button = PopoverItemFactory.makeIconOnlySegmentItem(
                icon: shape.icon,
                isActive: filterState.shapes.contains(shape),
                iconSize: Self.shapeIconSize  // V5.5: 22pt 让 aspect ratio 可见
            ) { [weak self] in
                self?.handleToggle(shape)
            }
            row.addArrangedSubview(button)
        }
        visualEffect.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.padding),
            row.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.padding),
            row.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
        ])
        self.view = visualEffect
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: Self.preferredHeight
        )
    }

    // MARK: - 状态同步

    /// V4.88.0: 接收外部 filterState 变化
    ///   当前 3 个 button 无独立缓存——updateState 无需操作
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        // 当前无子 button——no-op
    }

    // MARK: - toggle

    private func handleToggle(_ shape: PhotoShape) {
        if filterState.shapes.contains(shape) {
            filterState.shapes.remove(shape)
        } else {
            filterState.shapes.insert(shape)
        }
        onStateChange?(filterState)
    }
}
