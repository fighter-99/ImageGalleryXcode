//
//  FilterUnifiedPopoverController.swift
//  ImageGallery
//
//  V5.63-1: 入口重设计——单 popover 4 可折叠 sections
//    替代 V4.84.0 2 级 popover (顶层 4 row + 子 popover 选具体)
//    仿 macOS Photos 1 级 popover 风格——所有选项一目了然, 不用 2 级跳转
//    click-outside 自动关 (V5.62-1 改回 .transient) 就够, 不需要 2 级
//
//  范式：
//    - 1 个 NSStackView 纵向 4 section
//    - 每个 section:
//      - header: 复用 CategoryRowView (icon + 标题 + count + chevron) — 点击 toggle expand
//      - content: 自适应高度的子容器 (folder/tag NSStackView checkboxes, shape 3 icon row, rating 6 star rows)
//    - 默认 folder 展开, 单 section 模式 (accordion) — 一次只 1 section open
//    - 整 popover 高度上限 600pt——超出时外层 NSScrollView 滚动
//    - 280pt 宽 (vs 原 240pt)——给 4 section header 留 padding
//
//  关联:
//    - V5.62-2 实时同步逻辑: updateState 4 个 section 视觉, 保留——但简化 (无需 4 个子 VC, 1 个 VC 管 4 section)
//    - V5.62-1 click-outside 自动关: 沿用 .transient 行为
//

import AppKit

