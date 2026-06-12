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

final class FilterPopoverViewController: NSViewController {
    // MARK: - 配置常量
    //
    // V4.41.1: 全部从 PopoverStyle token 引用——与 ViewOptionsPopover 视觉对齐
    //   之前 V4.36.x 写死 200/8/22/26 与 ViewOptions 240/12/44 不一致
    //   现在统一：width 240 / padding 12 / itemHeight 28
    // V4.44.0: 删 searchFieldHeight——NSSearchField 移除后不再需要

    private static let contentWidth: CGFloat = PopoverStyle.width
    private static let padding: CGFloat = PopoverStyle.padding
    private static let itemHeight: CGFloat = PopoverStyle.itemHeight
    private static let sectionHeaderHeight: CGFloat = 18
    private static let sectionSpacing: CGFloat = PopoverStyle.sectionSpacing
    private static let segmentRowHeight: CGFloat = PopoverStyle.itemHeight
    private static let segmentGap: CGFloat = PopoverStyle.segmentGap
    private static let columnGap: CGFloat = PopoverStyle.columnGap

    // MARK: - 数据源 + 回调

    /// state 变化时回调——ContentView 监听并同步 FilterState
    var onStateChange: ((FilterState) -> Void)?

    /// "清除全部"按钮回调
    var onClearAll: (() -> Void)?

    private var filterState: FilterState
    private let allFolders: [Folder]
    private let allTags: [Tag]

    // V4.44.0: 删 NSSearchField 搜索——folder/tag 通常 10-20 个无需实时过滤
    //   减少 popover 高度 + 视觉聚焦 (移除 NSSearchField 占的 22pt + 段间距 10pt = 32pt)
    //   删除相关: searchText state、searchField 引用、searchFieldHeight 常量

    // 缓存所有 NSButton 引用——切换时同步 UI 状态
    private var folderButtons: [UUID: NSButton] = [:]
    private var tagButtons: [UUID: NSButton] = [:]
    private var shapeButtons: [PhotoShape: NSButton] = [:]
    private var ratingButtons: [Int: NSButton] = [:]  // 0 = 全部, 1-5 = n星

    // 内容容器——重建式布局
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
        // V4.45.0: NSVisualEffectView 包裹整个 popover——macOS Photos transl material
        //   .popover 材质是 macOS 专门为 popover 设计的 subtle blur
        //   让窗口背景色 / 工具栏毛玻璃透过来 = 真 macOS 风格
        // V4.46.0: state .active → .followsWindowActiveState
        //   暗色下 .active 偏"闷" (绿色调透过来)
        //   .followsWindowActiveState 跟窗口 active 状态走
        // V4.47.0: blendingMode .behindWindow → .withinWindow
        //   .withinWindow 让材质在窗口内 blend (相对自己周围)，不受窗口内容色偏影响
        //   暗色下 popover 不再"闷"——保持 macOS Photos 风格的清透
        // V4.82.0: 改用 NSVisualEffectView.popoverHost() helper——与 V4.77.0 ViewOptionsPopover 完全一致
        //   4 行 material/state/blendingMode + 3 行 layer 样式全抽到 helper
        let visualEffect = NSVisualEffectView.popoverHost()

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = Self.sectionSpacing
        outer.edgeInsets = NSEdgeInsets(
            top: Self.padding, left: Self.padding,
            bottom: Self.padding, right: Self.padding
        )
        outer.translatesAutoresizingMaskIntoConstraints = false

        // V4.61.0: 删顶部 header（"筛选" + "清除全部"）——macOS Photos 扁平 menu 风格
        //   "筛选" 与 anchor button "筛选" 语义重复
        //   "清除全部" 入口在 V4.36.x ActiveFiltersBar 已有——保留一处即可

        // V4.44.0: 删 NSSearchField——folder/tag 数量少无需过滤

        // V4.60.0: 内容区嵌入 NSScrollView——4 段全展开 + 14 folder + 14 tag 时 ~620pt
        //   接近窗口可视区，overflow 时静默截断——NSScroller 自动出现解决
        //   autohidesScrollers = true 让内容 < 580pt 时 scroller 自动隐藏
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // 内容区——可重建
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = Self.sectionSpacing
        contentStack = content
        rebuildContent()

        // V4.60.0: 文档视图——frame 布局决定滚动范围
        //   width = popover 内容宽（240 - 2*12 padding = 216）
        //   height = stack 实际需要的高度（fittingSize 自动算）
        let docWidth = Self.contentWidth - 2 * Self.padding
        content.frame = NSRect(x: 0, y: 0, width: docWidth, height: content.fittingSize.height)
        scrollView.documentView = content

