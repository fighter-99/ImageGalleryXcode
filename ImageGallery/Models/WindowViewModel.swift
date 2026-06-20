//
//  WindowViewModel.swift
//  ImageGallery
//
//  V6.28.2 NEW: 从 ContentViewModel 拆出的 Window 业务模型
//    Window 业务 — NSToolbar 配置 / Titlebar 右上 ⓘ 按钮 / WindowDidResize observer
//    持 Core back-ref (weak) 用于 settings + grid + importVM 跨域访问
//    + shared settings (init 注入, 同 instance)
//
//  拆分依据 (memory V6.28 follow-up):
//    ContentViewModel V6.28.1 后 456 行 → 拆 WindowViewModel (~140 行)
//    Window chrome (NSToolbar + Titlebar accessory + windowDidBecomeKey observer)
//    单独追踪 — 不污染 Core / Grid / Import 的 observation graph
//    测试隔离: WindowViewModel 单测更聚焦 (toolbar config / accessory state)
//
//  关键约束:
//    - @MainActor + @Observable + final class (同 ContentViewModel / GridViewModel / ImportViewModel)
//    - weak var core (避免 retain cycle — ContentViewModel 持 windowVM strong, windowVM 持 core weak)
//    - settings 由 init 注入 (同 instance, Core + Window 共享)
//    - configureToolbar 内访问 core.settings / core.grid / core.importVM — 单 back-ref chain
//
//  不在 WindowViewModel (仍 ContentViewModel):
//    - sidebarSelection / filterState / viewMode (Core)
//    - selection / visiblePhotos / batch ops (GridViewModel)
//    - startImport / handleDropImport / importPhotos (ImportViewModel)
//    - toastQueue / undoManager / enqueueToast (Core services)
//
//  阶段:
//    - V6.28.2-1: skeleton + Window 业务抽取 ✓
//    - V6.28.2-2: caller files file-by-file 迁移 model.X → model.windowVM.X
//    - V6.28.2-3: tests 迁移 + 验证 0 regression
//

import Foundation
import SwiftUI
import AppKit

/// V6.28.2: Window 业务模型 — NSToolbar 配置 / Titlebar accessory
@MainActor
@Observable
final class WindowViewModel {
    /// V6.28.2: Core back-ref (weak 避免 retain cycle)
    ///   用途: settings + grid + importVM + filterState (跨域访问)
    @ObservationIgnored weak var core: ContentViewModel?

    /// V6.28.2: shared settings (init 注入)
    ///   configureToolbar 直接读 settings.showSidebar / showDetail
    let settings: UserSettings

    /// V4.37.4: titlebar 右上角小按钮引用（NSObject 引用，model 持有）
    ///   .onChange(of: showDetail) 时调 setActive / setTooltip 同步状态
    var titlebarAccessory: TitlebarAccessoryController? = nil

    // MARK: - Init

    /// V6.28.2: WindowViewModel init — Core (ContentViewModel) 反向注入 weak ref + settings
    init(settings: UserSettings) {
        self.settings = settings
    }

    // MARK: - NSToolbar 配置

    /// V4.8.0: NSToolbar 配置（WindowAccessor 触发）
    /// V6.28: Grid 业务闭包走 model.grid.X()
    /// V6.28.1: Import 业务闭包走 model.importVM.X()
    /// V6.28.2: 整方法搬到 WindowViewModel (纯 chrome 配置, 不污染 Core observation)
    func configureToolbar(window: NSWindow) {
        // 只在第一次设置
        guard window.toolbar == nil else { return }

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        toolbar.delegate = ToolbarController.shared
        toolbar.displayMode = .iconOnly
        // V4.8.3: centeredItemIdentifiers = [.search] 让搜索框居中
        toolbar.centeredItemIdentifiers = [ToolbarController.Identifier.search.nsIdentifier]
        toolbar.allowsUserCustomization = true   // 用户可自定义 toolbar items
        toolbar.autosavesConfiguration = true   // 自定义状态自动保存
        toolbar.showsBaselineSeparator = false  // 不显示底部分隔线
        if #available(macOS 14.0, *) {
            toolbar.allowsDisplayModeCustomization = true
        }

