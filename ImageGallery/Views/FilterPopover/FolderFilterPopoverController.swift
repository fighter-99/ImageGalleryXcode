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
        // V4.86.0: NSVisualEffectView 包裹——V4.80.0 popoverHost() helper
        let visualEffect = NSVisualEffectView.popoverHost()
        // 1 列 checkbox list——V4.81.0 PopoverItemFactory 共享
        let list = PopoverItemFactory.makeOneColumnCheckList(items: folders) { [weak self] folder in
            PopoverItemFactory.makeCheckItem(
                label: folder.name,
                isOn: self?.filterState.folders.contains(folder.id) ?? false
            ) { [weak self] in
                self?.handleToggle(folder.id)
            }
        }
        visualEffect.addSubview(list)
        // V4.98.0: padding 12 → 6——NSPopover 自身有内置 inset 12pt
        //   之前 padding 12 + popover inset 12 = 24pt 顶部空隙
        //   改 padding 6 → 总空隙 18pt——视觉紧凑
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.padding / 2),
            list.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.padding / 2),
            list.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.padding / 2),
            list.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -Self.padding / 2)
        ])
        self.view = visualEffect
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: Self.preferredHeight
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

    private func handleToggle(_ id: UUID) {
        if filterState.folders.contains(id) {
            filterState.folders.remove(id)
        } else {
            filterState.folders.insert(id)
        }
        onStateChange?(filterState)
    }
}
