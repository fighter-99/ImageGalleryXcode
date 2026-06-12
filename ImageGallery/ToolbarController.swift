//
//  ToolbarController.swift
//  ImageGallery
//
//  V4.8.0 NEW: NSToolbar (AppKit) 集成——macOS 原生 Photos.app 风格
//
//  背景：V4.7.x 7 个 commit 试图用 SwiftUI .toolbar 实现 Photos.app 风格，
//  最终确认 SwiftUI .toolbar 在 macOS 是降级实现：
//    - .principal placement 强制加 section 背景（不可覆盖）
//    - .primaryAction 在 macOS 不解释为右上角
//    - .toolbarBackground(.hidden) 任何 scope 都不覆盖
//  Photos.app / Finder / Mail 都用 NSToolbar (AppKit) 不是 SwiftUI .toolbar。
//
//  设计：
//  - ToolbarController 是 NSToolbarDelegate，定义所有 toolbar items
//  - 5 actions + sidebar toggle 是简单 NSToolbarItem (image + target/action)
//  - Search field 用 NSSearchToolbarItem (V4.8.1 替换 NSHostingView 包 ToolbarSearchField)
//  - Action 桥接用 closure：ContentView 设置，NSToolbar 触发
//  - 状态桥接 (enabled/disabled) 通过 ToolbarController.update* 方法
//
//  Photos.app 视觉特征：
//  - .iconOnly display mode（V4.7.1-V4.7.7 .controlSize(.regular) 适配）
//  - section 背景由 NSToolbar 控制（可控，不像 SwiftUI 强制）
//  - flexible space 居中 5 actions
//

import AppKit
import SwiftUI

@MainActor
final class ToolbarController: NSObject, NSToolbarDelegate, NSPopoverDelegate {
    /// 单例——NSToolbarDelegate 是 weak 引用，必须有强引用
    static let shared = ToolbarController()

    // MARK: - Action 桥接（ContentView 设置 closure）

    var onToggleSidebar: (() -> Void)?
    // V5.7: 砍 onToggleFavorite——工具栏 ❤ 收藏按钮移除
    var onBatchExport: (() -> Void)?
    var onDelete: (() -> Void)?
    var onImport: (() -> Void)?
    var onQuickLook: (() -> Void)?   // V4.37.1 NEW: ⌘Y Quick Look（ContentView 接 quickLookController）
    var onPrev: (() -> Void)?        // V4.37.2 NEW: ⌘[ 上一张（ContentView 接 goPrev）
    var onNext: (() -> Void)?        // V4.37.2 NEW: ⌘] 下一张（ContentView 接 goNext）
    // V4.9.1: 删 onShowViewOptions closure——改用 viewOptionsContentProvider + NSPopover

    // MARK: - Search field 桥接

    /// NSSearchField 强引用——用于 SwiftUI @State → NSSearchField 同步
    /// NSSearchField 由 NSToolbar 在需要时构造（NSToolbarItem.view 懒加载）
    /// 这里保存引用是为了 ContentView 通过 setSearchText 主动更新 stringValue
    private(set) weak var searchField: NSSearchField?

    /// NSSearchField → SwiftUI @State 同步（用户输入时）
    var onSearchTextChanged: ((String) -> Void)?

    // MARK: - View options popover 桥接（V4.9.1 NEW）

    /// V4.9.1: ContentView 提供 popover 内容（NSHostingController 包 SwiftUI ViewOptionsPopover）
    /// 之前 V4.8.0 迁移 NSToolbar 时丢了 .popover modifier——action 只 toggle 状态无 popover 显示
    /// 现在用 NSPopover + NSHostingController 动态显示
    var viewOptionsContentProvider: (() -> NSViewController)?

    /// V4.9.1: View Options popover 强引用（避免被释放）
    /// transient 行为下点击外部自动关闭
    private var viewOptionsPopover: NSPopover?

    // MARK: - Filter popover 桥接（V4.36.x + V4.89.0 重构）——FilterPopoverCoordinator 接管

