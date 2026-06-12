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
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover      // macOS popover 专用材质
        visualEffect.state = .followsWindowActiveState
        visualEffect.blendingMode = .withinWindow  // V4.47.0: 暗色下更清透

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
            content.addArrangedSubview(makeOneColumnCheckList(items: allFolders) { folder in
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

        // 段 2: 标签
        // V4.61.0: 同上——删段头
        if allTags.isEmpty {
            content.addArrangedSubview(makeEmptyStatePlaceholder(
                icon: "tag",
                message: "暂无标签\n右键侧边栏「标签」新建"
            ))
        } else {
            content.addArrangedSubview(makeOneColumnCheckList(items: allTags) { tag in
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

        // 段 3: 形状（不参与搜索过滤）
        // V4.61.0: 删段头
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
        // V4.61.0: 删段头
        let ratingContainer = NSStackView()
        ratingContainer.orientation = .vertical
        ratingContainer.alignment = .leading
        ratingContainer.spacing = PopoverStyle.segmentGap
        ratingContainer.translatesAutoresizingMaskIntoConstraints = false

        let row1 = makeSegmentRow()
        // V4.46.0: "全部" 改用 circle icon——与带星评分项视觉对称
        //   之前纯文字 vs 其他带星——"全部" 看起来像 textbox 而非 button
        let noRating = makeIconOnlySegmentItem(
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
        for n in 1...2 {
            let button = makeIconOnlySegmentItem(
                icon: "star.fill",
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
            let button = makeIconOnlySegmentItem(
                icon: "star.fill",
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
        // V4.41.1: 传 symbolName 让 applySegmentStyle 按状态 tint icon
        for (shape, button) in shapeButtons {
            applySegmentStyle(button, isActive: filterState.shapes.contains(shape), text: nil, symbolName: shape.icon)
        }
        for (rating, button) in ratingButtons {
            // 评分段无 icon（"1星" 等纯文字）——symbolName = nil
            let text = button.attributedTitle.string
            // V4.66.0: 评分段 inactive icon tint gold（仿 Photos ⭐ 实际风格）
            //   active 仍用 white（在 accent bg 上）——override 只影响 inactive
            applySegmentStyle(
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

    /// checkbox + label 的 item
    /// V4.36.x #5: 统一文字颜色 labelColor——active 态用 checkbox + 浅蓝背景区分
    /// V4.58.0: 长 folder/tag 名截断——cell.lineBreakMode = .byTruncatingMiddle
    ///   之前直接传长名让 button 撑开列宽、2 列布局失衡
    ///   现在中间省略号截断——保留原数据，视觉上每列等宽不溢出
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
        // V4.58.0: 中间省略号截断（macOS Photos 风格——长文件夹名截中间"旅行照..."）
        button.cell?.lineBreakMode = .byTruncatingMiddle
        button.cell?.truncatesLastVisibleLine = true
        return button
    }

    /// 1 列 checkbox 列表——仿 macOS Photos 排序 popover 风格
    /// V4.63.0: 砍 2 列布局（之前 HStack + 2 VStack 复杂）——1 列 + fill 撑满宽度
    ///   - 2 列问题：fillEqually 对齐 + V4.58.0 byTruncatingMiddle 截断
    ///   - 1 列优势：每行独立视觉单元 + 无对齐问题
    ///   - 副作用：folder/tag 多时 popover 变高，V4.60.0 NSScrollView 兜底
    private func makeOneColumnCheckList<T: AnyObject, Button: NSButton>(
        items: [T],
        itemBuilder: (T) -> Button
    ) -> NSView {
        let vStack = NSStackView()
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.distribution = .fill  // V4.63.0: 子 view 撑满 VStack 宽度
        vStack.spacing = 2  // V4.63.0: 1 列时 row 间距 2pt 紧凑
        vStack.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            vStack.addArrangedSubview(itemBuilder(item))
        }
        return vStack
    }

    /// 2 列紧凑列表：HStack + 2 VStack（左列先满）
    /// V4.42.0: VStack spacing 2 → PopoverStyle.columnRowGap (4) — checkbox 行间更舒展
    /// V4.63.0: 砍——1 列布局替代
    @available(*, unavailable, message: "V4.63.0 砍 2 列布局——用 makeOneColumnCheckList")
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
        leftVStack.spacing = PopoverStyle.columnRowGap
        leftVStack.translatesAutoresizingMaskIntoConstraints = false
        for item in leftItems {
            leftVStack.addArrangedSubview(itemBuilder(item))
        }

        let rightVStack = NSStackView()
        rightVStack.orientation = .vertical
        rightVStack.alignment = .leading
        rightVStack.spacing = PopoverStyle.columnRowGap
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
        stack.spacing = PopoverStyle.segmentGap
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
    /// V4.41.1: 改为按状态动态 tint——active 白、inactive labelColor
    ///   之前预染色白色 + 25% 黑底 = inactive 状态白字白 icon 视觉糊
    ///   现在 6% black 底 + labelColor icon = Photos 风格"未选"感
    private func makeIconOnlySegmentItem(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: "", action: action)
        button.bezelStyle = .recessed
        // V4.41.1: 不预染色——把 symbol name 传给 applySegmentStyle 让它按状态 tint
        applySegmentStyle(button, isActive: isActive, text: nil, symbolName: icon)
        return button
    }

    /// icon + text segment item
    /// V4.45.1: 评分段改用真 ⭐ SF Symbol "star.fill" + "n+" 文字
    ///   之前是 "n星" 纯文字——现在视觉上一眼是评分筛选
    ///   Photos 风格：实心星 + 数字 = 表达"≥N 星"语义
    private func makeIconTextSegmentItem(
        icon: String?,
        text: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> NSButton {
        let button = ClosureButton(title: "", action: action)
        button.bezelStyle = .recessed
        applySegmentStyle(button, isActive: isActive, text: text, symbolName: icon)
        return button
    }

    // MARK: - 状态同步

    /// V4.41.1: 全部颜色 + 字号 token 化——与 ViewOptions popoverSegmentItem 对齐
    ///   - active: accent 底 + 白字/icon（PopoverStyle.activeBackgroundAppKit + .activeTextAppKit）
    ///   - inactive: 6% primary 底 + labelColor 字（PopoverStyle.inactiveBackgroundAppKit + .inactiveTextAppKit）
    ///   - 之前 V4.36.x #5 写"永远白" + 25% 黑底——与 ViewOptions 不一致 + 暗色下 25% 黑底偏暗
    ///   - symbolName: 可选——传非 nil 时按状态动态 tint icon（active 白、inactive labelColor）
    /// V4.66.0: 加 iconTintOverride 参数——评分段 inactive 显式 tint gold
    ///   Photos 实际：所有 ⭐ 都是金色，无论 active/inactive
    ///   之前走默认 inactiveTextAppKit (labelColor) → 视觉上是黑色 ⭐
    private func applySegmentStyle(
        _ button: NSButton,
        isActive: Bool,
        text: String?,
        symbolName: String? = nil,
        iconTintOverride: NSColor? = nil
    ) {
        // 1. 文字：active 白 / inactive labelColor（系统色，暗色自动适配）
        if let text = text {
            let color = isActive ? PopoverStyle.activeTextAppKit : PopoverStyle.inactiveTextAppKit
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.systemFont(ofSize: PopoverStyle.headerFontSize, weight: .medium)
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString()
        }

        // 2. icon：按状态动态 tint（不是预染色）——V4.41.1 修复
        // V4.47.0: 修复 star/circle icon 不可见 bug——paletteColors 在 .followsWindowActiveState
        //   transl popover 下渲染异常（截图里 5 个评分项 + "全部" 全部显示为空方块）
        //   改用 contentTintColor 方式——更标准也稳定
        if let symbol = symbolName {
            // V4.66.0: inactive 状态可显式 override icon tint（评分段用 gold）
            //   active 仍用 activeTextAppKit (white) — 在 accent bg 上保持对比
            let iconColor: NSColor
            if isActive {
                iconColor = PopoverStyle.activeTextAppKit
            } else if let override = iconTintOverride {
                iconColor = override
            } else {
                iconColor = PopoverStyle.inactiveTextAppKit
            }
            let sizeConfig = NSImage.SymbolConfiguration(
                pointSize: PopoverStyle.iconFontSize,
                weight: .medium
            )
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(sizeConfig)
            button.image = img
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            // V4.47.0: contentTintColor 替代 paletteColors——更可靠的 tint 方式
            //   NSImage(systemSymbolName:) 返回 template image, contentTintColor 直接上色
            button.contentTintColor = iconColor
        } else {
            button.image = nil
        }

        // 3. 背景：active 实色 accent / inactive 完全透明
        //   V4.65.0: 砍 inactive 14% primary 背景——在 V4.45.0 transl material popover 上
        //   14% 视觉仅 ~5%（V4.46.0 注释），实际看起来是"黑底胶囊"——用户反馈
        //   macOS Photos 实际：inactive = 完全透明，只靠 active 视觉锤区分
        //   副作用：3 个形状 icon 平铺视觉"轻"——但 Photos 排序 popover 也是这样
        // V4.43.1: NSAnimationContext 包裹 bezelColor 变更——0.15s easeInOut 平滑
        //   SwiftUI 用 .animation(.easeInOut(duration:), value:)，AppKit 需手动
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = PopoverStyle.stateTransitionDuration
        if isActive {
            button.bezelColor = PopoverStyle.activeBackgroundAppKit
        } else {
            // V4.65.0: inactive = .clear 透明——之前 14% primary 在 transl 上视觉过弱
            button.bezelColor = .clear
        }
        NSAnimationContext.endGrouping()
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
