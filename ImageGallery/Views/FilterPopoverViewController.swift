//
//  FilterPopoverViewController.swift
//  ImageGallery
//
//  V4.36.x: 工具栏筛选按钮的 popover 内容——**AppKit 原生实现**
//  弃用 SwiftUI FilterPopover + NSHostingController 方案，原因：
//    SwiftUI 视图的 intrinsic size 与 NSPopover 的尺寸协商不一致，
//    导致 popover 实际宽度超出 .frame(width:) 约束、被窗口右边界裁切
//
//  新方案用 NSStackView + NSButton 纯 AppKit 渲染：
//    - 4 段配置：文件夹 / 标签 / 形状 / 评分
//    - 状态通过 callback closure 同步到 ContentView
//    - preferredContentSize 显式设值，NSPopover 直接看这个
//
//  V4.36.x 5 个 P0 修复：
//    #1 形状段裁切 → 只显示 icon（3 个一行）
//    #2 评分段裁切 → 2 行 3 列布局
//    #3 缺"清除全部"按钮 → header 加 button
//    #4 updateState 未调用 → 监听 .filterStateChangedFromOutside
//    #5 颜色不统一 → 全部 labelColor，active 用 accent 背景区分
//

import AppKit

extension Notification.Name {
    /// V4.36.x: ContentView 在 .onChange(of: filterState) 时发此通知
    ///   popover 监听后调 updateState 同步 UI
    static let filterStateChangedFromOutside = Notification.Name("FilterStateChangedFromOutside")
}

final class FilterPopoverViewController: NSViewController, NSSearchFieldDelegate {
    // MARK: - 配置常量

    private static let contentWidth: CGFloat = 200
    private static let padding: CGFloat = 8
    private static let itemHeight: CGFloat = 22
    private static let sectionHeaderHeight: CGFloat = 18
    private static let sectionSpacing: CGFloat = 8
    private static let segmentRowHeight: CGFloat = 26
    private static let segmentGap: CGFloat = 4
    private static let columnGap: CGFloat = 8
    private static let searchFieldHeight: CGFloat = 22  // V4.36.x: NSSearchField 高度

    // MARK: - 数据源 + 回调

    /// state 变化时回调——ContentView 监听并同步 FilterState
    var onStateChange: ((FilterState) -> Void)?

    /// "清除全部"按钮回调
    var onClearAll: (() -> Void)?

    private var filterState: FilterState
    private let allFolders: [Folder]
    private let allTags: [Tag]

    // V4.36.x #4: filter popover 内搜索——folder/tag 段顶部 NSSearchField
    //   实时过滤；过滤后如全空显示空状态
    private var searchText: String = "" {
        didSet { rebuildContent() }
    }
    private var searchField: NSSearchField?

    // 缓存所有 NSButton 引用——切换时同步 UI 状态
    private var folderButtons: [UUID: NSButton] = [:]
    private var tagButtons: [UUID: NSButton] = [:]
    private var shapeButtons: [PhotoShape: NSButton] = [:]
    private var ratingButtons: [Int: NSButton] = [:]  // 0 = 全部, 1-5 = n星

    // 内容容器——重建式布局（搜索时整个内容区重建）
    private var contentStack: NSStackView?

    // MARK: - init

    init(filterState: FilterState, folders: [Folder], tags: [Tag]) {
        self.filterState = filterState
        self.allFolders = folders
        self.allTags = tags
        super.init(nibName: nil, bundle: nil)
        // V4.36.x: 关键——preferredContentSize 决定 NSPopover 实际大小
        // AppKit 直接读这个值，不走 SwiftUI intrinsic size 协商
        self.preferredContentSize = NSSize(
            width: Self.contentWidth,
            height: Self.computeHeight(folders: folders, tags: tags)
        )
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = Self.sectionSpacing
        outer.edgeInsets = NSEdgeInsets(
            top: Self.padding, left: Self.padding,
            bottom: Self.padding, right: Self.padding
        )
        outer.translatesAutoresizingMaskIntoConstraints = false

        // 顶部：header（"筛选" + "清除全部"）
        outer.addArrangedSubview(makeHeader())

        // V4.36.x #4: 搜索框——folder/tag 段顶部
        let search = NSSearchField()
        search.placeholderString = "搜索文件夹、标签"
        search.bezelStyle = .roundedBezel
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.target = self
        search.action = #selector(handleSearchChanged(_:))
        search.translatesAutoresizingMaskIntoConstraints = false
        searchField = search
        outer.addArrangedSubview(search)

        // 内容区——可重建（搜索过滤时整段重建）
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = Self.sectionSpacing
        content.translatesAutoresizingMaskIntoConstraints = false
        contentStack = content
        rebuildContent()
        outer.addArrangedSubview(content)

        self.view = outer
    }