    /// V4.89.0: ContentView 提供 coordinator 工厂（接收 folders/tags + onStateChange）
    ///   coordinator 内部管 顶层 + 4 子 popover lifecycle
    ///   ToolbarController 只持 coordinator 强引用
    var filterCoordinatorFactory: ((@escaping (FilterState) -> Void) -> FilterPopoverCoordinator)?

    /// V4.90.0: Filter popover coordinator 强引用（避免被释放）
    private var filterPopoverCoordinator: FilterPopoverCoordinator?

    /// V4.36.x: 激活筛选总数（用于工具栏 hover tooltip 角标 "筛选 (N)"）
    /// ContentView 通过 .onChange(of: filterState.activeCount) 同步此值
    var filterActiveCount: Int = 0 {
        didSet { updateFilterBadge() }
    }

    /// V4.54.0 NEW: filter 按钮激活状态——决定 icon + tint 视觉锤
    ///   filterActiveCount > 0 时为 true
    ///   computed property（而非独立 didSet）——保证永远与 filterActiveCount 同步，无须 ContentView 额外 push
    ///   仿 V4.37.4 TitlebarAccessoryController.setActive 模式（双 symbol + tint）
    var filterIsActive: Bool { filterActiveCount > 0 }

    /// V4.36.x: 工具栏筛选按钮的 SwiftUI view provider（暂未使用——V4.36.x 回归 NSButton 风格）
    ///   用 SwiftUI .popover() 而非 NSPopover，避免窗口裁切
    ///   ContentView 设置时 return NSHostingView(rootView: FilterToolbarButton(...))
    var filterButtonViewProvider: (() -> NSView)?

    // MARK: - 状态桥接

    /// 4 actions 的 enabled 状态
    /// V5.7: 砍 favoriteEnabled——工具栏 ❤ 收藏按钮移除
    var exportEnabled: Bool = false {
        didSet { updateItemEnabled(.export, enabled: exportEnabled) }
    }
    var deleteEnabled: Bool = false {
        didSet { updateItemEnabled(.delete, enabled: deleteEnabled) }
    }
    /// V4.37.1 NEW: Quick Look 仅在单选时可用（多选/无选时灰显）
    var quickLookEnabled: Bool = false {
        didSet { updateItemEnabled(.quickLook, enabled: quickLookEnabled) }
    }

    weak var toolbar: NSToolbar?

    // 缓存 NSToolbarItem 用于状态更新
    private var itemCache: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

    private override init() {
        super.init()
    }

    // MARK: - Item Identifiers

    enum Identifier: String {
        case sidebarToggle
        case search
        case flexibleSpace
        // V5.7: 砍 favorite case——工具栏 ❤ 收藏按钮移除（走右键菜单评分 / 筛选 popover）
        case export
        case delete
        case importItem      // 避开 `import` 关键字
        case filter          // V4.36.x NEW: 工具栏筛选按钮
        case viewOptions
        case quickLook       // V4.37.1 NEW: ⌘Y Quick Look（macOS Finder/Photos 标准）

