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
import os

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
    var onQuickLook: (() -> Void)?   // V4.37.1 NEW: ⌘Y Quick Look → ContentView.showQuickLook() → V5.42 改走 enterImmersiveFromSelection()
    var onPrev: (() -> Void)?        // V4.37.2 NEW: ⌘[ 上一张（ContentView 接 goPrev）
    var onNext: (() -> Void)?        // V4.37.2 NEW: ⌘] 下一张（ContentView 接 goNext）
    // V5.24 NEW: 布局模式 + 密度 toolbar 桥接
    //   之前只在 ViewOptionsPopover (popover) 里——V5.24 集成到 NSToolbar 直操作
    //   镜像 macOS Photos: toolbar 有 density slider + view mode segment
    var onLayoutModeChange: ((ThumbnailLayoutMode) -> Void)?
    var onDensityChange: ((CGFloat) -> Void)?
    // V5.39.3 NEW: 排序 toolbar 桥接——之前藏在 ViewOptionsPopover 里
    //   提到独立 toolbar 按钮后直接闭包回调
    var onSortOptionChange: ((SortOption) -> Void)?

    // MARK: - Search field 桥接

    /// NSSearchField 强引用——用于 SwiftUI @State → NSSearchField 同步
    /// NSSearchField 由 NSToolbar 在需要时构造（NSToolbarItem.view 懒加载）
    /// 这里保存引用是为了 ContentView 通过 setSearchText 主动更新 stringValue
    private(set) weak var searchField: NSSearchField?

    /// NSSearchField → SwiftUI @State 同步（用户输入时）
    var onSearchTextChanged: ((String) -> Void)?

    // MARK: - V5.39.3: 删 View options popover 桥接
    //   布局模式 + 排序都搬到独立 toolbar 按钮, ViewOptionsPopover 空壳, 整段删
    //   - viewOptionsContentProvider 删
    //   - viewOptionsPopover 删
    //   - handleShowViewOptions 删
    //   - popoverDidClose 中对 viewOptionsPopover 的处理删

    // MARK: - Filter popover 桥接（V4.36.x + V4.89.0 重构）——FilterPopoverCoordinator 接管

    /// V4.89.0: ContentView 提供 coordinator 工厂（接收 folders/tags + onStateChange）
    ///   coordinator 内部管 顶层 + 4 子 popover lifecycle
    ///   ToolbarController 只持 coordinator 强引用
    var filterCoordinatorFactory: ((@escaping (FilterState) -> Void) -> FilterPopoverCoordinator)?

    /// V4.90.0: Filter popover coordinator 强引用（避免被释放）
    private var filterPopoverCoordinator: FilterPopoverCoordinator?

    /// V5.72 NEW: LayoutMode popover 强引用——避免被 ARC 释放
    ///   仿 V4.90.0 filterPopoverCoordinator pattern
    private var layoutModePopover: NSPopover?

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

    // V5.66: 改 internal (去掉 private)——测试要能 new ToolbarController() 验证字段 invariant
    //   单例访问仍走 static let shared
    override init() {
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
        // V5.39.3: 砍 viewOptions case——布局模式 + 排序都搬到独立 toolbar 按钮
        //   popover 只剩空壳, 直接删
        // V5.39.3 NEW: 布局模式 toolbar 按钮 (方格 / 按比例 下拉菜单)
        case layoutModeMenu
        // V5.39.3 NEW: 缩略图大小 toolbar 按钮 (4 档下拉菜单)——替代 V5.31 NSSegmentedControl
        case densityMenu
        // V5.39.3 NEW: 排序 toolbar 按钮 (导入时间/文件名/文件大小/自定义 下拉菜单)
        case sortMenu
        case quickLook       // V4.37.1 NEW: ⌘Y Quick Look（macOS Finder/Photos 标准）
        // V5.39.3: 砍 case density (V5.24 连续 slider) + case layoutMode (V5.24 3-icon segment)
        //   全部走 NSMenu 下拉 (densityMenu + layoutModeMenu)

        var nsIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(rawValue: rawValue)
        }
    }

    // MARK: - NSToolbarDelegate

    /// 默认 item 顺序——决定 toolbar 的视觉布局
    /// sidebar | search | flex | quickLook | export | delete | import | filter | layoutMode | density | sort
    /// V4.36.x: 在 importItem 之后插入 filter（import→filter 形成操作组）
    /// V4.37.1: 在 favorite 之后插入 quickLook（"看"的语义紧邻 favorite/"标记"语义）
    /// V5.7: 砍 favorite 项——侧栏/工具栏都不再放收藏入口（走右键菜单评分 / 筛选 popover）
    /// V5.39.3: filter 之后插入 3 个 NSMenu 下拉按钮 (布局模式/缩略图大小/排序)——viewOptions 砍
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
            Identifier.layoutModeMenu.nsIdentifier,  // V5.39.3: 从 viewOptions 提到 toolbar
            Identifier.densityMenu.nsIdentifier,     // V5.39.3: NSSegmentedControl → NSMenu
            Identifier.sortMenu.nsIdentifier         // V5.39.3: 从 viewOptions 提到 toolbar
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
                label: Copy.toolbarToggleSidebar,
                action: #selector(handleToggleSidebar)
            )
        // V5.7: 砍 .favorite case——工具栏 ❤ 收藏按钮移除
        case .quickLook:  // V4.37.1 NEW
            // V4.37.1: ⌘Y 快速查看——macOS Finder/Photos 标准 eye 图标
            //   复用 makeSimpleItem 模式，行为与 5 actions 一致
            item = makeSimpleItem(
                id: id,
                image: "eye",
                label: Copy.quickLook,
                action: #selector(handleShowQuickLook)
            )
        case .export:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.up",
                label: Copy.toolbarExport,
                action: #selector(handleBatchExport)
            )
        case .delete:
            item = makeSimpleItem(
                id: id,
                image: "trash",
                label: Copy.delete,
                action: #selector(handleDelete)
            )
        case .importItem:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.down",
                label: Copy.toolbarImport,
                action: #selector(handleImport)
            )
        case .filter:  // V4.36.x NEW + V4.54.0 状态感知升级
            // V4.36.x: 回归 NSButton 风格——与其他 5 actions 完全一致
            //   SwiftUI popover 在 NSToolbar 里点击响应不可靠（事件被 toolbar 拦截）
            // V4.54.0: filter 按钮需要状态感知（仿 V4.37.4 titlebar accessory）——单独构造
            //   原因：双 SF Symbol + tint accent 需要保留 button 引用以便 setActive 时更新
            item = makeFilterItem(id: id)
        case .search:
            // V4.8.1: 用 NSSearchToolbarItem 替代 NSHostingView 包 SwiftUI ToolbarSearchField
            item = makeSearchItem(id: id)
        case .flexibleSpace:
            item = nil  // flexible space 由 NSToolbar 系统处理
        case .layoutModeMenu:  // V5.39.3 NEW: 方格/按比例/方格(完整) 下拉菜单
            // V5.46: defaultImage 跟 layoutMode 走——初次创建时用默认 .square
            //   后续 updateAllStates(layoutMode:) 调 updateLayoutModeButtonImage() 同步
            item = makeMenuItem(
                id: id,
                defaultImage: layoutMode.icon,
                label: Copy.layoutMode,
                action: #selector(handleMenuButtonClicked(_:))
            )
        case .densityMenu:  // V5.39.3 NEW: 4 档密度 下拉菜单 (替代 V5.31 NSSegmentedControl)
            // V5.43.1: defaultImage 跟 currentDensity 走——初次创建时用默认值 medium
            //   后续 currentDensity.didSet → updateDensityButtonImage() 同步
            item = makeMenuItem(
                id: id,
                defaultImage: currentDensity.iconName,
                label: Copy.thumbnailSize,
                action: #selector(handleMenuButtonClicked(_:))
            )
        case .sortMenu:  // V5.39.3 NEW: 排序 下拉菜单
            // V5.50-1: defaultImage 跟 sortOption 走——初次创建时用默认 .filenameAsc
            //   后续 updateAllStates(sortOption:) 调 updateSortButtonImage() 同步
            //   镜像 V5.43-1 densityMenu + V5.46-3 layoutModeMenu 模式
            //   工具栏 3 个 NSMenu 按钮 UX 现在完全一致: 按钮自己 = 状态指示
            item = makeMenuItem(
                id: id,
                defaultImage: sortOption.toolbarIcon,
                label: Copy.sort,
                action: #selector(handleMenuButtonClicked(_:))
            )
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
    /// V5.24: 加 density 状态同步——ContentView @AppStorage 变化时调
    /// V5.33: 砍 layoutMode 参数——3 模式 toolbar 控件已删 (e7695d7)
    /// V5.39.3: 重构——layoutMode / thumbnailSize / sortOption 3 个 NSMenu 按钮都需 state
    ///   ContentView 状态变化时全推, toolbar 同步更新 button image + menu checkbox
    func updateAllStates(
        hasSelection: Bool,
        hasMultipleSelection: Bool,
        density: CGFloat? = nil,
        layoutMode: ThumbnailLayoutMode? = nil,
        sortOption: SortOption? = nil
    ) {
        exportEnabled = hasSelection
        deleteEnabled = hasSelection
        // V4.37.1: Quick Look 仅在单张选中时可用（多张 / 0 张 都灰显）
        quickLookEnabled = hasSelection && !hasMultipleSelection

        // V5.39.3: density 改 NSMenu 按钮——存 state 给 buildDensityMenu 勾选用
        // V5.43.1: 同步 currentDensity——按钮 image 跟选中的档位变
        //   (之前 image 写死 medium, 切到 compact/small/large 按钮自己不变)
        //   先设 thumbnailSize (CGFloat) 给 buildDensityMenu 勾选, 再算 currentDensity 触发 didSet 更新 image
        if let d = density {
            self.thumbnailSize = d
            self.currentDensity = ThumbnailDensity.nearest(to: d)
        }

        // V5.39.3: 布局模式 NSMenu 按钮——存 state + 切 button image (跟 layoutMode 走)
        if let m = layoutMode {
            self.layoutMode = m
            updateLayoutModeButtonImage()
        }

        // V5.39.3: 排序 NSMenu 按钮——存 state + 切 button image (跟 sortOption 走)
        if let s = sortOption {
            self.sortOption = s
            updateSortButtonImage()
        }
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
    ///
    /// V5.9.7: 改 bezelStyle = .circular + 不设 item.isBordered
    ///   跟 V5.9.7 makeButtonItem 一致——圆形 pill 背景跟其他 5 按钮统一
    private func makeFilterItem(id: Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""  // V4.8.3: 空 label + displayMode = .iconOnly 双重保险隐藏文字
        item.paletteLabel = Copy.filter  // Customize Toolbar 面板显示
        item.toolTip = Copy.filter  // 初值；filterActiveCount > 0 时被 updateFilterBadge 覆盖
        item.target = self
        item.action = #selector(handleShowFilter)
        // V5.9.7: 不设 item.isBordered——让 button bezel 处理背景

        let button = NSButton()
        // V5.9.7: .recessed → .circular——圆形 pill 背景，跟其他按钮一致
        button.bezelStyle = .circular
        button.toolTip = Copy.filter
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

    /// V5.9.2: 通用工具栏按钮 item 工厂——popover-承载类按钮走 NSButton
    ///   让 item.view = NSButton——popover 可锚定到 button.bounds
    ///   之前 makeSimpleItem 用默认 NSToolbarItem——item.view = nil
    ///   handleShowXxx 的 `guard let anchorView = item.view` 失败——popover 永远打不开
    ///   典型受害者：view options（之前一直不工作的根因）
    ///
    /// V5.9.7: 改 bezelStyle = .circular + 不设 item.isBordered
    ///   之前 .recessed + item.isBordered=true 在 toolbar 模式下渲染异常
    ///   圆形 pill 背景跟其他 5 个按钮（QuickLook/Export/Delete/Import）一致
    ///   不设 item.isBordered——让 button 自己的 bezel 渲染，避免与 item 冲突
    private func makeButtonItem(id: Identifier, image: String, label: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        // V5.9.7: 不设 item.isBordered——让 button bezel 处理背景
        //   之前 item.isBordered=true + button.isBordered=true 冲突
        //   V5.9.1 setItemPressed 把 item.isBordered 切 false 时，背景完全消失
        //   现在只靠 button 自己的 bezel——不被 item 干扰

        let button = NSButton()
        // V5.9.7: .recessed → .circular——圆形 pill 背景，跟其他按钮一致
        button.bezelStyle = .circular
        button.toolTip = label
        button.target = self
        button.action = action
        button.isBordered = true
        button.image = NSImage(systemSymbolName: image, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
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
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: Copy.filter)
        // V4.54.0: 激活时 tint 强调色（Photos.app 同款——toggle 按钮 active 时显色）
        // nil = 系统默认（保持与其他 5 actions 不主动 tint 一致）
        btn.contentTintColor = filterIsActive ? .controlAccentColor : nil
    }

    /// V5.43.1 NEW: 同步 density button image 跟 currentDensity——所有 currentDensity 变化走这里
    ///   仿 V4.54.0 updateFilterButtonImage 模式 (didSet → updateImage)
    ///   icon: 4x3.fill / 3x2.fill / 2x2.fill / square.fill (跟档位)
    ///   tint: nil = 系统默认（不主动 tint，跟其他 5 actions 一致）
    ///   V5.43.1 之前: 按钮 image 写死 medium——选 compact/small/large 按钮自己不变
    ///   V5.43.1 之后: 按钮 image 跟选中的档位——视觉上"按钮自己就是状态指示"
    private func updateDensityButtonImage() {
        guard let item = itemCache[Identifier.densityMenu.nsIdentifier],
              let btn = item.view as? NSButton else { return }
        btn.image = NSImage(
            systemSymbolName: currentDensity.iconName,
            accessibilityDescription: Copy.thumbnailSize
        )
    }

    // MARK: - V5.39.3: NSMenu 工具栏按钮 (布局模式 / 缩略图大小 / 排序)

    /// V5.39.3 NEW: 工具栏 NSMenu 按钮工厂
    ///   - 1 个 NSButton + .circular bezel (与其他 toolbar 按钮一致)
    ///   - 点击后通过 handleMenuButtonClicked 弹 NSMenu
    ///   - defaultImage: 初值；实际 icon 由 updateLayoutModeButtonImage / updateDensityButtonImage / updateSortButtonImage 跟状态切
    ///   - 替代 V5.31 NSSegmentedControl (density) + V5.33 砍掉的 layoutMode segment + ViewOptionsPopover 内的 sort 段
    private func makeMenuItem(id: Identifier, defaultImage: String, label: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""
        item.paletteLabel = label
        item.toolTip = label

        let button = NSButton()
        button.bezelStyle = .circular
        button.toolTip = label
        button.target = self
        button.action = action
        button.isBordered = true
        button.image = NSImage(systemSymbolName: defaultImage, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        item.view = button

        return item
    }

    /// V5.39.3 NEW: 3 个 NSMenu 按钮的统一 action handler
    ///   - 找到被点击的 button 对应的 Identifier
    ///   - 按 Identifier 构造对应 NSMenu
    ///   - 在 button 底部弹 NSMenu（NSMenu.popUp positioning at: in:）
    ///   - 用户点 menu item → 触发对应 closure (onLayoutModeChange / onDensityChange / onSortOptionChange)
    private let menuSelectors: [Selector] = [
        #selector(handleMenuItemSelected(_:))
    ]

    @objc private func handleMenuButtonClicked(_ sender: NSButton) {
        // 找到 sender button 对应的 toolbar item → Identifier
        guard let id = identifierForButton(sender) else { return }

        // V5.72: layoutMode 改 NSPopover (仿 filter popover V5.63-1 风格)——统一视觉
        //   density + sort 仍走 NSMenu, V5.73/V5.74 后续扩
        if id == .layoutModeMenu {
            handleShowLayoutMode()
            return
        }

        let menu: NSMenu?
        switch id {
        case .densityMenu:
            menu = buildDensityMenu()
        case .sortMenu:
            menu = buildSortMenu()
        default:
            menu = nil
        }
        guard let menu = menu else { return }
        // V5.39.4: 菜单定位——
        //   - x: 0 (左对齐按钮左边缘)——macOS Photos 风格, 菜单左边缘与按钮左边缘齐平
        //     (原 at: midX 居中对齐——菜单中心在按钮中心, 但菜单常比按钮宽, 视觉偏右)
        //   - y: bounds.minY - 2 (按钮底部下方 2pt 视觉间隙)——
        //     原 at: minY 紧贴按钮 0pt 间隙, 看起来"挤"在按钮上
        //     2pt 间隙给"按钮浮起"感, 跟 macOS Photos toolbar 菜单节奏一致
        //   NSButton 默认非 flipped——y 向上为正, minY 在按钮底部, minY-2 是底部下方
        let location = NSPoint(x: 0, y: sender.bounds.minY - 2)
        menu.popUp(positioning: nil, at: location, in: sender)
    }

    /// V5.72 NEW: 显示 layoutMode NSPopover——仿 handleShowFilter 模式 (V4.36.x)
    ///   强引用 layoutModePopover 避免 ARC 释放, V5.71 改 anchoredTo 路径
    @objc private func handleShowLayoutMode() {
        // 切换关闭（再点 toolbar 按钮 toggle）
        if let popover = layoutModePopover, popover.isShown {
            popover.close()
            layoutModePopover = nil
            return
        }

        guard let item = itemCache[Identifier.layoutModeMenu.nsIdentifier],
              let anchorView = item.view else {
            return
        }

        let vc = LayoutModePopoverController(currentMode: layoutMode)
        vc.onSelect = { [weak self] mode in
            // V5.72: 走 onLayoutModeChange closure 写入 UserSettings + ContentView .onChange 推 toolbar icon
            //   V5.66 已有 updateAllStates(layoutMode:) 路径
            self?.onLayoutModeChange?(mode)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        // V5.71 模式: anchoredTo + .minY (跟 filter popover 一致)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        layoutModePopover = popover
    }

    /// V5.39.3: 找到 NSButton 对应的 Identifier——遍历 itemCache 比 view ===
    private func identifierForButton(_ button: NSButton) -> Identifier? {
        for id in [Identifier.layoutModeMenu, .densityMenu, .sortMenu] {
            if let item = itemCache[id.nsIdentifier], item.view === button {
                return id
            }
        }
        return nil
    }

    // MARK: - 3 个 menu builder (V5.39.3 NEW)

    /// V5.39.3 NEW: 缩略图大小菜单——4 档
    private func buildDensityMenu() -> NSMenu {
        let menu = NSMenu()
        for density in ThumbnailDensity.allCases {
            let item = NSMenuItem(
                title: density.label,
                action: #selector(handleMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = CGFloat(density.size)
            item.image = NSImage(systemSymbolName: density.iconName, accessibilityDescription: density.label)
            if CGFloat(density.size) == thumbnailSize {
                item.state = .on
            }
            menu.addItem(item)
        }
        return menu
    }

    /// V5.39.3 NEW: 排序菜单——7 种排序 (导入时间/文件名/文件大小/自定义 × 方向)
    private func buildSortMenu() -> NSMenu {
        let menu = NSMenu()
        for option in SortOption.allCases {
            let item = NSMenuItem(
                title: option.label,
                action: #selector(handleMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option
            item.image = NSImage(systemSymbolName: option.toolbarIcon, accessibilityDescription: option.label)
            if option == sortOption {
                item.state = .on
            }
            menu.addItem(item)
        }
        return menu
    }

    /// V5.39.3 NEW: menu item 选中回调——按 representedObject 类型分派
    @objc private func handleMenuItemSelected(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? ThumbnailLayoutMode {
            onLayoutModeChange?(mode)
        } else if let size = sender.representedObject as? CGFloat {
            onDensityChange?(size)
        } else if let option = sender.representedObject as? SortOption {
            onSortOptionChange?(option)
        }
    }

    // MARK: - 3 个 menu 按钮的 image 更新 (V5.39.3 NEW)

    /// V5.39.3: 同步布局模式按钮 image——跟着 layoutMode 切
    ///   ContentView 在 .onChange(of: layoutMode) 调 updateAllStates 推
    private func updateLayoutModeButtonImage() {
        guard let item = itemCache[Identifier.layoutModeMenu.nsIdentifier],
              let button = item.view as? NSButton else { return }
        button.image = NSImage(systemSymbolName: layoutMode.icon, accessibilityDescription: Copy.layoutMode)
    }

    /// V5.39.3: 同步排序按钮 image——跟着 sortOption 切
    ///   ContentView 在 .onChange(of: sortOption) 调 updateAllStates 推
    private func updateSortButtonImage() {
        guard let item = itemCache[Identifier.sortMenu.nsIdentifier],
              let button = item.view as? NSButton else { return }
        button.image = NSImage(systemSymbolName: sortOption.toolbarIcon, accessibilityDescription: Copy.sort)
    }

    // MARK: - V5.39.3: 3 个 NSMenu 按钮的 state (menu item 勾选用)

    /// V5.39.3: 当前布局模式——buildLayoutModeMenu 勾选用
    ///   ContentView 在 .onChange(of: layoutMode) 调 updateAllStates 推
    /// V5.66: 改 private(set) 让测试可读——V5.66 修了 '启动不 transition 不同步' bug, 锁住 invariant
    private(set) var layoutMode: ThumbnailLayoutMode = .defaultValue

    /// V5.39.3: 当前缩略图大小——buildDensityMenu 勾选用
    ///   ContentView 在 .onChange(of: thumbnailSize) 调 updateAllStates 推
    private(set) var thumbnailSize: CGFloat = 200

    /// V5.43.1 NEW: 当前缩略图密度 enum——按钮 image 跟随
    ///   之前 V5.39.3 按钮 image 写死 medium (square.fill)——切到大或小按钮自己不变
    ///   V5.43.1: 跟 ThumbnailDensity.iconName——4x3 / 3x2 / 2x2 / 1x1 反映当前档
    ///   仿 V4.54.0 filterActiveCount 模式：computed property + didSet 自动同步 UI
    var currentDensity: ThumbnailDensity = .medium {
        didSet {
            // 只在值实际变化时更新 UI（避免 didSet 循环）
            if oldValue != currentDensity {
                updateDensityButtonImage()
            }
        }
    }

    /// V5.39.3: 当前排序——buildSortMenu 勾选用
    ///   ContentView 在 .onChange(of: sortOption) 调 updateAllStates 推
    /// V5.66: 改 private(set) 让测试可读
    private(set) var sortOption: SortOption = .filenameAsc

    // V5.9.7: 砍 setItemPressed 整个方法 + 所有调用点
    //   用户反馈: "可以不产生icon的变化，只有点击的反馈就行了"
    //   之前 V5.9.1 setItemPressed 改 item.isBordered = false 在 popover 关闭时
    //   → 按钮背景完全消失（其他 5 个按钮都有圆形 pill 背景）
    //   现在：不主动改 item 任何状态——NSToolbarItem + NSButton 自己处理 hover/press 反馈

    // V5.39.3: 删 popoverDidClose 中 viewOptionsPopover 引用 (line 434-435)
    //   viewOptions popover 已删, filter popover 由 coordinator 内部管
    //   现在 popoverDidClose 已无任何 NSPopover 需要清理——整个方法可砍
    //   但保留 delegate conformance 以防未来 NSPopover 引入

    /// V5.62-2: 外部 filterState 变化推送 (ContentView.onChange 触发)
    ///   透传到 coordinator.pushStateToOpenChild——若 child popover open, 同步 checkbox 视觉
    func pushFilterStateToOpenChild(_ newState: FilterState) {
        filterPopoverCoordinator?.pushStateToOpenChild(newState)
    }
    func popoverDidClose(_ notification: Notification) {
        // V5.39.3: 空实现——所有 popover 关闭由各自 controller 内部处理
        //   保留方法以维持 NSPopoverDelegate conformance
    }

    private func makeSearchItem(id: Identifier) -> NSToolbarItem {
        // V4.8.2: 用 NSSearchToolbarItem 替代裸 NSToolbarItem + NSSearchField
        //   NSSearchToolbarItem (macOS 11+) 是 NSToolbar 专用 search item 包装
        //   自动有合适的背景样式 + 系统 placeholder + clear button + 展开/收起的 toolbar 行为
        //   Photos.app / Finder / Mail / Notes 都用这个
        let searchItem = NSSearchToolbarItem(itemIdentifier: id.nsIdentifier)
        searchItem.label = ""  // V4.8.3: 不显示 "Search" 文字
        // V4.14.0: 本地化——之前 V4.8.x 硬编码英文，Customize Toolbar 面板 + hover tooltip 显示英文
        searchItem.paletteLabel = Copy.search
        searchItem.toolTip = Copy.searchHint

        let searchField = searchItem.searchField
        searchField.placeholderString = Copy.searchPlaceholder
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

    /// V5.24 NEW: 3-icon NSSegmentedControl (布局模式 toolbar 集成)
    ///   - .square / .squareFit 两档 (V5.47 砍 .masonry)
    ///   - selectedSegment = mode.rawValue 直接同步 @AppStorage
    ///   - segment 风格 matches macOS Photos view mode segment
    ///   - 状态由 ContentView 推 (updateAllStates)
    private func makeLayoutModeItem(id: Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""
        item.paletteLabel = Copy.layoutMode
        item.toolTip = Copy.layoutMode

        let segment = NSSegmentedControl(
            images: ThumbnailLayoutMode.allCases.map { mode in
                NSImage(systemSymbolName: mode.icon, accessibilityDescription: mode.displayName) ?? NSImage()
            },
            trackingMode: .selectOne,
            target: self,
            action: #selector(handleLayoutModeChanged(_:))
        )
        // 初始 selectedSegment = defaultValue (0 = .square)
        segment.selectedSegment = ThumbnailLayoutMode.defaultValue.rawValue
        segment.setContentHuggingPriority(.defaultLow, for: .horizontal)
        item.view = segment

        return item
    }

    /// V5.31 NEW: NSSegmentedControl 离散密度 4 档——替代 V5.24 NSSlider
    ///   - 镜像 macOS Photos.app: 密度是离散 3-4 档按钮, 不是连续 slider
    ///   - 4 段对应 ThumbnailDensity.allCases: compact(70) / small(110) / medium(200) / large(240)
    ///   - 用 SF Symbol 图标表示密度 (4x3 / 3x2 / 2x2 / 1x1 网格)
    ///   - selectedSegment → ThumbnailDensity.allCases 索引 → onDensityChange(size)
    ///   - 状态由 ContentView 推 (updateAllStates)
    private func makeDensityItem(id: Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""
        item.paletteLabel = Copy.thumbnailSize
        item.toolTip = Copy.thumbnailSize

        // V5.31: 4 段离散按钮 (Photos 真版)
        //   - 段 0: compact 70pt (square.grid.4x3.fill)
        //   - 段 1: small 110pt (square.grid.3x2.fill)
        //   - 段 2: medium 200pt (square.grid.2x2.fill) [V5.30 默认]
        //   - 段 3: large 240pt (square)
        let segment = NSSegmentedControl(
            images: ThumbnailDensity.allCases.map { mode in
                NSImage(systemSymbolName: mode.iconName, accessibilityDescription: mode.label) ?? NSImage()
            },
            trackingMode: .selectOne,
            target: self,
            action: #selector(handleDensitySegmentChanged(_:))
        )
        // 初始 selectedSegment = medium.index (V5.30 默认)
        segment.selectedSegment = ThumbnailDensity.allCases.firstIndex(of: .medium) ?? 0
        segment.setContentHuggingPriority(.defaultLow, for: .horizontal)
        item.view = segment

        return item
    }

    /// V5.24: 布局模式 segment 变化回调
    @objc private func handleLayoutModeChanged(_ sender: NSSegmentedControl) {
        let mode = ThumbnailLayoutMode(rawValue: sender.selectedSegment) ?? .defaultValue
        onLayoutModeChange?(mode)
    }

    /// V5.31: 密度 segment 变化回调——4 段映射到 ThumbnailDensity.size
    @objc private func handleDensitySegmentChanged(_ sender: NSSegmentedControl) {
        let densities = ThumbnailDensity.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < densities.count else { return }
        let density = densities[sender.selectedSegment]
        onDensityChange?(CGFloat(density.size))
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
    // V5.39.3: 删 handleShowViewOptions——布局模式 + 排序都搬到独立 toolbar 按钮
    //   走 NSMenu (handleMenuButtonClicked) + handleMenuItemSelected, 不再需要 NSPopover
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
            return
        }

        guard let item = itemCache[Identifier.filter.nsIdentifier],
              let anchorView = item.view else {
            return
        }

        // V4.90.0: 创建 coordinator + 调 showTop
        //   ContentView 注入 factory + onStateChange closure
        guard let coordinator = filterCoordinatorFactory?({ [weak self] newState in
            // V4.90.0: 写回 ContentView filterState——coordinator 不直接管 ContentView state
            //   实际由 ContentView .onChange 推——coordinator 只管 popover lifecycle
            _ = newState
            _ = self
        }) else { return }

        // V5.39.2: 用 coordinator.showTopAtRect + contentView positioningView
        //   V5.9.4 引入此 helper (V5.9.4 注释: "刚创建的 NSButton 还没进 window, anchor 无效")
        //   V5.9.5 回退到 V5.8 anchoredTo 路径, 在 macOS 26+ 上 popover 不显示 (用户反馈)
        //   现统一回 showTopAtRect——contentView 永远在 window, 1x1 rect 在按钮底部中心
        // V5.69/V5.70/V5.71 三次 preferredEdge 试错 (.minY/.maxY/rect offset) 用户都报重叠
        // V5.71: 改回 anchoredTo 路径, 用 button 自身作 anchor (popover.show(relativeTo: anchor.bounds, of: anchor, ...))
        //   这是 NSPopover 最简 API, macOS 26+ 'NSButton 没进 window' 坑已确认不存在 (user click 时 button 已在 window)
        coordinator.showTop(anchoredTo: anchorView)
        filterPopoverCoordinator = coordinator
    }

    /// V4.36.x + V4.54.0: 同步激活筛选数 + active 视觉锤到 filter item
    ///   V4.36.x: 改 tooltip "筛选 (N)"
    ///   V4.54.0: 同时调 updateFilterButtonImage 切 icon (outline ↔ fill.circle) + tint 强调色
    ///   V4.8.3: displayMode = .iconOnly 不显示 title，故用 tooltip 显示 "筛选 (N)"
    private func updateFilterBadge() {
        guard let item = itemCache[Identifier.filter.nsIdentifier] else { return }
        item.toolTip = filterActiveCount > 0 ? Copy.filterWithCount(filterActiveCount) : Copy.filter
        updateFilterButtonImage()  // V4.54.0: 同步 icon + tint
    }
}
