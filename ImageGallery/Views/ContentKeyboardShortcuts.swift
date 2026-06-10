//
//  ContentKeyboardShortcuts.swift
//  ImageGallery
//
//  ContentView 的全局键盘快捷键集合。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  设计：用 `.background { ... }` 挂载隐藏的 Button + keyboardShortcut，
//  真正的 UI 是 macOS 标准快捷键，Button 只是 SwiftUI 触发键位的机制。
//

import SwiftUI

extension View {
    /// ContentView 的全局快捷键：
    /// - ⌘1-6: 切换侧栏智能文件夹
    /// - ⌘O: 导入
    /// - ⌘N: 新建文件夹
    /// - ⌘R: 重置筛选
    /// - ⌘F: 收藏/取消收藏
    /// - ⌘C: 复制到剪贴板
    /// - ⌘⇧S: 切换排序方向
    /// - ⌘⌃S: 切换侧栏显隐（macOS 标准）
    /// - ⌘Z / ⌘⇧Z: 撤销 / 重做（V4.7.0 起由 Edit menu 接管——见 ImageGalleryApp.UndoRedoMenuButtons）
    func contentKeyboardShortcuts(
        sidebarSelection: Binding<SidebarSelection?>,
        onImport: @escaping () -> Void,
        onNewFolder: @escaping () -> Void,
        onResetFilters: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onToggleSortDirection: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void,
        onUndo: @escaping () -> Void = {},  // V4.7.0: 不再使用——保留参数避免破坏调用点
        onRedo: @escaping () -> Void = {},  // V4.7.0: 不再使用——保留参数避免破坏调用点
        onFocusSearch: @escaping () -> Void = {}  // V3.6.23: ⌘F 聚焦搜索框（V3.5 ⌘F 之前给收藏，移除避免冲突 — 收藏快捷键改 ⌘D）
    ) -> some View {
        background {
            Group {
                Button("") { onImport() }
                    .keyboardShortcut("o", modifiers: .command)
                    .hidden()
                Button("") { sidebarSelection.wrappedValue = .all }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { sidebarSelection.wrappedValue = .favorites }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { sidebarSelection.wrappedValue = .unfiled }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { sidebarSelection.wrappedValue = .duplicates }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { sidebarSelection.wrappedValue = .recent7Days }
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
                Button("") { sidebarSelection.wrappedValue = .largeFiles }
                    .keyboardShortcut("6", modifiers: .command)
                    .hidden()

                Button("") { onNewFolder() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
                Button("") { onResetFilters() }
                    .keyboardShortcut("r", modifiers: .command)
                    .hidden()
                // V3.6.23: ⌘F 改为聚焦搜索框（V3.5 Phase 1 之前 ⌘F 是收藏/取消收藏，现在让位给更常用的搜索）
                Button("") { onFocusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                Button("") { onCopy() }
                    .keyboardShortcut("c", modifiers: .command)
                    .hidden()
                Button("") { onToggleSortDirection() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .hidden()
                // V3.5.12：⌘⌃+S 切换侧栏显隐（macOS 标准）
                Button("") { onToggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .hidden()

                // V4.7.0: ⌘Z 撤销 / ⌘⇧Z 重做 改由 Edit menu 接管（ImageGalleryApp.UndoRedoMenuButtons）
                //   之前这里有 hidden Button 触发 onUndo/onRedo
                //   现在移除——避免与 menu 双触发
                //   onUndo/onRedo 参数保留默认空实现，调用点不破坏
            }
        }
    }
}