        // 绑 action closures
        let controller = ToolbarController.shared
        controller.onToggleSidebar = { [weak self] in
            guard let model = self?.core else { return }
            withAnimation(Animations.medium) { model.settings.showSidebar.toggle() }
        }
        // V5.7: 砍 onToggleFavorite——工具栏 ❤ 收藏按钮已移除
        controller.onBatchExport = { [weak self] in
            self?.core?.grid.batchExport()
        }
        controller.onDelete = { [weak self] in
            self?.core?.grid.handleDelete()
        }
        controller.onImport = { [weak self] in
            self?.core?.importVM.startImport()
        }
        // V4.37.1: ⌘Y Quick Look——复用 showQuickLook()（与空格键同路径）
        controller.onQuickLook = { [weak self] in
            self?.core?.grid.showQuickLook()
        }
        // V4.37.2: ⌘[ / ⌘] 上下张切换（macOS Quick Look 标准）
        controller.onPrev = { [weak self] in
            self?.core?.grid.goPrev()
        }
        controller.onNext = { [weak self] in
            self?.core?.grid.goNext()
        }
        // V5.24: 布局模式 + 密度 toolbar 集成桥接
        // V6.12.14: ThumbnailLayoutMode 加 .list 后——选 .list 切 viewMode = .list
        controller.onLayoutModeChange = { [weak self] mode in
            guard let model = self?.core else { return }
            model.layoutMode = mode
            switch mode {
            case .list:
                model.viewMode = .list
            case .squareFit:
                model.viewMode = .grid
            }
        }
        controller.onDensityChange = { [weak self] density in
            guard let model = self?.core else { return }
            model.grid.thumbnailSize = density
            // 同步 storedThumbnailSize 以便重启后恢复（V4.15.0 ⌘0 行为一致）
            model.settings.thumbnailSize = Double(density)
        }
        // V5.39.3: 排序 toolbar 桥接
        controller.onSortOptionChange = { [weak self] newSort in
            self?.core?.grid.sortOption = newSort
        }
        // V4.90.0: filterContentProvider 改 filterCoordinatorFactory
        //   folders/allTags 是 Q-bucket (view-owned), 由 GridViewModel 缓存
        controller.filterCoordinatorFactory = { [weak self] onStateChange in
            FilterPopoverCoordinator(
                folders: self?.core?.grid.folders ?? [],
                tags: self?.core?.grid.allTags ?? [],
                onStateChange: { newState in
                    self?.core?.filterState = newState
                    onStateChange(newState)
                }
            )
        }
        // V4.36.x: 首次同步角标
        controller.filterActiveCount = core?.filterState.activeCount ?? 0
        // V4.8.1: search field 改用 NSSearchField
        controller.onSearchTextChanged = { [weak self] newText in
            guard let model = self?.core else { return }
            if model.grid.searchText != newText {
                model.grid.searchText = newText
            }
        }

        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden

        // V4.37.4: titlebar 右上角小按钮（Photos.app ⓘ 风格）
        let accessory = TitlebarAccessoryController(
            inactiveSymbol: "info.circle",
            activeSymbol: "info.circle.fill",
            accessibilityLabel: Copy.titlebarInfoLabel,
            tooltip: titlebarAccessoryTooltip(isActive: settings.showDetail),
            onAction: { [weak self] in
                withAnimation(Animations.medium) { self?.settings.showDetail.toggle() }
            }
        )
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
        titlebarAccessory = accessory
        accessory.setActive(settings.showDetail)

        // 初始 enabled 状态同步
        controller.updateAllStates(
            hasSelection: core?.grid.selection.hasSelection ?? false,
            hasMultipleSelection: core?.grid.selection.isMultiSelect ?? false
        )
    }

    /// V4.37.4: titlebar ⓘ 按钮 tooltip
    func titlebarAccessoryTooltip(isActive: Bool) -> String {
        isActive ? Copy.titlebarInfoTooltipHide : Copy.titlebarInfoTooltipShow
    }
}
