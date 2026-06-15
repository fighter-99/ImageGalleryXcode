//
//  ContentView+ToolbarSync.swift
//  ImageGallery
//
//  V5.51-6: 从 ContentView.swift 抽出 syncNSToolbar* 3 个 helper
//  原位置 ContentView.swift:1674-1742
//  V4.8.1 引入——SwiftUI @State → NSToolbar 桥接
//

import SwiftUI

// MARK: - V4.8.1: NSToolbar 桥接 extension
//
// 抽到 extension 避免 ContentView body 链过长触发 type-check 超时
// （V3.6.17/6.23/4.7.7 教训——body 临界点 ~200 行）
//
// syncNSToolbarSelectionState: SwiftUI @State SelectionState → NSToolbar buttons enabled
// syncNSToolbarSearchField: SwiftUI @State searchText → NSSearchField.stringValue
//
extension View {
    /// V4.8.0: 选中状态变化 → 同步到 NSToolbar 5 actions 的 enabled
    /// V5.24: 加 layoutMode + density 同步——ContentView 状态变化时推 toolbar
    func syncNSToolbarSelectionState(
        selection: SelectionState,
        layoutMode: ThumbnailLayoutMode? = nil,
        density: CGFloat? = nil
    ) -> some View {
        onChange(of: selection.hasSelection) { _, hasSelection in
            // V5.33: 删 layoutMode: 参数——3 模式 toolbar 控件已删
            ToolbarController.shared.updateAllStates(
                hasSelection: hasSelection,
                hasMultipleSelection: selection.isMultiSelect,
                density: density
            )
        }
    }

    // V5.39.3: 砍 syncNSToolbarLayoutMode (V5.33 之前的)——layoutMode 改走 syncNSToolbarAllStates
    //   在 syncNSToolbarAllStates 里一次性推 layoutMode + density + sortOption

    /// V5.39.3 NEW: 统一推 3 个 NSMenu 按钮 state——layoutMode + density + sortOption
    ///   替代 V5.24 syncNSToolbarDensity + V5.33 砍掉的 syncNSToolbarLayoutMode
    ///   ContentView .onChange(of: layoutMode/density/sortOption) 全调这个
    /// V5.66: 加 .task 启动时主动推一次——.onChange 不触发 initial 值, 启动后 toolbar 默认
    ///   .defaultValue (.square 3x3) 与用户 settings (可能 .squareFit 2x2) 失同步
    func syncNSToolbarAllStates(
        layoutMode: ThumbnailLayoutMode,
        density: CGFloat,
        sortOption: SortOption
    ) -> some View {
        self
            .task {
                // V5.66: 启动推一次, 打破 '无 transition 不同步' 陷阱
                ToolbarController.shared.updateAllStates(
                    hasSelection: false,
                    hasMultipleSelection: false,
                    density: density,
                    layoutMode: layoutMode,
                    sortOption: sortOption
                )
            }
            .onChange(of: layoutMode) { _, newMode in
                ToolbarController.shared.updateAllStates(
                    hasSelection: false,
                    hasMultipleSelection: false,
                    layoutMode: newMode
                )
            }
            .onChange(of: density) { _, newDensity in
                ToolbarController.shared.updateAllStates(
                    hasSelection: false,
                    hasMultipleSelection: false,
                    density: newDensity
                )
            }
            .onChange(of: sortOption) { _, newSort in
                ToolbarController.shared.updateAllStates(
                    hasSelection: false,
                    hasMultipleSelection: false,
                    sortOption: newSort
                )
            }
    }

    /// V4.8.1: SwiftUI @State searchText 变化 → 同步到 NSSearchField
    ///   NSSearchField 内部变化由 ToolbarController.onSearchTextChanged 闭包处理（避免循环）
    func syncNSToolbarSearchField(text: String) -> some View {
        onChange(of: text) { _, newValue in
            ToolbarController.shared.setSearchText(newValue)
        }
    }
}
