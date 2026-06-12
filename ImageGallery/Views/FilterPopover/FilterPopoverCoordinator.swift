//
//  FilterPopoverCoordinator.swift
//  ImageGallery
//
//  V4.89.0 NEW: 父子 FilterPopover lifecycle 管理
//    FilterPopover 拆 2 层 popover 重构 Phase 3
//    顶层 + 4 个子 popover 全部走 coordinator 强引用
//
//  关键设计：
//    - 强引用 topPopover + childPopover（不释放）
//    - 父子都 .transient——macOS 标准 transient 行为
//    - 子 anchor 用顶层 row.bounds（不是 toolbar 按钮）
//    - 子 popover viewDidDisappear → 父恢复顶层行为
//    - 顶层 viewDidDisappear → 强制 close child（防 orphan）
//
//  Why coordinator（而非放进 ContentView @State）：
//    - ContentView 关闭时 popover lifecycle 不被监听
//    - 父子 popover 引用需要强引用——@State 不合适
//    - lifecycle 集中管理——coordinator 是单例或 ToolbarController 持有的对象
//

import AppKit

/// V4.89.0: 父子 FilterPopover lifecycle 管理
///   - 强引用 top + child
///   - 子 popover 创建 + 锚定到 row.bounds
///   - 父子 lifecycle 协同（子关 → 父保持；父关 → 强制 close child）
@MainActor
final class FilterPopoverCoordinator {
    // MARK: - 状态

    /// V5.9: 改为 internal（默认）——ToolbarController 需在 popoverDidClose 区分顶层 popover
    ///   配合 ToolbarController.popoverDidClose 用 popover === topPopover 判断
    private(set) var topPopover: NSPopover?
    private var childPopover: NSPopover?

    /// V4.89.0: 当前打开的子 popover 类别——close 后清 nil
    private var currentChildCategory: FilterCategory?

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

    /// V4.90.0: 顶层 popover 是否显示——ToolbarController 用此判断 toggle
    var isTopShown: Bool { topPopover?.isShown == true }

    // MARK: - 顶层 popover

