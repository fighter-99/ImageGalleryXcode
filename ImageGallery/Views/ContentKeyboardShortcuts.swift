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
    /// - ⌘O: 导入
    /// - ⌘N: 新建文件夹
    /// - ⌘R: 重置筛选
    /// - ⌘F: 聚焦搜索框
    /// - ⌘C: 复制到剪贴板
    /// - ⌘⇧S: 切换排序方向
    /// - ⌘⌃S: 切换侧栏显隐（macOS 标准）
    /// - ⌘Z / ⌘⇧Z: 撤销 / 重做（V4.7.0 起由 Edit menu 接管——见 ImageGalleryApp.UndoRedoMenuButtons）
    /// - V5.12: ⌘0 清除评分 + ⌘1-⌘5 设为 N 星（仿 macOS Photos 标准）
    /// - V5.15: 删 ⌘1-6 sidebar smart folder 快捷键——⌘1-5 与 rating 评分快捷键冲突
    ///        仿 macOS Photos 把 ⌘1-5 让给 rating（侧栏 mouse 交互 + ⌘⌃S 切显隐足够）
    ///        砍 onToggleFavorite 参数——工具栏 ❤ 已移除
    /// - V5.52-8: 删 sidebarSelection 参数——之前是 dead arg (// _ = sidebarSelection)
    func contentKeyboardShortcuts(
        onImport: @escaping () -> Void,
        onNewFolder: @escaping () -> Void,
        onResetFilters: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onToggleSortDirection: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void,
        onSetRating: @escaping (Int) -> Void = { _ in },  // V5.12: 评分快捷键——⌘0-⌘5
        onUndo: @escaping () -> Void = {},  // V4.7.0: 不再使用——保留参数避免破坏调用点
        onRedo: @escaping () -> Void = {},  // V4.7.0: 不再使用——保留参数避免破坏调用点
        onFocusSearch: @escaping () -> Void = {},  // V3.6.23: ⌘F 聚焦搜索框（V3.5 ⌘F 之前给收藏，移除避免冲突 — 收藏快捷键改 ⌘D）
        // V5.7: 砍 onToggleFavorite 参数——工具栏 ❤ 收藏按钮已移除
        onToggleFavorite: @escaping () -> Void = {}  // V5.7: 保留默认空实现，调用点不破坏
    ) -> some View {
        // V5.13：抽到 RatingShortcuts.routes 路由表，便于测试
        //   用 local @ViewBuilder function 避免 Group 内混合 Button + ForEach 触发类型推断失败
        @ViewBuilder
        func makeRatingButtons() -> some View {
            ForEach(RatingShortcuts.routes, id: \.rating) { route in
                Button("") { onSetRating(route.rating) }
                    .keyboardShortcut(route.key, modifiers: route.modifiers)
                    .hidden()
            }
        }

        return background {
            Group {
                Button("") { onImport() }
                    .keyboardShortcut("o", modifiers: .command)
                    .hidden()
                // V5.15：删 ⌘1-6 sidebar smart folder 快捷键——⌘1-5 与 rating 评分快捷键冲突
                //   仿 macOS Photos 把 ⌘1-5 让给 rating
                //   sidebar 仍可 ⌘⌃S 切显隐 + 鼠标点击
                // V5.52-8: 删 sidebarSelection dead arg (原 // _ = sidebarSelection 防破坏)

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
                // V6.58 (audit P1.7): 改用 ⌘\ 避开 ⌘⇧S (sort) 的 s 字面冲突
                //   之前两个 hidden Button 都绑 `s` (不同 modifier) — SwiftUI 在某些 macOS 版本
                //   modifier-disambiguation 不稳, last-registered wins, 1 个 shortcut 静默失效
                // V6.103.4: 删 hidden button — ImageGalleryApp.swift:601 Toggle menu item 已绑 ⌘\,
                //   双触发让 showSidebar toggle 2 次 = 净效果 0, sidebar 不动 (V6.103.1/2/3 修错地方)
                //   现在只留 menu Toggle (macOS 真版范式: View 菜单 Toggle + ⌘\)

                // V5.12: ⌘0 清除评分 + ⌘1-⌘5 设为 N 星（仿 macOS Photos 标准）
                // V5.15: ⌘1-6 sidebar 已删——⌘0-5 独占
                //   ⌘D/⌘F 等给搜索/收藏之类——V5.7 已释放 ⌘F 槽位
                // V5.13：抽到 RatingShortcuts.routes 路由表，便于测试
                makeRatingButtons()

                // V4.7.0: ⌘Z 撤销 / ⌘⇧Z 重做 改由 Edit menu 接管（ImageGalleryApp.UndoRedoMenuButtons）
                //   之前这里有 hidden Button 触发 onUndo/onRedo
                //   现在移除——避免与 menu 双触发
                //   onUndo/onRedo 参数保留默认空实现，调用点不破坏
            }
        }
    }
}