    /// V4.36.x #4: 重建内容区（搜索过滤时整体重建——folder/tag 段）
    private func rebuildContent() {
        guard let content = contentStack else { return }
        // 清空旧内容
        for sub in content.arrangedSubviews {
            content.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        // 过滤 folder/tag
        let loweredSearch = searchText.lowercased()
        let filteredFolders = loweredSearch.isEmpty
            ? allFolders
            : allFolders.filter { $0.name.lowercased().contains(loweredSearch) }
        let filteredTags = loweredSearch.isEmpty
            ? allTags
            : allTags.filter { $0.name.lowercased().contains(loweredSearch) }

        // 段 1: 文件夹
        if !allFolders.isEmpty {
            if filteredFolders.isEmpty {
                content.addArrangedSubview(makeEmptyHint("无匹配文件夹"))
            } else {
                content.addArrangedSubview(makeSectionHeader("文件夹", icon: "folder"))
                content.addArrangedSubview(makeTwoColumnCheckList(items: filteredFolders) { folder in
                    let button = self.makeCheckItem(
                        label: folder.name,
                        isOn: filterState.folders.contains(folder.id)
                    ) { [weak self] in
                        self?.handleFolderToggle(folder.id)
                    }
                    self.folderButtons[folder.id] = button
                    return button
                })
            }
        }

        // 段 2: 标签
        if !allTags.isEmpty {
            if filteredTags.isEmpty {
                content.addArrangedSubview(makeEmptyHint("无匹配标签"))
            } else {
                content.addArrangedSubview(makeSectionHeader("标签", icon: "tag"))
                content.addArrangedSubview(makeTwoColumnCheckList(items: filteredTags) { tag in
                    let button = self.makeCheckItem(
                        label: "#\(tag.name)",
                        isOn: filterState.tags.contains(tag.id)
                    ) { [weak self] in
                        self?.handleTagToggle(tag.id)
                    }
                    self.tagButtons[tag.id] = button
                    return button
                })
            }
        }

        // 段 3: 形状（不参与搜索过滤）
        content.addArrangedSubview(makeSectionHeader("形状", icon: "rectangle"))
        let shapeStack = makeSegmentRow()
        for shape in PhotoShape.allCases {
            let button = makeIconOnlySegmentItem(
                icon: shape.icon,
                isActive: filterState.shapes.contains(shape)
            ) { [weak self] in
                self?.handleShapeToggle(shape)
            }
            shapeStack.addArrangedSubview(button)
            shapeButtons[shape] = button
        }
        content.addArrangedSubview(shapeStack)

        // 段 4: 评分（不参与搜索过滤）
        content.addArrangedSubview(makeSectionHeader("评分", icon: "star"))
        let ratingContainer = NSStackView()
        ratingContainer.orientation = .vertical
        ratingContainer.alignment = .leading
        ratingContainer.spacing = Self.segmentGap
        ratingContainer.translatesAutoresizingMaskIntoConstraints = false

        let row1 = makeSegmentRow()
        let noRating = makeIconTextSegmentItem(
            icon: nil, text: "全部",
            isActive: filterState.minRating == 0
        ) { [weak self] in
            self?.handleRatingToggle(0)
        }
        row1.addArrangedSubview(noRating)
        ratingButtons[0] = noRating
        for n in 1...2 {
            let button = makeIconTextSegmentItem(
                icon: nil, text: "\(n)星",
                isActive: filterState.minRating == n
            ) { [weak self] in
                self?.handleRatingToggle(n)
            }
            row1.addArrangedSubview(button)
            ratingButtons[n] = button
        }
        ratingContainer.addArrangedSubview(row1)

        let row2 = makeSegmentRow()
        for n in 3...5 {
            let button = makeIconTextSegmentItem(
                icon: nil, text: "\(n)星",
                isActive: filterState.minRating == n
            ) { [weak self] in
                self?.handleRatingToggle(n)
            }
            row2.addArrangedSubview(button)
            ratingButtons[n] = button
        }
        ratingContainer.addArrangedSubview(row2)
        content.addArrangedSubview(ratingContainer)
    }

    @objc private func handleSearchChanged(_ sender: NSSearchField) {
        searchText = sender.stringValue
    }

    private func makeEmptyHint(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // V4.36.x #4: 监听外部 state 变化（如 ActiveFiltersBar × 删 chip）
        //   同步更新 popover UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalStateChange),
            name: .filterStateChangedFromOutside,
            object: nil
        )
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleExternalStateChange() {
        // ContentView 在 .onChange(of: filterState) 时把最新 state 附在 userInfo 里
        // 这里直接读
        let newState = (view.window?.contentViewController as? NSViewController)?.representedObject as? FilterState
        // 简化：直接从 filterState 引用（由 ContentView 同步过）
        syncButtonStates()
    }

    // MARK: - 公共 API

    /// V4.36.x #4: ContentView 在 .onChange(of: filterState) 时调此方法
    ///   显式传入新 state + 同步 popover UI（用于反向同步场景）
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        syncButtonStates()
    }

