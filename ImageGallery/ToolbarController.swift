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
//  - Search field 是 custom NSToolbarItem (NSHostingView 包 ToolbarSearchField)
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
final class ToolbarController: NSObject, NSToolbarDelegate {
    /// 单例——NSToolbarDelegate 是 weak 引用，必须有强引用
    static let shared = ToolbarController()

    // MARK: - Action 桥接（ContentView 设置 closure）

    var onToggleSidebar: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var onBatchExport: (() -> Void)?
    var onDelete: (() -> Void)?
    var onImport: (() -> Void)?
    var onShowViewOptions: (() -> Void)?

    // MARK: - Search field 桥接

    /// ContentView 提供 closure 创建 search field view
    /// 捕获 @State searchText binding 进 SwiftUI view
    var searchViewProvider: (() -> NSView)?

    // MARK: - 状态桥接

    /// 5 actions 的 enabled 状态
    var favoriteEnabled: Bool = false {
        didSet { updateItemEnabled(.favorite, enabled: favoriteEnabled) }
    }
    var exportEnabled: Bool = false {
        didSet { updateItemEnabled(.export, enabled: exportEnabled) }
    }
    var deleteEnabled: Bool = false {
        didSet { updateItemEnabled(.delete, enabled: deleteEnabled) }
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
        case favorite
        case export
        case delete
        case importItem      // 避开 `import` 关键字
        case viewOptions

        var nsIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(rawValue: rawValue)
        }
    }

    // MARK: - NSToolbarDelegate

    /// 默认 item 顺序——决定 toolbar 的视觉布局
    /// sidebar | search | flex | favorite | export | delete | import | viewOptions
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Identifier.sidebarToggle.nsIdentifier,
            Identifier.search.nsIdentifier,
            Identifier.flexibleSpace.nsIdentifier,
            Identifier.favorite.nsIdentifier,
            Identifier.export.nsIdentifier,
            Identifier.delete.nsIdentifier,
            Identifier.importItem.nsIdentifier,
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
                label: "Toggle Sidebar",
                action: #selector(handleToggleSidebar)
            )
        case .favorite:
            item = makeSimpleItem(
                id: id,
                image: "star",
                label: "Favorite",
                action: #selector(handleToggleFavorite)
            )
        case .export:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.up",
                label: "Export",
                action: #selector(handleBatchExport)
            )
        case .delete:
            item = makeSimpleItem(
                id: id,
                image: "trash",
                label: "Delete",
                action: #selector(handleDelete)
            )
        case .importItem:
            item = makeSimpleItem(
                id: id,
                image: "square.and.arrow.down",
                label: "Import",
                action: #selector(handleImport)
            )
        case .viewOptions:
            item = makeSimpleItem(
                id: id,
                image: "rectangle.3.offgrid",
                label: "View Options",
                action: #selector(handleShowViewOptions)
            )
        case .search:
            // V4.8.0b: custom NSToolbarItem 用 NSHostingView 包 SwiftUI ToolbarSearchField
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
        case .favorite: return favoriteEnabled
        case .export: return exportEnabled
        case .delete: return deleteEnabled
        default: return true
        }
    }

    // MARK: - 状态更新

    private func updateItemEnabled(_ id: Identifier, enabled: Bool) {
        guard let item = itemCache[id.nsIdentifier] else { return }
        item.isEnabled = enabled
    }

    /// 全部状态更新（ContentView 在 .onChange 调用）
    func updateAllStates(hasSelection: Bool, hasMultipleSelection: Bool) {
        favoriteEnabled = hasSelection
        exportEnabled = hasSelection
        deleteEnabled = hasSelection
    }

    // MARK: - Item 工厂

    private func makeSimpleItem(id: Identifier, image: String, label: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    private func makeSearchItem(id: Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id.nsIdentifier)
        item.label = "Search"
        item.paletteLabel = "Search"
        item.toolTip = "Search photos, tags, notes"
        // V4.8.0b: 用 ContentView 提供的 provider 创建 search view
        if let viewProvider = searchViewProvider {
            item.view = viewProvider()
            item.minSize = NSSize(width: 180, height: 24)
            item.maxSize = NSSize(width: 360, height: 24)
        } else {
            // Provider 未设置时的 fallback
            item.view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        }
        return item
    }

    // MARK: - Action Handlers

    @objc private func handleToggleSidebar() { onToggleSidebar?() }
    @objc private func handleToggleFavorite() { onToggleFavorite?() }
    @objc private func handleBatchExport() { onBatchExport?() }
    @objc private func handleDelete() { onDelete?() }
    @objc private func handleImport() { onImport?() }
    @objc private func handleShowViewOptions() { onShowViewOptions?() }
}