/// V5.63-1: 统一 Filter popover——单窗口 4 可折叠 sections
///   替代 V4.84.0 2 级 popover
///   仿 macOS Photos filter 侧边栏风格——1 级下拉
final class FilterUnifiedPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState

    // V5.63-1: 展开 section 状态——accordion 模式 (单 section 展开)
    private var expandedSection: FilterCategory? = .folder

    // MARK: - 子视图引用

    private var categoryRows: [FilterCategory: CategoryRowView] = [:]
    // V5.62-2: button 引用——updateState 同步视觉
    private var checkButtons: [UUID: NSButton] = [:]   // folder + tag 共用
    private var shapeButtons: [PhotoShape: NSButton] = [:]
    private var ratingRows: [Int: RatingRowView] = [:]
    // V5.63-1: 4 个 section content 容器——visibility 通过折叠
    private var sectionContents: [FilterCategory: NSView] = [:]

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 280
    private static let maxHeight: CGFloat = 600
    private static let sectionContentPadding: CGFloat = 8
    private static let outerPadding: CGFloat = PopoverStyle.padding  // 12pt
    private static let sectionSpacing: CGFloat = 0  // section 间不留 gap, 用分隔线

    // MARK: - init

    init(filterState: FilterState) {
        self.filterState = filterState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V5.2 范式：container → visualEffect → outerScroll → outerStack
        //   整体 popover 可滚 (maxHeight 600pt 兜底)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        // header (title + clear)
        let headerLabel = NSTextField(labelWithString: "筛选")
        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "清除", target: self, action: #selector(handleClearTapped))
        clearButton.bezelStyle = .recessed
        clearButton.controlSize = .small
        clearButton.font = NSFont.systemFont(ofSize: 11)
        clearButton.isBordered = false
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [headerLabel, clearButton])
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        // 4 section 创建
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = Self.sectionSpacing
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        for category in FilterCategory.allCases {
            // 1. section header: 复用 CategoryRowView (icon + 标题 + count + chevron)
            let row = CategoryRowView(category: category)
            // V5.63-1: 点击 header → toggle expand (替代原 "→ 子 popover")
            row.onTap = { [weak self] in
                self?.toggleSection(category)
            }
            categoryRows[category] = row
            outerStack.addArrangedSubview(row)

            // 2. section content (initially hidden, show if expanded)
            let content = makeSectionContent(for: category)
            content.translatesAutoresizingMaskIntoConstraints = false
            // 关键: stack 里 addArrangedSubview + 设 visibility collapsed
            outerStack.addArrangedSubview(content)
            // V5.63-1: 高度约束由内容决定, visibility = .visible / .collapsed
            //   NSStackView 配合 NSView.isHidden——.isHidden true 时自动从 layout 移除
            content.isHidden = (category != expandedSection)
            sectionContents[category] = content

            // V5.63-1: section header 与 content 间加 1pt 分隔线
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            // (insert between row and content by inserting after both in stack)
        }

        // header + outerStack
        let contentStack = NSStackView(views: [headerStack, outerStack])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        // V5.63-1: 外层 NSScrollView——maxHeight 600pt 兜底
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentStack

        visualEffect.addSubview(scrollView)
        container.addSubview(visualEffect)
        self.view = container

        // 三层约束
        NSLayoutConstraint.activate([
            // 1. visualEffect 撑满 container
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 2. scrollView 在 visualEffect 内 12pt padding
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.outerPadding),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.outerPadding),
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.outerPadding),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -Self.outerPadding),
            // 3. contentStack 撑满 scrollView 文档宽
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            // 4. maxHeight 兜底
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxHeight - 2 * Self.outerPadding)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // V5.63-1: 高度按内容 (header + 展开 section 高度) + padding
        //   NSScrollView 自动限制 maxHeight——这里算实际内容高度
        let visibleContentHeight = (view.subviews.first?.subviews.first as? NSScrollView)?
            .documentView?.fittingSize.height ?? 200
        let totalHeight = min(visibleContentHeight + 2 * Self.outerPadding, Self.maxHeight)
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: totalHeight
        )
    }

    // MARK: - Section content 构建

    /// V5.63-1: 给定 category 构建 section content 容器——checkbox list / 3 icon row / 6 star rows
    ///   每个 section 用统一 VStack 容器, padding 与 CategoryRowView 12pt 左对齐
    private func makeSectionContent(for category: FilterCategory) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.sectionContentPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.sectionContentPadding),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2)
        ])

        switch category {
        case .folder:
            buildFolderList(into: stack)
        case .tag:
            buildTagList(into: stack)
        case .shape:
            buildShapeRow(into: stack)
        case .rating:
            buildRatingRows(into: stack)
        }
        return container
    }

    /// folder checkbox list——V4.86.0 范式
    private func buildFolderList(into stack: NSStackView) {
        // 复用 V5.62-2 的 [weak self] + 存 checkButtons 模式
        for folder in availableFolders {
            let button = PopoverItemFactory.makeCheckItem(
                label: folder.name,
                isOn: filterState.folders.contains(folder.id)
            ) { [weak self] in
                self?.handleFolderToggle(folder.id)
            }
            checkButtons[folder.id] = button
            stack.addArrangedSubview(button)
        }
    }

    /// tag checkbox list——V4.87.0 范式, V5.62-1 加 # 前缀
    private func buildTagList(into stack: NSStackView) {
        for tag in availableTags {
            let button = PopoverItemFactory.makeCheckItem(
                label: "#\(tag.name)",
                isOn: filterState.tags.contains(tag.id)
            ) { [weak self] in
                self?.handleTagToggle(tag.id)
            }
            checkButtons[tag.id] = button
            stack.addArrangedSubview(button)
        }
    }

    /// shape 3 icon row——V4.88.0 范式
    private func buildShapeRow(into stack: NSStackView) {
        let row = PopoverItemFactory.makeSegmentRow()
        for shape in PhotoShape.allCases {
            let button = PopoverItemFactory.makeIconOnlySegmentItem(
                icon: shape.icon,
                isActive: filterState.shapes.contains(shape),
                iconSize: 22  // V5.5: 22pt 让 aspect ratio 可见
            ) { [weak self] in
                self?.handleShapeToggle(shape)
            }
            shapeButtons[shape] = button
            row.addArrangedSubview(button)
        }
        stack.addArrangedSubview(row)
    }

    /// rating 6 rows——V5.5 macOS Photos 风格
    private func buildRatingRows(into stack: NSStackView) {
        let contentWidth = Self.preferredWidth - 2 * Self.outerPadding - 2 * Self.sectionContentPadding

        let allRow = RatingRowView(
            filledCount: 0,
            label: "全部",
            isActive: filterState.minRating == 0,
            width: contentWidth
        ) { [weak self] in
            self?.handleRatingToggle(0)
        }
        ratingRows[0] = allRow
        stack.addArrangedSubview(allRow)

        for n in 1...5 {
            let row = RatingRowView(
                filledCount: n,
                label: "≥\(n) 星",
                isActive: filterState.minRating == n,
                width: contentWidth
            ) { [weak self] in
                self?.handleRatingToggle(n)
            }
            ratingRows[n] = row
            stack.addArrangedSubview(row)
        }
    }

    // MARK: - 数据源

    private var availableFolders: [Folder] = []
    private var availableTags: [Tag] = []

    /// V5.63-1: 由 coordinator 在 makeChildViewController (旧路径) 或 init 时注入
    ///   旧子 popover 接 onStateChange 后通过此 setter 更新内部数据
    func setDataSource(folders: [Folder], tags: [Tag]) {
        self.availableFolders = folders
        self.availableTags = tags
    }

    // MARK: - V5.63-1: section toggle

    private func toggleSection(_ category: FilterCategory) {
        if expandedSection == category {
            // 再次点击 → 折叠
            expandedSection = nil
        } else {
            expandedSection = category
        }
        // 更新所有 section content visibility
        for (cat, content) in sectionContents {
            content.isHidden = (cat != expandedSection)
        }
        // 更新 chevron 视觉 (CategoryRowView.update 内部管)
        for (cat, row) in categoryRows {
            let isExpanded = (cat == expandedSection)
            row.setActive(isExpanded)
        }
    }

    // MARK: - Toggle handlers

    private func handleFolderToggle(_ id: UUID) {
        if filterState.folders.contains(id) {
            filterState.folders.remove(id)
        } else {
            filterState.folders.insert(id)
        }
        onStateChange?(filterState)
    }

    private func handleTagToggle(_ id: UUID) {
        if filterState.tags.contains(id) {
            filterState.tags.remove(id)
        } else {
            filterState.tags.insert(id)
        }
        onStateChange?(filterState)
    }

    private func handleShapeToggle(_ shape: PhotoShape) {
        if filterState.shapes.contains(shape) {
            filterState.shapes.remove(shape)
        } else {
            filterState.shapes.insert(shape)
        }
        onStateChange?(filterState)
    }

    private func handleRatingToggle(_ rating: Int) {
        filterState.minRating = rating
        onStateChange?(filterState)
    }

    @objc private func handleClearTapped() {
        let empty = FilterState.empty
        filterState = empty
        onStateChange?(empty)
    }

    // MARK: - 状态同步 (V5.62-2 沿用)

    /// V5.62-2: 外部 filterState 变化——实时同步 4 个 section 视觉
    ///   现在 4 section 在 1 个 VC 内——只需 rebuild visual, 无需跨 VC 通讯
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        // folder + tag: checkbox state
        for (id, button) in checkButtons {
            if availableFolders.contains(where: { $0.id == id }) {
                button.state = newState.folders.contains(id) ? .on : .off
            } else if availableTags.contains(where: { $0.id == id }) {
                button.state = newState.tags.contains(id) ? .on : .off
            }
        }
        // shape: segment active 视觉
        for (shape, button) in shapeButtons {
            PopoverItemFactory.applySegmentStyle(
                button,
                isActive: newState.shapes.contains(shape),
                text: nil,
                symbolName: shape.icon,
                iconSize: 22
            )
        }
        // rating: row active
        for (rating, row) in ratingRows {
            row.setActive(rating == newState.minRating)
        }
        // section header count badge 同步
        updateSectionHeaderCounts()
    }

    /// V5.63-1: 更新 4 section header 的 count badge——updateState 时同步
    ///   用 CategoryRowView.update(count:summary:) 增量更新
    private func updateSectionHeaderCounts() {
        for category in FilterCategory.allCases {
            guard let row = categoryRows[category] else { continue }
            let count = count(for: category)
            let summary = summary(for: category)
            row.update(count: count, summary: summary)
        }
    }

    private func count(for category: FilterCategory) -> Int {
        switch category {
        case .folder: return filterState.folders.count
        case .tag: return filterState.tags.count
        case .shape: return filterState.shapes.count
        case .rating: return filterState.minRating > 0 ? 1 : 0
        }
    }

    private func summary(for category: FilterCategory) -> String? {
        if category == .rating, filterState.minRating > 0 {
            return "≥ \(filterState.minRating) ★"
        }
        return nil
    }
}