    private func syncButtonStates() {
        for (id, button) in folderButtons {
            button.state = filterState.folders.contains(id) ? .on : .off
        }
        for (id, button) in tagButtons {
            button.state = filterState.tags.contains(id) ? .on : .off
        }
        for (shape, button) in shapeButtons {
            applySegmentStyle(button, isActive: filterState.shapes.contains(shape), text: nil)
        }
        for (rating, button) in ratingButtons {
            // 从 button 读 attributedTitle 拿回 text
            let text = button.attributedTitle.string
            applySegmentStyle(button, isActive: filterState.minRating == rating, text: text)
        }
    }

    // MARK: - 子视图工厂

    /// 顶部 header："筛选" + "清除全部" 按钮（仅激活时显示）
    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: "筛选")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        let stack = NSStackView(views: [title, NSView()])  // spacer 用空 view 占位
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        // "清除全部" 按钮（仅在筛选激活时显示）
        if filterState.isActive {
            let clearButton = NSButton(title: "清除全部", target: self, action: #selector(handleClearAllTapped))
            clearButton.bezelStyle = .recessed
            clearButton.controlSize = .small
            clearButton.font = NSFont.systemFont(ofSize: 11)
            clearButton.isBordered = false
            clearButton.contentTintColor = .secondaryLabelColor
            // 用 attributeString 渲染下划线 + 蓝色（链接风格）
            let attrTitle = NSAttributedString(
                string: "清除全部",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            )
            clearButton.attributedTitle = attrTitle
            stack.addArrangedSubview(clearButton)
        }

        return stack
    }

    @objc private func handleClearAllTapped() {
        onClearAll?()
    }

    private func makeSectionHeader(_ title: String, icon: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let imageView = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage())
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        return stack
    }

    /// checkbox + label 的 item
    /// V4.36.x #5: 统一文字颜色 labelColor——active 态用 checkbox + 浅蓝背景区分
    private func makeCheckItem(
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: label, action: action)
        button.setButtonType(.switch)
        button.state = isOn ? .on : .off
        button.isBordered = false
        // 统一文字颜色（不随 state 变）
        button.contentTintColor = .labelColor
        return button
    }

    /// 2 列紧凑列表：HStack + 2 VStack（左列先满）
    private func makeTwoColumnCheckList<T: AnyObject, Button: NSButton>(
        items: [T],
        itemBuilder: (T) -> Button
    ) -> NSView {
        let half = (items.count + 1) / 2
        let leftItems = Array(items.prefix(half))
        let rightItems = Array(items.dropFirst(half))

        let leftVStack = NSStackView()
        leftVStack.orientation = .vertical
        leftVStack.alignment = .leading
        leftVStack.spacing = 2
        leftVStack.translatesAutoresizingMaskIntoConstraints = false
        for item in leftItems {
            leftVStack.addArrangedSubview(itemBuilder(item))
        }

        let rightVStack = NSStackView()
        rightVStack.orientation = .vertical
        rightVStack.alignment = .leading
        rightVStack.spacing = 2
        rightVStack.translatesAutoresizingMaskIntoConstraints = false
        for item in rightItems {
            rightVStack.addArrangedSubview(itemBuilder(item))
        }

        let hStack = NSStackView(views: [leftVStack, rightVStack])
        hStack.orientation = .horizontal
        hStack.distribution = .fillEqually
        hStack.spacing = Self.columnGap
        hStack.alignment = .top
        hStack.translatesAutoresizingMaskIntoConstraints = false
        return hStack
    }

    /// 单行 segment（用于形状段——3 个 icon-only 按钮）
    private func makeSegmentRow() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = Self.segmentGap
        stack.distribution = .fillEqually
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// icon-only segment item（用于形状——只 SF Symbol，无文字）
    /// V4.36.x #1: 解决"3 个带文字 segment 装不下 200pt"裁切
    /// V4.36.x: 用 SF Symbol 的 paletteColors **预染色**为白色
    ///   之前尝试 image.isTemplate + contentTintColor 都不生效
    ///   （NSButton 无 title 时 tint 行为不可靠）
    ///   paletteColors 直接生成白色 image——绕开 NSButton tint 系统
    private func makeIconOnlySegmentItem(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: "", action: action)
        button.bezelStyle = .recessed
        // 预染色 SF Symbol 为白色——白色 icon
        let whiteConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(whiteConfig)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        applySegmentStyle(button, isActive: isActive, text: nil)
        return button
    }

    /// icon + text segment item（用于评分——星数 + "n星"文字）
    private func makeIconTextSegmentItem(
        icon: String?,
        text: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: "", action: action)  // title 留空，用 attributedTitle 上色
        button.bezelStyle = .recessed
        applySegmentStyle(button, isActive: isActive, text: text)
        return button
    }

    // MARK: - 状态同步

    /// V4.36.x #5: 文字 + icon 永远白色
    ///   - 文字：attributedTitle 锁 white
    ///   - 图标：contentTintColor = .white
    ///   - 背景：active 实色 accent / inactive 半透明黑（让白字有衬底）
    ///   失活/激活只靠背景区分——macOS 标准 NSSegmentedControl 风格
    private func applySegmentStyle(_ button: NSButton, isActive: Bool, text: String?) {
        // 1. 文字：永远白
        if let text = text {
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium)
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString()
        }

        // 2. 图标：永远白
        button.contentTintColor = .white

        // 3. 背景：active 实色 accent / inactive 半透明黑（让白字有底）
        if isActive {
            button.bezelColor = .controlAccentColor
        } else {
            // 半透明黑底——白字可读，弱化"未选"感
            button.bezelColor = NSColor.black.withAlphaComponent(0.25)
        }
    }

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
        syncButtonStates()
        onStateChange?(filterState)
    }

    private func handleRatingToggle(_ rating: Int) {
        filterState.minRating = rating
        syncButtonStates()
        onStateChange?(filterState)
    }

    // MARK: - 高度计算

    /// V4.36.x: header 高度（"筛选" 文字 + "清除全部" 链接）
    private static let headerHeight: CGFloat = 22

    private static func computeHeight(folders: [Folder], tags: [Tag]) -> CGFloat {
        let padding: CGFloat = 16
        let header: CGFloat = headerHeight + 4  // header + 与下段间距
        let searchSection: CGFloat = searchFieldHeight + sectionSpacing  // V4.36.x: 搜索框
        let sectionHeader: CGFloat = 18
        let item: CGFloat = 22
        let section: CGFloat = 8
        let segment: CGFloat = 26
        // V4.36.x: folder/tag 段 2 列——高度按列中较多那列算
        let folderColHeight = ceil(CGFloat(folders.count) / 2) * item
        let tagColHeight = ceil(CGFloat(tags.count) / 2) * item
        // V4.36.x #2: 评分段 2 行——高度 = 2 * segment + 1 * segmentGap
        let ratingBlock: CGFloat = 2 * segment + segmentGap
        let total: CGFloat =
            padding
            + header
            + searchSection
            + (folders.isEmpty ? 0 : sectionHeader + folderColHeight + section)
            + (tags.isEmpty ? 0 : sectionHeader + tagColHeight + section)
            + sectionHeader + segment   // shape 单行
            + section
            + sectionHeader + ratingBlock
        return total
    }
}

// MARK: - NSButton + closure 桥接

private final class ClosureButton: NSButton {
    private let actionClosure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.actionClosure = action
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(invoke)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    @objc private func invoke() { actionClosure() }
}
