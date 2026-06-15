//
//  OptionListItem.swift
//  ImageGallery
//
//  V5.77 NEW: 通用 option list 协议——给 NSPopover 选项列表复用
//    3 个工具栏按钮 (layoutMode / density / sort) V5.72/V5.74/V5.75 各写了一个 ~140 行 popover
//    重复度 99%, 现抽 OptionListItem 协议 + OptionListPopoverController<T> generic
//
//  复用: 任何 enum 满足 OptionListItem 即可用通用 popover, 加新 popover 只需 10 行 conformance
//

import Foundation

/// V5.77: 通用 popover 选项协议——displayName + iconName 两个属性
///   约束: CaseIterable (遍历所有选项) + Equatable (识别当前选中)
protocol OptionListItem: CaseIterable, Equatable {
    /// V5.77: 选项显示名 (e.g. "方格" / "极小" / "导入时间 ↓")
    var displayName: String { get }
    /// V5.77: 选项 SF Symbol 名 (e.g. "square.grid.3x3" / "arrow.up")
    var iconName: String { get }
}

// MARK: - 3 个工具栏 enum conformance

extension ThumbnailLayoutMode: OptionListItem {
    // V5.77: displayName 已存在, icon 改名 iconName 满足协议
    //   ThumbnailLayoutMode.icon → OptionListItem.iconName (alias)
    var iconName: String { icon }
}

extension ThumbnailDensity: OptionListItem {
    // V5.77: iconName 已存在, label 改名 displayName 满足协议
    //   ThumbnailDensity.label → OptionListItem.displayName (alias)
    var displayName: String { label }
}

extension SortOption: OptionListItem {
    // V5.78: 改 alias 源——之前用 directionIcon (只 up/down 箭头) 看不出字段
    //   改 toolbarIcon (clock / textformat.size / externaldrive 区分字段) + 方向 (fill/无 fill)
    //   V5.75 NPPopover 重构时手抖用错, V5.77 generic 沿用 alias 没发现
    var displayName: String { label }
    var iconName: String { toolbarIcon }
}
