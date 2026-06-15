//
//  FilterPopoverCoordinator.swift
//  ImageGallery
//
//  V4.89.0 NEW: 父子 FilterPopover lifecycle 管理
//  V5.63-1: 重设计——单 popover (FilterUnifiedPopoverController) 替代 2 级 popover
//    删顶层 4-row 入口 + 4 个子 popover controllers, 1 个 unified popover 内 4 可折叠 sections
//    lifecycle 简化为: 强引用 singlePopover, .transient (V5.62-1), click-outside 自动关
//

import AppKit

/// V4.89.0: 父子 FilterPopover lifecycle 管理
/// V5.63-1: 简化为单一 popover lifecycle——1 个 NSPopover, 无子
@MainActor
final class FilterPopoverCoordinator {
    // MARK: - 状态

    /// V5.63-1: 单一 popover 引用——替代 V4.89.0 顶层 + 子 2 个
    private(set) var filterPopover: NSPopover?

    // MARK: - 数据

    private let folders: [Folder]
    private let tags: [Tag]

    // MARK: - 回调（由 ContentView 注入）

    /// V4.89.0: filterState 写回 ContentView
    private let onStateChange: (FilterState) -> Void

    // MARK: - init

    init(folders: [Folder], tags: [Tag], onStateChange: @escaping (FilterState) -> Void) {
        self.folders = folders
        self.tags = tags
        self.onStateChange = onStateChange
    }

    // MARK: - 公开状态

    /// V4.90.0: popover 是否显示——ToolbarController 用此判断 toggle
    var isTopShown: Bool { filterPopover?.isShown == true }

    // MARK: - 顶层 popover (V5.63-1: 改为单 popover)

    /// V5.63-1: 显示单 popover——锚定到 toolbar 按钮
    ///   替代 V4.89.0 2 级 popover (顶层 4 row + 子 4 个), 1 个 unified popover
    func showTop(anchoredTo anchor: NSView) {
        // V4.89.0: 切换关闭（再点 toolbar 按钮 toggle）
        if let pop = filterPopover, pop.isShown {
            pop.close()
            filterPopover = nil
            return
        }

        showUnifiedPopover(anchoredTo: anchor, positioningView: nil, rect: .zero)
    }

    /// V5.9.4: 用 positioningView + rect 显示 popover——避开 view-based anchor 的两个坑
    ///   1) 刚创建的 NSButton 还没进 window，anchor 无效
    ///   2) .transient race condition：click 事件流持续 → 立即关闭
    ///   用 contentView 作 positioningView（永远在 window 里）
    ///   rect 是 1x1 像素小矩形，位置在按钮底部中心
    func showTopAtRect(_ rect: NSRect, positioningView: NSView) {
        // V4.89.0: 切换关闭（再点 toolbar 按钮 toggle）
        if let pop = filterPopover, pop.isShown {
            pop.close()
            filterPopover = nil
            return
        }

        showUnifiedPopover(anchoredTo: nil, positioningView: positioningView, rect: rect)
    }

    /// V5.63-1: 共享 popover 创建逻辑——showTop + showTopAtRect 共用
    ///   - view-based anchor (showTop) 或 positioningView+rect (showTopAtRect)
    private func showUnifiedPopover(anchoredTo anchor: NSView?, positioningView: NSView?, rect: NSRect) {
        let vc = FilterUnifiedPopoverController(filterState: FilterState())
        // V5.63-1: 数据注入——folders + tags 给 4 section 用
        vc.setDataSource(folders: folders, tags: tags)
        // V5.63-1: 单一 closure 接管所有变化 (toggle + clear)——替代 V4.89.0 3 个 closure
        vc.onStateChange = { [weak self] newState in
            self?.onStateChange(newState)
        }

        let popover = NSPopover()
        // V5.62-1: 改回 .transient (见之前注释)——click-outside 自动关
        popover.behavior = .transient
        popover.contentViewController = vc

        // V5.73: preferredEdge 统一 .maxY——
        //   真实方向: .minY = above (popover 拓向 LARGER y, 屏幕上方)
        //           .maxY = below (popover 拓向 SMALLER y, 屏幕下方)
        //   filter popover 大 (280x600) 不 fit above, NSPopover auto-flip 到 below (碰巧正确)
        //   layoutMode popover 小 (140x60) fit above, 不 flip, 显式在 button 上方 (用户报不一致)
        //   改 .maxY 后两边都显式 below, 无需依赖 auto-flip
        if let anchor = anchor {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if let positioningView = positioningView {
            popover.show(relativeTo: rect, of: positioningView, preferredEdge: .maxY)
        }
        filterPopover = popover
    }

    // MARK: - 关闭全部 (V5.63-1: 简化为单 popover)

    /// V5.63-1: 简化——只有 1 个 popover 需要关
    func closeAll() {
        filterPopover?.close()
        filterPopover = nil
    }

    /// V5.62-2: 外部 filterState 变化推送——更新 unified popover 视觉
    ///   V5.63-1: 简化为 1 个 VC——只需调 1 次 updateState
    func pushStateToOpenChild(_ newState: FilterState) {
        guard let vc = filterPopover?.contentViewController as? FilterUnifiedPopoverController,
              filterPopover?.isShown == true else { return }
        vc.updateState(newState)
    }
}
