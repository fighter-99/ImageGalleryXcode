//
//  FilterTopPopoverViewController.swift
//  ImageGallery
//
//  V4.84.0 NEW: 顶层 FilterPopover——4 类别入口
//    FilterPopover 拆 2 层 popover 重构 Phase 2
//    顶层只显示 4 类别行（folder/tag/shape/rating），点击进入二级
//    仿 macOS Photos 8-item 简洁风格（30-item → 4-item 入口）
//
//  范式：
//    - 240×184pt preferredContentSize
//    - header "筛选" + "清除"（仅 isActive 时显示）
//    - 4 个 CategoryRowView（V4.83.0）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 接收 filterState + onStateChange + onClearAll + onCategoryTap 4 个 closure
//
//  V4.84.0: 4 row 只触 onCategoryTap closure——不创建子 popover
//    子 popover 创建由 coordinator（V4.85.0 接入）接管
//

import AppKit

/// V4.84.0: 顶层 FilterPopover——4 类别入口
///   仿 macOS Photos 8-item popover 风格
///   4 类别入口比 30-item 单层更轻盈
final class FilterTopPopoverViewController: NSViewController {
    // MARK: - 回调

    /// V4.84.0: filterState 变化回调——ContentView 接管写回 @State
    var onStateChange: ((FilterState) -> Void)?

    /// V4.84.0: "清除" 按钮回调
    var onClearAll: (() -> Void)?

    /// V4.84.0: 类别 row 点击回调——coordinator 接管打开子 popover
    var onCategoryTap: ((FilterCategory) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState

    // MARK: - 子视图

    private let headerLabel: NSTextField
    private let clearButton: NSButton
    private var categoryRows: [FilterCategory: CategoryRowView] = [:]
    private let contentStack: NSStackView

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 240
    private static let preferredHeight: CGFloat = 184
    private static let padding: CGFloat = PopoverStyle.padding  // 12pt

    // MARK: - init

    init(filterState: FilterState) {
        self.filterState = filterState

        self.headerLabel = NSTextField(labelWithString: "筛选")
        self.headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.headerLabel.textColor = .labelColor
        self.headerLabel.translatesAutoresizingMaskIntoConstraints = false

        self.clearButton = NSButton(title: "清除", target: nil, action: nil)
        self.clearButton.bezelStyle = .recessed
        self.clearButton.controlSize = .small
        self.clearButton.font = NSFont.systemFont(ofSize: 11)
        self.clearButton.isBordered = false
        self.clearButton.contentTintColor = .tertiaryLabelColor
        self.clearButton.translatesAutoresizingMaskIntoConstraints = false
        // V4.84.0: target/action 在 viewDidLoad 设——init 阶段 self 不可用

        self.contentStack = NSStackView()
        self.contentStack.orientation = .vertical
        self.contentStack.alignment = .leading
        self.contentStack.spacing = 0
        self.contentStack.translatesAutoresizingMaskIntoConstraints = false

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V4.84.0: NSVisualEffectView 包裹——V4.80.0 popoverHost() helper
        let visualEffect = NSVisualEffectView.popoverHost()
        // header
        let headerStack = NSStackView(views: [headerLabel, clearButton])
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // 4 row 创建
        for category in FilterCategory.allCases {
            let row = CategoryRowView(category: category)
            // V4.84.0: row tap 转发给 onCategoryTap closure
            row.onTap = { [weak self] in
                self?.onCategoryTap?(category)
            }
            categoryRows[category] = row
            contentStack.addArrangedSubview(row)
        }

        // outer VStack: header + content
        let outer = NSStackView(views: [headerStack, contentStack])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 0),
            outer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: 0),
            outer.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 0),
            outer.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: 0),
            headerStack.leadingAnchor.constraint(equalTo: outer.leadingAnchor, constant: Self.padding),
            headerStack.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -Self.padding),
            headerStack.topAnchor.constraint(equalTo: outer.topAnchor, constant: Self.padding),
            contentStack.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 6),
            contentStack.bottomAnchor.constraint(equalTo: outer.bottomAnchor)
        ])

        self.view = visualEffect
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        clearButton.target = self
        clearButton.action = #selector(handleClearTapped)
        rebuildAllRows()
        updateClearButtonVisibility()
    }

    /// V4.84.0: 显式设 preferredContentSize——NSPopover 读这个值
    override func viewDidLayout() {
        super.viewDidLayout()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: Self.preferredHeight
        )
    }

    // MARK: - 状态同步

    /// V4.84.0: 接收外部 filterState 变化（V4.36.x #4 范式）
    ///   ContentView .onChange(of: filterState) 推送
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        rebuildAllRows()
        updateClearButtonVisibility()
    }

    private func rebuildAllRows() {
        for category in FilterCategory.allCases {
            guard let row = categoryRows[category] else { continue }
            let count = count(for: category)
            let summary = summary(for: category)
            row.update(count: count, summary: summary)
        }
    }

    private func updateClearButtonVisibility() {
        clearButton.isHidden = !filterState.isActive
    }

    // MARK: - 计数 / summary 计算

    private func count(for category: FilterCategory) -> Int {
        switch category {
        case .folder: return filterState.folders.count
        case .tag: return filterState.tags.count
        case .shape: return filterState.shapes.count
        case .rating: return filterState.minRating > 0 ? 1 : 0  // 评分单值
        }
    }

    /// V4.84.0: rating 类别用 summary 而非 count——表达"≥N 星"语义
    private func summary(for category: FilterCategory) -> String? {
        if category == .rating, filterState.minRating > 0 {
            return "≥ \(filterState.minRating) ★"
        }
        return nil
    }

    // MARK: - 清除按钮

    @objc private func handleClearTapped() {
        onClearAll?()
    }
}