        var nsIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(rawValue: rawValue)
        }
    }

    // MARK: - NSToolbarDelegate

    /// 默认 item 顺序——决定 toolbar 的视觉布局
    /// sidebar | search | flex | quickLook | export | delete | import | filter | viewOptions
    /// V4.36.x: 在 importItem 之后、viewOptions 之前插入 filter（import→filter→viewOptions 形成设置组）
    /// V4.37.1: 在 favorite 之后插入 quickLook（"看"的语义紧邻 favorite/"标记"语义）
    /// V5.7: 砍 favorite 项——侧栏/工具栏都不再放收藏入口（走右键菜单评分 / 筛选 popover）
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Identifier.sidebarToggle.nsIdentifier,
            Identifier.search.nsIdentifier,
            Identifier.flexibleSpace.nsIdentifier,
            Identifier.quickLook.nsIdentifier,  // V4.37.1 NEW
            Identifier.export.nsIdentifier,
            Identifier.delete.nsIdentifier,
            Identifier.importItem.nsIdentifier,
            Identifier.filter.nsIdentifier,
            Identifier.viewOptions.nsIdentifier
        ]
    }

    /// 允许的 items——customize toolbar 时用户可拖入的 items
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    /// 单个 item 的创建
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let id = Identifier(rawValue: itemIdentifier.rawValue) else { return nil }

        let item: NSToolbarItem?
        switch id {
        case .sidebarToggle:
            item = makeSimpleItem(
                id: id,
                image: "sidebar.leading",
                // V4.14.0: 本地化——之前 V4.8.0 硬编码英文，hover tooltip + Customize Toolbar 面板显示英文
                label: "切换侧边栏",
                action: #selector(handleToggleSidebar)
            )
        // V5.7: 砍 .favorite case——工具栏 ❤ 收藏按钮移除
        case .quickLook:  // V4.37.1 NEW
            // V4.37.1: ⌘Y 快速查看——macOS Finder/Photos 标准 eye 图标
            //   复用 makeSimpleItem 模式，行为与 5 actions 一致
            item = makeSimpleItem(
                id: id,
                image: "eye",
                label: "快速查看",
                action: #selector(handleShowQuickLook)
            )
        case .export:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.up",
                label: "导出",
                action: #selector(handleBatchExport)
            )
        case .delete:
            item = makeSimpleItem(
                id: id,
                image: "trash",
                label: "删除",
                action: #selector(handleDelete)
            )
        case .importItem:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.down",
                label: "导入",
                action: #selector(handleImport)
            )
        case .filter:  // V4.36.x NEW + V4.54.0 状态感知升级
            // V4.36.x: 回归 NSButton 风格——与其他 5 actions 完全一致
            //   SwiftUI popover 在 NSToolbar 里点击响应不可靠（事件被 toolbar 拦截）
            // V4.54.0: filter 按钮需要状态感知（仿 V4.37.4 titlebar accessory）——单独构造
            //   原因：双 SF Symbol + tint accent 需要保留 button 引用以便 setActive 时更新
            item = makeFilterItem(id: id)
        case .viewOptions:
            item = makeSimpleItem(
                id: id,
                image: "rectangle.3.offgrid",
                label: "视图选项",
                action: #selector(handleShowViewOptions)
            )
        case .search:
            // V4.8.1: 用 NSSearchToolbarItem 替代 NSHostingView 包 SwiftUI ToolbarSearchField
            item = makeSearchItem(id: id)
        case .flexibleSpace:
            item = nil  // flexible space 由 NSToolbar 系统处理
        }

        if let item = item {
            itemCache[itemIdentifier] = item
        }
        return item
    }

    /// Validate items（用于更新 enabled 状态）
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let id = Identifier(rawValue: item.itemIdentifier.rawValue) else { return true }
        switch id {
        // V5.7: 砍 .favorite case
        case .export: return exportEnabled
        case .delete: return deleteEnabled
        case .quickLook: return quickLookEnabled   // V4.37.1 NEW
        default: return true
        }
    }

    // MARK: - 状态更新

    private func updateItemEnabled(_ id: Identifier, enabled: Bool) {
        guard let item = itemCache[id.nsIdentifier] else { return }
        item.isEnabled = enabled
    }

    /// 全部状态更新（ContentView 在 .onChange 调用）
    /// V5.7: 砍 favoriteEnabled 赋值——工具栏 ❤ 已移除
    func updateAllStates(hasSelection: Bool, hasMultipleSelection: Bool) {
        exportEnabled = hasSelection
        deleteEnabled = hasSelection
        // V4.37.1: Quick Look 仅在单张选中时可用（多张 / 0 张 都灰显）
        quickLookEnabled = hasSelection && !hasMultipleSelection
    }

    // MARK: - Item 工厂

    private func makeSimpleItem(id: Identifier, image: String, label: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""  // V4.8.3: 空 label + displayMode = .iconOnly 双重保险隐藏文字
        item.paletteLabel = label  // Customize Toolbar 面板仍显示 label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.isBordered = true

        // V4.9.2: 显式创建 NSButton 作为 item.view
        //   原因: 简单 NSToolbarItem（只有 image + target/action）的 item.view = nil
        //   NSToolbar 内部会生成 NSButton 但不暴露给 item.view
        //   NSPopover.show(relativeTo:of:) 需要非 nil anchor view——否则 popover 创建后被 ARC 释放
        //   显式 NSButton 让 item.view 非 nil，popover 可正确锚定
        //   同时让所有 5 actions 行为一致（之前 sidebar toggle 也有此问题，只是不需要 popover 没暴露）
        let button = NSButton()
        button.image = item.image
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = action
        button.bezelStyle = .recessed  // 跟 NSToolbar 系统按钮风格一致
        button.toolTip = label
        button.isBordered = true
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        item.view = button

        return item
    }

    /// V4.54.0 NEW: 工具栏 filter 按钮——双 SF Symbol + setActive 视觉锤
    ///   仿 V4.37.4 TitlebarAccessoryController 双 symbol + tint 模式
    ///   inactive: line.3.horizontal.decrease (outline)
    ///   active:   line.3.horizontal.decrease.circle.fill (fill + circle 高亮)
    ///   Photos.app 风格——toggle 按钮 active 时 icon 切填充 + tint 强调色
    private func makeFilterItem(id: Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""  // V4.8.3: 空 label + displayMode = .iconOnly 双重保险隐藏文字
        item.paletteLabel = "筛选"  // Customize Toolbar 面板显示
        item.toolTip = "筛选"  // 初值；filterActiveCount > 0 时被 updateFilterBadge 覆盖
        item.target = self
        item.action = #selector(handleShowFilter)
        item.isBordered = true

        let button = NSButton()
        button.bezelStyle = .recessed  // 跟 NSToolbar 系统按钮风格一致
        button.toolTip = "筛选"
        button.target = self
        button.action = #selector(handleShowFilter)
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // V4.54.0: 初值同步 icon——setActive 时再切
        updateFilterButtonImage(button: button)
        item.view = button

        return item
    }

    /// V4.54.0 NEW: 同步 filter button image + tint——所有 filterIsActive 变化走这里
    ///   仿 V4.37.4 TitlebarAccessoryController.updateButtonImage 模式
    ///   icon: inactiveSymbol ↔ activeSymbol（line.3.horizontal.decrease ↔ ...circle.fill）
    ///   tint: 系统默认（nil）↔ .controlAccentColor（强调色）
    private func updateFilterButtonImage(button: NSButton? = nil) {
        let btn = button ?? (itemCache[Identifier.filter.nsIdentifier]?.view as? NSButton)
        guard let btn = btn else { return }
        let symbol = filterIsActive
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease"
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "筛选")
        // V4.54.0: 激活时 tint 强调色（Photos.app 同款——toggle 按钮 active 时显色）
        // nil = 系统默认（保持与其他 5 actions 不主动 tint 一致）
        btn.contentTintColor = filterIsActive ? .controlAccentColor : nil
    }

    // MARK: - V5.9.1: popover 打开/关闭时按钮视觉反馈

    /// V5.9.1: popover 打开/关闭时改变工具栏按钮 icon + tint
    ///   V5.9 用 NSButton.state 失败原因：item.view as? NSButton 对默认 NSToolbarItem 返回 nil
    ///   （view options 用 makeSimpleItem 创建默认 item——没有 NSButton）
    ///   改方案：直接改 item.image（icon）+ item.isBordered 控 pressed 外观
    ///   - isOpen = true:  icon 切填充变体 + item.isBordered = true 显 pressed 背景
    ///   - isOpen = false: icon 恢复默认 + item.isBordered = false 隐背景
    ///   对 NSButton 类（filter）也走同路径——统一用 item 级别 API
    private func setItemPressed(_ id: Identifier, isOpen: Bool, openIcon: String, defaultIcon: String) {
        guard let item = itemCache[id.nsIdentifier] else { return }
        // 切 icon
        item.image = NSImage(systemSymbolName: isOpen ? openIcon : defaultIcon, accessibilityDescription: item.toolTip)
        // 切 border（pressed 视觉）
        item.isBordered = isOpen
    }

    // MARK: - V5.9: NSPopoverDelegate

    /// V5.9.1: popover 关闭时（用户点外部 / 主动 close）——同步按钮 icon + border
    ///   - popover 是 view options：setItemPressed(.viewOptions, false)
    ///   - popover 是 filter top（coordinator 内部的 topPopover）：setItemPressed(.filter, false)
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        // 区分是哪个 popover 关闭
        if popover === viewOptionsPopover {
            setItemPressed(.viewOptions, isOpen: false,
                          openIcon: "rectangle.3.offgrid.fill",
                          defaultIcon: "rectangle.3.offgrid")
            viewOptionsPopover = nil
        } else if let coordinator = filterPopoverCoordinator,
                  let topPopover = coordinator.topPopover,
                  popover === topPopover {
            // V5.9.1: 顶层 filter popover 关闭（用户点外部 / coordinator.closeAll）
            setItemPressed(.filter, isOpen: false,
                          openIcon: "line.3.horizontal.decrease.circle.fill",
                          defaultIcon: "line.3.horizontal.decrease")
        }
    }

    private func makeSearchItem(id: Identifier) -> NSToolbarItem {
        // V4.8.2: 用 NSSearchToolbarItem 替代裸 NSToolbarItem + NSSearchField
        //   NSSearchToolbarItem (macOS 11+) 是 NSToolbar 专用 search item 包装
        //   自动有合适的背景样式 + 系统 placeholder + clear button + 展开/收起的 toolbar 行为
        //   Photos.app / Finder / Mail / Notes 都用这个
        let searchItem = NSSearchToolbarItem(itemIdentifier: id.nsIdentifier)
        searchItem.label = ""  // V4.8.3: 不显示 "Search" 文字
        // V4.14.0: 本地化——之前 V4.8.x 硬编码英文，Customize Toolbar 面板 + hover tooltip 显示英文
        searchItem.paletteLabel = "搜索"
        searchItem.toolTip = "搜索照片、标签、笔记"

        let searchField = searchItem.searchField
        searchField.placeholderString = "搜索照片、标签…"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(handleSearchAction)

        // V4.8.2: 加宽搜索框——成为 toolbar 主要元素
        //   NSSearchToolbarItem.preferredWidthForSearchField 控制搜索框展开宽度
        searchItem.preferredWidthForSearchField = 280

        // 监听文本变化——同 V4.8.1，NSSearchField 继承自 NSSearchField
        NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification,
            object: searchField,
            queue: .main
        ) { [weak self, weak searchField] _ in
            guard let self = self, let searchField = searchField else { return }
            self.onSearchTextChanged?(searchField.stringValue)
        }

        self.searchField = searchField
        return searchItem
    }

    // MARK: - 外部 API（SwiftUI @State → NSSearchField 同步）

    /// ContentView 在 .onChange(of: searchText) 调用
    /// 把 SwiftUI @State 同步到 NSSearchField（外部状态变化时）
    func setSearchText(_ text: String) {
        // 避免无限循环：只在 NSSearchField 当前值与新值不同时更新
        guard searchField?.stringValue != text else { return }
        searchField?.stringValue = text
    }

    // MARK: - Action Handlers

    @objc private func handleToggleSidebar() { onToggleSidebar?() }
    // V5.7: 砍 handleToggleFavorite——工具栏 ❤ 收藏按钮移除
    @objc private func handleBatchExport() { onBatchExport?() }
    @objc private func handleDelete() { onDelete?() }
    @objc private func handleImport() { onImport?() }
    @objc private func handleShowQuickLook() { onQuickLook?() }   // V4.37.1 NEW
    @objc private func handleNavigatePrev() { onPrev?() }          // V4.37.2 NEW
    @objc private func handleNavigateNext() { onNext?() }          // V4.37.2 NEW
    @objc private func handleShowViewOptions() {
        // V4.9.1: 不用 onShowViewOptions closure——直接用 NSPopover 显示 ViewOptionsPopover
        //   行为：再次点击按钮 → 关闭 popover（toggle）
        //   点外部 → 自动关闭（.transient）
        if let popover = viewOptionsPopover, popover.isShown {
            popover.close()
            viewOptionsPopover = nil
            setItemPressed(.viewOptions, isOpen: false,
                          openIcon: "rectangle.3.offgrid.fill",
                          defaultIcon: "rectangle.3.offgrid")
            return
        }

        guard let contentProvider = viewOptionsContentProvider,
              let item = itemCache[Identifier.viewOptions.nsIdentifier],
              let anchorView = item.view else {
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient  // 点外部自动关闭
        popover.delegate = self  // V5.9: 监听 popoverDidClose 同步按钮状态
        popover.contentViewController = contentProvider()
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        self.viewOptionsPopover = popover
        // V5.9.1: icon 切填充变体 + border 显 pressed——"我正被使用"
        setItemPressed(.viewOptions, isOpen: true,
                      openIcon: "rectangle.3.offgrid.fill",
                      defaultIcon: "rectangle.3.offgrid")
    }
    @objc private func handleSearchAction() {
        // Enter 键触发——已通过 textDidChangeNotification 实时同步
        // 这里留作 future: 触发"提交搜索"（可能高亮首个结果等）
    }

    // MARK: - Filter popover handlers（V4.36.x NEW）

    /// V4.36.x: 显示/隐藏 Filter popover
    ///   完全仿 V4.9.1 handleShowViewOptions 模式：NSPopover + item.view 锚定
    ///   NSPopover 自动处理屏幕边界，比 SwiftUI .popover() 在 NSToolbar 里更可靠
    @objc private func handleShowFilter() {
        // V4.90.0: 切换关闭（再点 toolbar 按钮 toggle）——coordinator 内部管 toggle
        if let coordinator = filterPopoverCoordinator, coordinator.isTopShown {
            coordinator.closeAll()
            filterPopoverCoordinator = nil
            // V5.9.1: 恢复默认 icon + 隐藏 border——"我不再被使用"
            setItemPressed(.filter, isOpen: false,
                          openIcon: "line.3.horizontal.decrease.circle.fill",
                          defaultIcon: "line.3.horizontal.decrease")
            return
        }

        guard let item = itemCache[Identifier.filter.nsIdentifier],
              let anchorView = item.view else {
            return
        }

        // V4.90.0: 创建 coordinator + 调 showTop
        //   ContentView 注入 factory + onStateChange closure
        let coordinator = filterCoordinatorFactory?({ [weak self] newState in
            // V4.90.0: 写回 ContentView filterState——coordinator 不直接管 ContentView state
            //   实际由 ContentView .onChange 推——coordinator 只管 popover lifecycle
            _ = newState
            _ = self
        })
        coordinator?.showTop(anchoredTo: anchorView)
        filterPopoverCoordinator = coordinator
        // V5.9.1: icon 切填充变体（与 filterIsActive 视觉一致）+ border 显 pressed
        //   注：filterIsActive 也走同 icon——打开时强制显示 active icon
        setItemPressed(.filter, isOpen: true,
                      openIcon: "line.3.horizontal.decrease.circle.fill",
                      defaultIcon: "line.3.horizontal.decrease")
    }

    /// V4.36.x + V4.54.0: 同步激活筛选数 + active 视觉锤到 filter item
    ///   V4.36.x: 改 tooltip "筛选 (N)"
    ///   V4.54.0: 同时调 updateFilterButtonImage 切 icon (outline ↔ fill.circle) + tint 强调色
    ///   V4.8.3: displayMode = .iconOnly 不显示 title，故用 tooltip 显示 "筛选 (N)"
    private func updateFilterBadge() {
        guard let item = itemCache[Identifier.filter.nsIdentifier] else { return }
        item.toolTip = filterActiveCount > 0 ? "筛选 (\(filterActiveCount))" : "筛选"
        updateFilterButtonImage()  // V4.54.0: 同步 icon + tint
    }
}