    /// V4.89.0: 显示顶层 popover——锚定到 toolbar 按钮
    ///   - 每次显示新建 NSPopover + FilterTopPopoverViewController（V4.84.0）
    ///   - 顶层 row 点击 → onCategoryTap closure 转发给 openChild(_:)
    ///   - toggle（再点 toolbar）→ 关闭顶层 + 强制 close child
    func showTop(anchoredTo anchor: NSView) {
        // V4.89.0: 切换关闭（再点 toolbar 按钮 toggle）
        if let top = topPopover, top.isShown {
            top.close()
            topPopover = nil
            closeChild()
            return
        }

        let topVC = FilterTopPopoverViewController(filterState: FilterState())
        // V4.89.0: row tap → openChild
        topVC.onCategoryTap = { [weak self] category in
            guard let self = self, let anchor = self.anchorForCategory(category) else { return }
            self.openChild(category, anchoredTo: anchor)
        }
        // V4.89.0: 清除 → 写回 ContentView
        topVC.onStateChange = { [weak self] newState in
            self?.onStateChange(newState)
        }
        topVC.onClearAll = { [weak self] in
            guard let self = self else { return }
            let empty = FilterState.empty
            self.onStateChange(empty)
            // 重建顶层——4 row count badge 重置
            topVC.updateState(empty)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = topVC
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        topPopover = popover
    }

    /// V5.9.4: 用 positioningView + rect 显示顶层 popover——避开 view-based anchor 的两个坑
    ///   1) 刚创建的 NSButton 还没进 window，anchor 无效
    ///   2) .transient race condition：click 事件流持续 → 立即关闭
    ///   用 contentView 作 positioningView（永远在 window 里）
    ///   rect 是 1x1 像素小矩形，位置在按钮底部中心
    func showTopAtRect(_ rect: NSRect, positioningView: NSView) {
        // V4.89.0: 切换关闭（再点 toolbar 按钮 toggle）
        if let top = topPopover, top.isShown {
            top.close()
            topPopover = nil
            closeChild()
            return
        }

        let topVC = FilterTopPopoverViewController(filterState: FilterState())
        topVC.onCategoryTap = { [weak self] category in
            guard let self = self, let anchor = self.anchorForCategory(category) else { return }
            self.openChild(category, anchoredTo: anchor)
        }
        topVC.onStateChange = { [weak self] newState in
            self?.onStateChange(newState)
        }
        topVC.onClearAll = { [weak self] in
            guard let self = self else { return }
            let empty = FilterState.empty
            self.onStateChange(empty)
            topVC.updateState(empty)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = topVC
        // V5.9.4: positioningView + rect 路径——避开 view-based anchor 的两个坑
        popover.show(relativeTo: rect, of: positioningView, preferredEdge: .minY)
        topPopover = popover
    }

    // MARK: - 子 popover

    /// V4.89.0: 显示子 popover——锚定到顶层 row.bounds
    ///   - 关闭旧 child（切到另一个类别）
    ///   - 新 child 创建 + 锚定
    private func openChild(_ category: FilterCategory, anchoredTo anchor: NSView) {
        // V4.89.0: 切到另一类别时关旧
        if childPopover?.isShown == true {
            childPopover?.close()
            childPopover = nil
            currentChildCategory = nil
        }

        // V4.89.0: 当前 filterState——从 topVC 取
        guard let topVC = topPopover?.contentViewController as? FilterTopPopoverViewController else { return }
        let state = currentFilterState(from: topVC)

        let childVC = makeChildViewController(category: category, filterState: state)
        // V4.89.0: 子 popover 接收状态变化→写回 ContentView + 顶层 rebuild
        attachStateChangeHandler(to: childVC) { [weak self, weak topVC] newState in
            guard let self = self else { return }
            self.onStateChange(newState)
            topVC?.updateState(newState)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = childVC
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        childPopover = popover
        currentChildCategory = category
        // V5.9: 顶层 row 标 active——行变 85% accent + 白前景
        topVC.setActiveCategory(category)
    }

    private func closeChild() {
        childPopover?.close()
        childPopover = nil
        currentChildCategory = nil
        // V5.9: 取消顶层 row active——所有 row 回到 default/hover 态
        if let topVC = topPopover?.contentViewController as? FilterTopPopoverViewController {
            topVC.setActiveCategory(nil)
        }
    }

    // MARK: - 关闭全部

    /// V4.89.0: 顶层 + 子 popover 都关（外部清理用）
    func closeAll() {
        closeChild()
        topPopover?.close()
        topPopover = nil
    }

    // MARK: - helpers

    /// V4.89.0: 从顶层 VC 取当前 filterState
    private func currentFilterState(from topVC: FilterTopPopoverViewController) -> FilterState {
        // FilterTopPopoverViewController 内有 filterState private——读不到
        // 改用最新 onStateChange 回调存的 state——本 commit 暂用 fallback
        // 后续 commit 用 closure capture state（V4.90+ 优化）
        return lastWrittenState ?? FilterState()
    }

    private var lastWrittenState: FilterState?

    /// V4.89.0: 子 popover 创建（按 category 分发）
    private func makeChildViewController(category: FilterCategory, filterState: FilterState) -> NSViewController {
        lastWrittenState = filterState
        switch category {
        case .folder:
            return FolderFilterPopoverController(filterState: filterState, folders: folders)
        case .tag:
            return TagFilterPopoverController(filterState: filterState, tags: tags)
        case .shape:
            return ShapeFilterPopoverController(filterState: filterState)
        case .rating:
            return RatingFilterPopoverController(filterState: filterState)
        }
    }

    /// V4.89.0: 顶层 row 锚点——coordinator 持 rowCache 引用
    ///   实际 row 是 topVC.view 子 view——这里简化用临时 view
    ///   后续 commit 用 rowCache 强引用
    private func anchorForCategory(_ category: FilterCategory) -> NSView? {
        guard let topVC = topPopover?.contentViewController as? FilterTopPopoverViewController else { return nil }
        return topVC.view  // fallback：锚到顶层 view（实际 popover.show 仍 work）
    }

    // MARK: - 子 popover 回调 attach

    /// V4.89.0: 通用 attach 子 popover onStateChange——4 类子 popover 都有 onStateChange 成员
    ///   Swift 不能直接给 NSViewController 公共成员设值——用 mirror 检查
    private func attachStateChangeHandler(
        to vc: NSViewController,
        handler: @escaping (FilterState) -> Void
    ) {
        // 4 个子 popover 都有 var onStateChange: ((FilterState) -> Void)?
        //   - FolderFilterPopoverController / TagFilterPopoverController
        //   - ShapeFilterPopoverController / RatingFilterPopoverController
        // Swift 静态派发——必须 cast 到具体类型
        if let vc = vc as? FolderFilterPopoverController {
            vc.onStateChange = handler
        } else if let vc = vc as? TagFilterPopoverController {
            vc.onStateChange = handler
        } else if let vc = vc as? ShapeFilterPopoverController {
            vc.onStateChange = handler
        } else if let vc = vc as? RatingFilterPopoverController {
            vc.onStateChange = handler
        }
    }
}
