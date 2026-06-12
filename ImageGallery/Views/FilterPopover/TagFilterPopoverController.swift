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
//    - 240pt 宽 × 580pt 高上限（8 行可视 + 滚）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 共享 PopoverItemFactory enum（V4.81.0）的 makeCheckItem / makeOneColumnCheckList
//

import AppKit

/// V4.87.0: Tag 二级 popover——13 个 tag 列表
///   13 > 8 → NSScrollView 兜底（V4.60.0 范式）
final class TagFilterPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState
    private let tags: [Tag]

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
        // V4.87.0: NSVisualEffectView 包裹——V4.80.0 popoverHost() helper
        let visualEffect = NSVisualEffectView.popoverHost()

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

        // V4.87.0: 文档视图 frame——fittingSize 算 content 高度
        //   width = popover 内容宽（240 - 2*12 padding = 216）
        //   height = stack 实际需要的高度
        let docWidth = Self.preferredWidth - 2 * Self.padding
        list.frame = NSRect(x: 0, y: 0, width: docWidth, height: list.fittingSize.height)

        visualEffect.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: 0),
            // V4.99.0: padding 0（scrollview 撑满 visualEffect 边缘）——与 FolderFilterPopover 保持一致
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: 0),
            // V4.60.0: 高度上限——超过时显示 scroller
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxHeight)
        ])
        self.view = visualEffect
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // V4.87.0: 显式 preferredContentSize——580pt 上限（与 V4.60.0 范式一致）
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: Self.maxHeight
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
