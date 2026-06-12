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
//    - 240pt 宽 × 48pt 高（12 padding + 24 items）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 共享 PopoverItemFactory enum（V4.81.0）的 makeIconOnlySegmentItem / makeSegmentRow
//

import AppKit

/// V4.88.0: Shape 二级 popover——3 个 PhotoShape (landscape/portrait/square)
///   仿 macOS Photos 排序 popover 风格——非常窄（48pt）
final class ShapeFilterPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 240
    private static let preferredHeight: CGFloat = 48
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
                isActive: filterState.shapes.contains(shape)
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
