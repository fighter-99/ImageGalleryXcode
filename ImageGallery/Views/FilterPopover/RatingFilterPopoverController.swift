//
//  RatingFilterPopoverController.swift
//  ImageGallery
//
//  V4.88.0 NEW: Rating 二级 popover
//    FilterPopover 拆 2 层 popover 重构 Phase 2
//    顶层 FilterTopPopoverViewController 点 rating 行 → 显示本 popover
//
//  范式：
//    - 6 个 icon: ○ 全部 + 5 ⭐ (1-5)
//    - ⭐ 用 .systemYellow paletteColors（V4.69.0 范式）
//    - 240pt 宽 × 48pt 高（12 padding + 24 items）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 共享 PopoverItemFactory enum（V4.81.0）的 makeIconOnlySegmentItem / makeSegmentRow
//

import AppKit

/// V4.88.0: Rating 二级 popover——6 个 icon
///   - ○ 全部（PhotoShape.circle）
///   - ⭐ 1-5（SF Symbol "star.fill" + .systemYellow palette）
///   仿 macOS Photos 评分 popover 风格
final class RatingFilterPopoverController: NSViewController {
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
        // V4.88.0: 单行 6 icon: ○ 全部 + ⭐ 1-5
        let row = PopoverItemFactory.makeSegmentRow()
        // "全部"——0 = 无评分筛选
        let noRating = PopoverItemFactory.makeIconOnlySegmentItem(
            icon: "circle",
            isActive: filterState.minRating == 0
        ) { [weak self] in
            self?.handleToggle(0)
        }
        row.addArrangedSubview(noRating)
        // ⭐ 1-5——V4.69.0 范式：创建时显式传 iconTintOverride = .systemYellow
        for n in 1...5 {
            let button = PopoverItemFactory.makeIconOnlySegmentItem(
                icon: "star.fill",
                isActive: filterState.minRating == n,
                iconTintOverride: .systemYellow
            ) { [weak self] in
                self?.handleToggle(n)
            }
            row.addArrangedSubview(button)
        }
        visualEffect.addSubview(row)
        // V4.99.0: padding 12→6——与 FolderFilterPopover 保持一致
        //   减 NSPopover 内置 inset——视觉紧凑
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.padding / 2),
            row.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.padding / 2),
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
    ///   当前 6 个 button 无独立缓存——updateState 无需操作
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        // 当前无子 button——no-op
    }

    // MARK: - toggle

    private func handleToggle(_ rating: Int) {
        filterState.minRating = rating
        onStateChange?(filterState)
    }
}