        // V4.60.0: 高度上限——超过时显示 scroller
        //   580pt 是 macOS 标准 popover "可接受"最大高度（接近窗口可视区）
        scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 580).isActive = true

        outer.addArrangedSubview(scrollView)

        // V4.45.0: outer 嵌入 NSVisualEffectView
        //   NSVisualEffectView 自动在所有 subview 背后渲染 blur effect
        //   直接 addSubview 到 visualEffect 即可（不是 contentView.addSubview）
        visualEffect.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            outer.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            outer.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        self.view = visualEffect
    }

    /// 重建内容区
    /// V4.44.0: 移除搜索过滤逻辑——folder/tag 直接展示
    private func rebuildContent() {
        guard let content = contentStack else { return }
        // 清空旧内容
        for sub in content.arrangedSubviews {
            content.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        // 段 1: 文件夹
        // V4.61.0: 删段头 + 段头 icon + 1pt 分隔线（macOS Photos 扁平 menu 风格）
        //   段间靠 8pt 留白过渡（V4.64.0 才改 8pt，当前保持 12pt）
        //   V4.59.0: 段头始终显示——空时显示 placeholder，引导用户新建
        //     删段头后: 段内首项加 folder icon (makeFolderItemWithIcon) 标识"段类型"
        if allFolders.isEmpty {
            content.addArrangedSubview(makeEmptyStatePlaceholder(
                icon: "folder.badge.plus",
                message: "暂无文件夹\n右键侧边栏「我的文件夹」新建"
            ))
        } else {
            content.addArrangedSubview(PopoverItemFactory.makeOneColumnCheckList(items: allFolders) { folder in
                let button = PopoverItemFactory.makeCheckItem(
                    label: folder.name,
                    isOn: filterState.folders.contains(folder.id)
                ) { [weak self] in
                    self?.handleFolderToggle(folder.id)
                }
                self.folderButtons[folder.id] = button
                return button
            })
        }

        // 段 2: 标签
        // V4.61.0: 同上——删段头
        // V4.70.0: folder-tag 段间加 1pt hairline——区分两种语义不同的 item 集合
        //   folder 是"集合"——tag 是"标签"
        //   只在两段都不为空时加（避免 folder 段 + 空 tag placeholder 之间出现奇怪分隔）
        if !allFolders.isEmpty && !allTags.isEmpty {
            content.addArrangedSubview(makeSectionSeparator())
        }
        if allTags.isEmpty {
            content.addArrangedSubview(makeEmptyStatePlaceholder(
                icon: "tag",
                message: "暂无标签\n右键侧边栏「标签」新建"
            ))
        } else {
            content.addArrangedSubview(PopoverItemFactory.makeOneColumnCheckList(items: allTags) { tag in
                let button = PopoverItemFactory.makeCheckItem(
                    label: "#\(tag.name)",
                    isOn: filterState.tags.contains(tag.id)
                ) { [weak self] in
                    self?.handleTagToggle(tag.id)
                }
                self.tagButtons[tag.id] = button
                return button
            })
        }

        // 段 3: 形状（不参与搜索过滤）
        // V4.61.0: 删段头
        let shapeStack = PopoverItemFactory.makeSegmentRow()
        for shape in PhotoShape.allCases {
            let button = PopoverItemFactory.makeIconOnlySegmentItem(
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
        // V4.61.0: 删段头
        let ratingContainer = NSStackView()
        ratingContainer.orientation = .vertical
        ratingContainer.alignment = .leading
        ratingContainer.spacing = PopoverStyle.segmentGap
        ratingContainer.translatesAutoresizingMaskIntoConstraints = false

        let row1 = PopoverItemFactory.makeSegmentRow()
        // V4.46.0: "全部" 改用 circle icon——与带星评分项视觉对称
        //   之前纯文字 vs 其他带星——"全部" 看起来像 textbox 而非 button
        let noRating = PopoverItemFactory.makeIconOnlySegmentItem(
            icon: "circle",
            isActive: filterState.minRating == 0
        ) { [weak self] in
            self?.handleRatingToggle(0)
        }
        row1.addArrangedSubview(noRating)
        ratingButtons[0] = noRating
        // V4.46.0: 评分改纯 icon-only (去 "n+" 文字)——macOS Photos 风格
        //   之前 V4.45.1 makeIconTextSegmentItem + text "1+"——但 NSButton.imagePosition = .imageOnly
        //   抑制文字显示，截图里只看到星没数字
        //   改 makeIconOnlySegmentItem 纯 icon = 文字消失,只显星 (Photos 标准)
        // V4.69.0: 评分 ⭐ 创建时显式传 iconTintOverride = .systemYellow
        //   仿 macOS Photos 实际：所有 ⭐ 都是金色（无论 active/inactive）
        //   之前 V4.66.0 只改 updateState 内的 applySegmentStyle 调用——不生效
        for n in 1...2 {
            let button = PopoverItemFactory.makeIconOnlySegmentItem(
                icon: "star.fill",
                isActive: filterState.minRating == n,
                iconTintOverride: .systemYellow
            ) { [weak self] in
                self?.handleRatingToggle(n)
            }
            row1.addArrangedSubview(button)
            ratingButtons[n] = button
        }
        ratingContainer.addArrangedSubview(row1)

        let row2 = PopoverItemFactory.makeSegmentRow()
        for n in 3...5 {
            let button = PopoverItemFactory.makeIconOnlySegmentItem(
                icon: "star.fill",
                isActive: filterState.minRating == n,
                iconTintOverride: .systemYellow  // V4.69.0: 评分 ⭐ gold
            ) { [weak self] in
                self?.handleRatingToggle(n)
            }
            row2.addArrangedSubview(button)
            ratingButtons[n] = button
        }
        ratingContainer.addArrangedSubview(row2)
        content.addArrangedSubview(ratingContainer)
    }

    private func makeEmptyHint(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }

    /// V4.70.0: 段间 1pt hairline 分隔——区分 folder 集合 vs tag 标签两种语义
    ///   0.5pt separator + 18% primary + 上下各 6pt padding
    ///   不画整宽——只占 60% 宽，居左对齐
    private func makeSectionSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.alphaValue = 0.6  // 18% 视觉
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            // 上下各 6pt padding
            container.heightAnchor.constraint(equalToConstant: 12 + 1),
            // separator 居中 (vertical) + 60% 宽 + 偏左 12pt
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            separator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            separator.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.6, constant: -12),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
        return container
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
        // V4.41.1: 传 symbolName 让 applySegmentStyle 按状态 tint icon
        for (shape, button) in shapeButtons {
            PopoverItemFactory.applySegmentStyle(button, isActive: filterState.shapes.contains(shape), text: nil, symbolName: shape.icon)
        }
        for (rating, button) in ratingButtons {
            // 评分段无 icon（"1星" 等纯文字）——symbolName = nil
            let text = button.attributedTitle.string
            // V4.66.0: 评分段 inactive icon tint gold（仿 Photos ⭐ 实际风格）
            //   active 仍用 white（在 accent bg 上）——override 只影响 inactive
            PopoverItemFactory.applySegmentStyle(
                button,
                isActive: filterState.minRating == rating,
                text: text,
                iconTintOverride: .systemYellow
            )
        }
    }

    // MARK: - 子视图工厂

    /// V4.59.0 NEW: 空状态占位——folder/tag 段无内容时显示
    ///   icon + 提示文字，引导用户到侧边栏新建
    ///   Photos 风格：弱化灰、保持视觉一致（非"无内容"突现）
    private func makeEmptyStatePlaceholder(icon: String, message: String) -> NSView {
        let imageView = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage())
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .tertiaryLabelColor  // V4.43.0 范式：tertiary = 弱化

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        // 2 行提示：第 1 行"暂无文件夹"，第 2 行"右键侧边栏...新建"
        label.usesSingleLineMode = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
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
        // V4.41.1: 全部从 PopoverStyle 推——padding 2x, itemHeight 28
        //   padding 12pt × 2 = 24（top + bottom）
        //   item 28pt (V4.36.x 22pt → 28pt)
        //   segment 28pt (V4.36.x 26pt → 28pt)
        // V4.44.0: 删 searchSection——NSSearchField 移除后 popover 高度减 32pt
        let padding: CGFloat = PopoverStyle.padding * 2
        let header: CGFloat = headerHeight + 4
        let sectionHeader: CGFloat = 18
        let item: CGFloat = PopoverStyle.itemHeight
        let section: CGFloat = PopoverStyle.sectionSpacing
        let segment: CGFloat = PopoverStyle.itemHeight
        // V4.36.x: folder/tag 段 2 列——高度按列中较多那列算
        let folderColHeight = ceil(CGFloat(folders.count) / 2) * item
        let tagColHeight = ceil(CGFloat(tags.count) / 2) * item
        // V4.36.x #2: 评分段 2 行——高度 = 2 * segment + 1 * segmentGap
        let ratingBlock: CGFloat = 2 * segment + segmentGap
        let total: CGFloat =
            padding
            + header
            + (folders.isEmpty ? 0 : sectionHeader + folderColHeight + section)
            + (tags.isEmpty ? 0 : sectionHeader + tagColHeight + section)
            + sectionHeader + segment   // shape 单行
            + section
            + sectionHeader + ratingBlock
        return total
    }
}

// MARK: - V4.81.0: ClosureButton 已迁到 PopoverItemFactory.swift
//   原 private final class ClosureButton 改 internal（跨文件用）—— 删本文件实现
