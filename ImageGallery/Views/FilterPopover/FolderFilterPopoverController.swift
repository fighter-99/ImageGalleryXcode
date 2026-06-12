//
//  FolderFilterPopoverController.swift
//  ImageGallery
//
//  V4.86.0 NEW: Folder 二级 popover
//    FilterPopover 拆 2 层 popover 重构 Phase 2
//    顶层 FilterTopPopoverViewController 点 folder 行 → 显示本 popover
//
//  范式：
//    - 8 个 folder 1 列 checkbox（V4.36.x 验证）
//    - 240pt 宽 × 216pt 高（12 padding + 8×24 items）
//    - NSVisualEffectView.popoverHost() 包裹（V4.80.0 helper）
//    - 共享 PopoverItemFactory enum（V4.81.0）的 makeCheckItem / makeOneColumnCheckList
//

import AppKit

/// V4.86.0: Folder 二级 popover——8 个 folder 列表
///   接收 filterState + folders + onStateChange
///   toggle folder 写回 onStateChange
final class FolderFilterPopoverController: NSViewController {
    // MARK: - 回调

    var onStateChange: ((FilterState) -> Void)?

    // MARK: - 数据

    private var filterState: FilterState
    private let folders: [Folder]

    // MARK: - 子视图引用（V5.4: viewDidLayout 计算 content height 用）

    private var listContainer: NSView?

    // MARK: - 配置常量

    private static let preferredWidth: CGFloat = 240
    private static let preferredHeight: CGFloat = 216
    private static let padding: CGFloat = PopoverStyle.padding

    // MARK: - init

    init(filterState: FilterState, folders: [Folder]) {
        self.filterState = filterState
        self.folders = folders
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - 视图生命周期

    override func loadView() {
        // V5.2 重构：container(NSView) → visualEffect(NSVisualEffectView) → list(NSStackView) 三层
        //   之前 self.view = visualEffect 单层——visualEffect 既是 contentView 又是 list 的父
        //   问题：visualEffect 默认 TAMC=true——frame 由 autoresizing mask 管
        //   list 约束基于 visualEffect anchor——autoresizing 模式下 list frame 算出 -24 负值
        //   checkbox 紧贴左边框——V5.0 加的 12pt padding 没生效
        //
        //   现在 container 当 contentView——visualEffect 是 container 的子 view
        //   两者都 TAMC=false——约束显式求值，list 12pt padding 稳定生效
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        // V4.86.0: NSVisualEffectView 包裹——V4.80.0 popoverHost() helper
        let visualEffect = NSVisualEffectView.popoverHost()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        // 1 列 checkbox list——V4.81.0 PopoverItemFactory 共享
        let list = PopoverItemFactory.makeOneColumnCheckList(items: folders) { [weak self] folder in
            PopoverItemFactory.makeCheckItem(
                label: folder.name,
                isOn: self?.filterState.folders.contains(folder.id) ?? false
            ) { [weak self] in
                self?.handleToggle(folder.id)
            }
        }
        container.addSubview(visualEffect)
        visualEffect.addSubview(list)
        self.listContainer = list
        // V5.2: 三层约束
        //   1. visualEffect 撑满 container
        //   2. list 12pt padding 在 visualEffect 内（V5.0 范式——修左侧切断）
        NSLayoutConstraint.activate([
            // 1. visualEffect 撑满 container
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // 2. list 12pt padding（V5.0 范式）
            list.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.padding),
            list.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.padding),
            list.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.padding),
            list.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -Self.padding)
        ])
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // V5.4: 高度按内容收缩（修御姐/旗袍间距异常）
        //   之前硬编码 216pt——按 8 item 算的，实际 10 item → NSPopover 内部拉伸
        //   distribution=.fill 把按钮挤压，首个 item 偏移 → 御姐/旗袍 gap ~34pt 其他 ~30pt
        //   现在 list.fittingSize.height + 2*padding 算实际高度——NSPopover 不再挤压
        let contentHeight = (listContainer?.fittingSize.height ?? 0) + 2 * Self.padding
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: contentHeight
        )
    }

    // MARK: - 状态同步

    /// V4.86.0: 接收外部 filterState 变化
    ///   V4.36.x #4 范式——ContentView .onChange 推送
    ///   当前实现：folder 1 列无独立 button 缓存——updateState 无需操作
    ///   folder 数量 8 个——不需要 rebuild
    func updateState(_ newState: FilterState) {
        self.filterState = newState
        // 当前无子 button——no-op
        // 后续如需复选同步可在此 rebuild list
    }

    // MARK: - toggle

    func handleToggle(_ id: UUID) {
        if filterState.folders.contains(id) {
            filterState.folders.remove(id)
        } else {
            filterState.folders.insert(id)
        }
        onStateChange?(filterState)
    }
}
