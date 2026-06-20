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

    // V6.20.2 (code audit fix #5): searchField observer token — NSToolbar rebuild 时 remove 旧的
    //   之前 addObserver 返回的 token 没存, NSToolbar 每次 rebuild makeSearchItem 都加新 observer
    //   旧 observer token 丢失, 永不 remove → 多个 observer 同触发 text change
    private var searchFieldObserver: NSObjectProtocol?

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

    /// V5.74 NEW: Density popover 强引用
    private var densityPopover: NSPopover?

    /// V5.75 NEW: SortOption popover 强引用
    private var sortOptionPopover: NSPopover?

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

    /// V6.29.2: filter button + badge 视图引用 (updateFilterBadge 更新)
    ///   container: 容纳 button + 红点 badge 的 NSView (用作 item.view)
    ///   button: NSButton (click target, icon update)
    ///   badgeLabel: NSTextField (右上小红点 + 数字, count==0 隐藏)
    @ObservationIgnored private var filterButtonContainer: NSView?
    @ObservationIgnored private var filterButton: NSButton?
    @ObservationIgnored private var filterBadgeLabel: NSTextField?

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
    /// V6.13.2: 工具栏 3 group 化 (Photos.app 范式)
    ///   1. 主操作组: sidebarToggle · importItem · export · delete · quickLook
    ///   2. flexible space (推到右边)
    ///   3. 视图组: filter · sortMenu · layoutModeMenu · densityMenu
    ///   4. space + search (centered, 原 V4.8.3 设计)
    ///   NSToolbar 自动支持 .space (小 fixed) 跟 .flexibleSpace (弹性) 作 separator
    ///   自动 overflow: 窗口窄时 NSToolbar 把末尾 items 塞进 ⋯ 菜单 (Photos 范式)
    ///
    /// V4.36.x: 在 importItem 之后插入 filter（import→filter 形成操作组）
    /// V4.37.1: 在 favorite 之后插入 quickLook（"看"的语义紧邻 favorite/"标记"语义）
    /// V5.7: 砍 favorite 项——侧栏/工具栏都不再放收藏入口（走右键菜单评分 / 筛选 popover）
    /// V5.39.3: filter 之后插入 3 个 NSMenu 下拉按钮 (布局模式/缩略图大小/排序)——viewOptions 砍
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            // 主操作组 (left side)
            Identifier.sidebarToggle.nsIdentifier,
            NSToolbarItem.Identifier.space,  // V6.13.2: 跟视图组视觉分隔
            Identifier.importItem.nsIdentifier,
            Identifier.export.nsIdentifier,
            Identifier.delete.nsIdentifier,
            Identifier.quickLook.nsIdentifier,  // V4.37.1 NEW
            // 弹性 space 推视图组到右
            Identifier.flexibleSpace.nsIdentifier,
            // 视图组 (right side, 主操作右侧)
            Identifier.filter.nsIdentifier,
            NSToolbarItem.Identifier.space,
            Identifier.sortMenu.nsIdentifier,         // V5.39.3: 从 viewOptions 提到 toolbar
            Identifier.layoutModeMenu.nsIdentifier,  // V5.39.3: 从 viewOptions 提到 toolbar
            Identifier.densityMenu.nsIdentifier,     // V5.39.3: NSSegmentedControl → NSMenu
            // 搜索 (centered, V4.8.3 设计保留)
            NSToolbarItem.Identifier.space,
            Identifier.search.nsIdentifier
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
                action: #selector(handleToggleSidebar),
                shortcut: Copy.toolbarShortcutToggleSidebar  // V6.24: ⌃⌘S
            )
        // V5.7: 砍 .favorite case——工具栏 ❤ 收藏按钮移除
        case .quickLook:  // V4.37.1 NEW
            // V4.37.1: ⌘Y 快速查看——macOS Finder/Photos 标准 eye 图标
            //   复用 makeSimpleItem 模式，行为与 5 actions 一致
            item = makeSimpleItem(
                id: id,
                image: "eye",
                label: Copy.quickLook,
                action: #selector(handleShowQuickLook),
                shortcut: Copy.toolbarShortcutQuickLook  // V6.24: ⌘Y
            )
        case .export:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.up",
                label: Copy.toolbarExport,
                action: #selector(handleBatchExport),
                shortcut: nil  // V6.24: export 用 ⌘⇧E (share sheet), 不是 toolbar 主快捷键, 不显示
            )
        case .delete:
            item = makeSimpleItem(
                id: id,
                image: "trash",
                label: Copy.delete,
                action: #selector(handleDelete),
                shortcut: Copy.toolbarShortcutDelete  // V6.24: ⌘⌫
            )
        case .importItem:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.down",
                label: Copy.toolbarImport,
                action: #selector(handleImport),
                shortcut: Copy.toolbarShortcutImport  // V6.24: ⌘O
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

    private func makeSimpleItem(id: Identifier, image: String, label: String, action: Selector, shortcut: String? = nil) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = ""  // V4.8.3: 空 label + displayMode = .iconOnly 双重保险隐藏文字
        item.paletteLabel = label  // Customize Toolbar 面板仍显示 label
        // V6.24 (P0 #3): tooltip 加快捷键提示 — "label\n(⌘O)" 风格, Photos.app 范式
        //   之前只显示按钮名, Power user 记不得快捷键, 新用户不知道有快捷键
        //   nil 时不换行, 保持之前行为
        item.toolTip = shortcut.map { "\(label)\n(\($0))" } ?? label
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
        // V5.81: 改 .circular——5 个系统按钮 (sidebar/quickLook/export/delete/import) 跟 4 个 popover 按钮 (filter/layoutMode/density/sort) 统一
        //   V5.9.7 注释 "圆形 pill 跟其他 5 按钮统一" 但实际 5 按钮是 .recessed, 现治本
        //   macOS Photos 风格——9 按钮全 .circular
        button.bezelStyle = .circular
        // V6.24: 按钮 tooltip 也加快捷键 — item.tooltip 显示 toolbar hover, button.tooltip 显示更近距离 hover
        button.toolTip = item.toolTip
        button.isBordered = true
        // V6.22.10 (XCUITest): accessibilityIdentifier 在 NSButton 上 (NSToolbarItem 没这个属性)
        //   importItem 设 "toolbar.importButton" — ImportTest 找按钮用
        //   其他 item 不设 (XCUIElementQuery 用 label 也行, 不强制)
        if id == .importItem {
            button.setAccessibilityIdentifier("toolbar.importButton")
        }
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
        // V6.29.2: wrap button in container view + add badge overlay (右上小红点 + count)
        //   NSToolbarItem.view 直接设 NSButton 不能加 overlay, 用 NSView 容器
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        button.frame = container.bounds
        button.autoresizingMask = [.width, .height]
        container.addSubview(button)
        let badge = makeFilterBadgeLabel()
        container.addSubview(badge)
        item.view = container
        // V6.29.2: 存引用, updateFilterBadge 更新 badge 文本/可见
        filterButtonContainer = container
        filterButton = button
        filterBadgeLabel = badge

        return item
    }

    /// V6.29.2: 创建 filter button badge (右上小红点 + count 数字)
    ///   Photos.app / Mail 等 macOS 标准: 小红圆角矩形 + 白字, 右上角叠在 icon 上
    ///   count==0 时通过 updateFilterBadge 隐藏 (默认隐藏)
    private func makeFilterBadgeLabel() -> NSTextField {
        let badge = NSTextField(labelWithString: "")
        badge.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .systemRed
        badge.drawsBackground = true
        badge.isBezeled = false
        badge.isEditable = false
        badge.isSelectable = false
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.masksToBounds = true
        badge.isHidden = true
        // 右上角, 尺寸根据 count 自适应 (1 位 / 2 位)
        // 容器 28x22, button 占满, badge 在 (18, 14) 起点, 12x12 默认
        badge.frame = NSRect(x: 16, y: 12, width: 14, height: 14)
        badge.autoresizingMask = [.minXMargin, [.minYMargin]]
        return badge
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
        // V5.79: 同步 imageScaling——之前 makeMenuItem 设过, 但 image 替换时仍保持
        btn.imageScaling = .scaleProportionallyDown
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
        // V5.79: 显式 imageScaling——4 档 density SF Symbol (square.grid.4x3.fill / .3x3 / .2x2 / square)
        //   intrinsic size 微差, 不设 scaling 时 bezel 跟着 image 变 → 按钮大小切换时变化
        button.imageScaling = .scaleProportionallyDown
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // V5.79: 显式 28x28 constraints 锁死 frame——防 toolbar 重新 layout 时 button 跟 image intrinsic 变
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        item.view = button

        return item
    }

    /// V5.75: 3 个 NSMenu 按钮的统一 action handler——全改 NPPopover 路由
    ///   - 找到被点击的 button 对应的 Identifier
    ///   - 路由到 handleShowLayoutMode / handleShowDensity / handleShowSort
    @objc private func handleMenuButtonClicked(_ sender: NSButton) {
        // 找到 sender button 对应的 toolbar item → Identifier
        guard let id = identifierForButton(sender) else { return }

        // V5.72/V5.74/V5.75: layoutMode + density + sort 都改 NSPopover (仿 filter popover)——统一视觉
        if id == .layoutModeMenu {
            handleShowLayoutMode()
            return
        }
        if id == .densityMenu {
            handleShowDensity()
            return
        }
        if id == .sortMenu {
            handleShowSort()
            return
        }
        // V5.75: 所有 3 个 menu 按钮都改 NSPopover, 这里无 fallback
        return
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

        let vc = OptionListPopoverController<ThumbnailLayoutMode>(currentItem: layoutMode, minWidth: 140)
        vc.onSelect = { [weak self] mode in
            // V5.77: 走 onLayoutModeChange closure 写入 UserSettings + ContentView .onChange 推 toolbar icon
            //   V5.66 已有 updateAllStates(layoutMode:) 路径
            self?.onLayoutModeChange?(mode)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        // V5.73: 改 .maxY——.minY 实际是 above (popover 拓向 LARGER y, 屏幕上方)
        //   之前 layoutMode small 不 fit above 也 NSPopover auto-flip 到 .maxY 才不
        //   现改 .maxY 显式 below, 跟 filter popover 一致
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        layoutModePopover = popover
    }

    /// V5.74 NEW: 显示 density NSPopover——仿 handleShowLayoutMode 模式
    @objc private func handleShowDensity() {
        if let popover = densityPopover, popover.isShown {
            popover.close()
            densityPopover = nil
            return
        }

        guard let item = itemCache[Identifier.densityMenu.nsIdentifier],
              let anchorView = item.view else {
            return
        }

        // V5.74: 4 档 density 跟 thumbnailSize (CGFloat) 走——currentDensity 算最近档
        let current = ThumbnailDensity.nearest(to: thumbnailSize)
        let vc = OptionListPopoverController<ThumbnailDensity>(currentItem: current, minWidth: 140)
        vc.onSelect = { [weak self] density in
            // V5.77: 走 onDensityChange closure (CGFloat)——UserSettings + toolbar icon 推
            self?.onDensityChange?(CGFloat(density.size))
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        // V5.73: .maxY 显式 below (跟 layoutMode / filter 一致)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        densityPopover = popover
    }

    /// V5.75 NEW: 显示 sortOption NSPopover——仿 handleShowLayoutMode 模式
    @objc private func handleShowSort() {
        if let popover = sortOptionPopover, popover.isShown {
            popover.close()
            sortOptionPopover = nil
            return
        }

        guard let item = itemCache[Identifier.sortMenu.nsIdentifier],
              let anchorView = item.view else {
            return
        }

        let vc = OptionListPopoverController<SortOption>(currentItem: sortOption, minWidth: 160)
        vc.onSelect = { [weak self] option in
            // V5.77: 走 onSortOptionChange closure——UserSettings + toolbar icon 推
            self?.onSortOptionChange?(option)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        // V5.73: .maxY 显式 below (跟 layoutMode / density / filter 一致)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        sortOptionPopover = popover
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

    // MARK: - V5.75: 删所有 NSMenu builder (3 个 menu 按钮全改 NPPopover)

    /// V5.75: 删 handleMenuItemSelected——所有 menu 按钮 (layoutMode/density/sort) 改 NPPopover,
    ///   各自 onSelect closure 直接调 onLayoutModeChange/onDensityChange/onSortOptionChange
    ///   不再需要 representedObject 类型分派

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
        // V6.20.2 (code audit fix #5): 旧 observer token 先 remove, 避免多次 rebuild 累积
        if let oldToken = searchFieldObserver {
            NotificationCenter.default.removeObserver(oldToken)
            searchFieldObserver = nil
        }
        searchFieldObserver = NotificationCenter.default.addObserver(
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
        // V6.20.3 (code audit fix #14): state change 不再丢弃 — 真正 sync 给 toolbar
        //   之前 _ = newState; _ = self — closure 接 newState 不转发, 完全死路径
        //   现在调 self.pushFilterStateToOpenChild(newState) — toolbar 推 state 到打开的 child popover
        //   ContentView .onChange 同步, toolbar 也能直接响应 (双保险)
        guard let coordinator = filterCoordinatorFactory?({ [weak self] newState in
            guard let self = self else { return }
            self.pushFilterStateToOpenChild(newState)
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
    /// V6.29.2: 加 badge label 同步 — 右上小红点 + count, filterIsActive 时显示
    private func updateFilterBadge() {
        guard let item = itemCache[Identifier.filter.nsIdentifier] else { return }
        item.toolTip = filterActiveCount > 0 ? Copy.filterWithCount(filterActiveCount) : Copy.filter
        updateFilterButtonImage()  // V4.54.0: 同步 icon + tint
        // V6.29.2: badge label — count>0 显示数字, 否则隐藏
        if let badge = filterBadgeLabel {
            if filterActiveCount > 0 {
                badge.stringValue = "\(filterActiveCount)"
                badge.isHidden = false
                // 自适应宽度 (1 位 / 2 位 / 3 位)
                let charWidth: CGFloat = 7
                let width = max(14, charWidth * CGFloat("\(filterActiveCount)".count) + 4)
                badge.frame = NSRect(x: 28 - width + 2, y: 12, width: width, height: 14)
            } else {
                badge.isHidden = true
            }
        }
    }
}
