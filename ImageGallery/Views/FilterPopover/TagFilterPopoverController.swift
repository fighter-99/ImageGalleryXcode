//
//  TagFilterPopoverController.swift
//  ImageGallery
//
//  V4.87.0 NEW: Tag 二级 popover
//    FilterPopover 拆 2 层 popover 重构 Phase 2
//    顶层 FilterTopPopoverViewController 点 tag 行 → 显示本 popover
//
//  范式：
//    - 13 个 tag 1 列 checkbox（V4.36.x 验证）
//    - 13 > 8 → NSScrollView 兜底（V4.60.0 范式）
//    - 240pt 宽 × 自适应高（按 content fitting size 收缩——V5.1 修顶部空白）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 共享 PopoverItemFactory enum（V4.81.0）的 makeCheckItem / makeOneColumnCheckList
//
//  V5.1 修：
//    - preferredContentSize.height 不再硬编码 maxHeight
//    - 改用 list.fittingSize.height + 2*padding 计算实际内容高
//    - 内容 ≤ maxHeight 时按内容高收缩，避免子面板内出现一大片空
//    - scrollView 加 12pt 内 padding——修左侧 icon/text 紧贴边框
//

import AppKit

/// V4.87.0: Tag 二级 popover——13 个 tag 列表
///   13 > 8 → NSScrollView 兜底（V4.60.0 范式）
///   V5.1: 高度按内容收缩（修顶部空白 + 左侧切断）
final class TagFilterPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState
    private let tags: [Tag]

    // MARK: - 子视图引用（V5.1: viewDidLayout 计算 content height 用）

    private var listContainer: NSView?

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 240
    private static let maxHeight: CGFloat = 580
    private static let padding: CGFloat = PopoverStyle.padding

    // MARK: - init

    init(filterState: FilterState, tags: [Tag]) {
        self.filterState = filterState
        self.tags = tags
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V5.2 重构：container(NSView) → visualEffect(NSVisualEffectView) → scrollView(NSScrollView) → list(NSStackView) 四层
        //   与 FolderFilterPopoverController V5.2 一致——TAMC=false 显式约束
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        // V4.87.0: NSVisualEffectView 包裹——V4.80.0 popoverHost() helper
        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        // V4.87.0: NSScrollView 兜底——V4.60.0 范式
        //   13 tag > 8 → 高度 > 580pt 上限 → autohidesScrollers 自动显示
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // V4.87.0: 1 列 checkbox list——V4.81.0 PopoverItemFactory 共享
        let list = PopoverItemFactory.makeOneColumnCheckList(items: tags) { [weak self] tag in
            PopoverItemFactory.makeCheckItem(
                label: "#\(tag.name)",
                isOn: self?.filterState.tags.contains(tag.id) ?? false
            ) { [weak self] in
                self?.handleToggle(tag.id)
            }
        }
        scrollView.documentView = list
        self.listContainer = list

        // V4.87.0: 文档视图 frame——fittingSize 算 content 高度
        //   V5.1: 宽度用 popover 内容宽（240 - 2*12 = 216）——padding 由 scrollView 自身约束承担
        //   高度 = stack 实际需要的高度
        let docWidth = Self.preferredWidth - 2 * Self.padding
        list.frame = NSRect(x: 0, y: 0, width: docWidth, height: list.fittingSize.height)

        container.addSubview(visualEffect)
        visualEffect.addSubview(scrollView)
        // V5.1: scrollView 加 12pt 内 padding——修左侧 icon/text 紧贴边框
        // V5.2: 改用 container 三层范式——TAMC=false 显式约束
        NSLayoutConstraint.activate([
            // 1. visualEffect 撑满 container
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 2. scrollView 在 visualEffect 内 12pt padding
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.padding),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.padding),
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.padding),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -Self.padding),
            // V4.60.0: 高度上限——超过时显示 scroller
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxHeight - 2 * Self.padding)
        ])
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // V5.1: 高度按内容收缩（修顶部空白）
        //   之前：硬编码 maxHeight (580) → 内容仅 ~340pt → 上半大片空
        //   现在：list.fittingSize.height + padding → 内容高自适应
        //   上限仍是 maxHeight（超过时显示 scroller）
        let contentHeight = (listContainer?.fittingSize.height ?? 0) + 2 * Self.padding
        let clampedHeight = min(contentHeight, Self.maxHeight)
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: clampedHeight
        )
    }

    // MARK: - 状态同步

    /// V4.87.0: 接收外部 filterState 变化
    ///   V4.36.x #4 范式——ContentView .onChange 推送
    ///   当前无独立 button 缓存——updateState 无需操作
    ///   13 个 tag 数量稳定
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        // 当前无子 button——no-op
    }

    // MARK: - toggle

    private func handleToggle(_ id: UUID) {
        if filterState.tags.contains(id) {
            filterState.tags.remove(id)
        } else {
            filterState.tags.insert(id)
        }
        onStateChange?(filterState)
    }
}
