//
//  ContentView+GridInput.swift
//  ImageGallery
//
//  V5.51-4: 从 ContentView.swift 抽出 gridInputHandling modifier
//  原位置 ContentView.swift:1744-1862
//  V4.10.0 引入——把 .onDeleteCommand + .focusable + 11 个 .onKeyPress 打包
//

import SwiftUI

// MARK: - V4.10.0: grid input handling extension
//
// 把 .onDeleteCommand + .focusable + 7 个 .onKeyPress（←→ESC / ⌘A / ⌘+ / ⌘- / ⌘0 / ⌘E / Space）打包。
// 同样的"抽到 extension 避免 type-check 超时"模式参考 applySettingsChrome / appLifecycleHooks。
extension View {
    func gridInputHandling(
        canPrev: Bool,
        canNext: Bool,
        hasSelection: Bool,
        onDelete: @escaping () -> Void,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        // V4.12.0: 空格键 QuickLook（macOS Finder/Photos 标准）
        hasSelectedPhoto: Bool,
        onSpace: @escaping () -> Void,
        // V4.15.0: ⌘0 reset zoom（macOS Photos/Finder 标准）
        onResetZoom: @escaping () -> Void,
        // V4.17.0: ⌘E 导出（macOS Finder 标准，⌘L 撤回——与 macOS Get Info 冲突）
        onExport: @escaping () -> Void,
        // V4.49.1: ⌘↩ Return 进入沉浸式查看（macOS Photos 标准）
        //   仅选中单张时有效——多选/无选 .ignored
        onReturn: @escaping () -> Void
    ) -> some View {
        self
            .onDeleteCommand(perform: onDelete)
            .focusable()
            .onKeyPress(.leftArrow) {
                if canPrev { onPrev() }
                return .handled
            }
            .onKeyPress(.rightArrow) {
                if canNext { onNext() }
                return .handled
            }
            .onKeyPress(.escape) {
                if hasSelection {
                    onEscape()
                    return .handled
                }
                return .ignored
            }
            // V4.12.0: 空格键 QuickLook——无选中时不响应（macOS Finder 行为一致）
            .onKeyPress(.space) {
                if hasSelectedPhoto {
                    onSpace()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("a", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    // V3.6.52: 用 selection.settingAll(in:) 替手写 Set 构造
                    onSelectAll()
                    return .handled
                }
                return .ignored
            }
            // V4.0.0.6: ⌘+ / ⌘- 缩放快捷键（缩放搬到侧栏顶部后必须配快捷键）
            .onKeyPress("+", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onZoomIn()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("-", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onZoomOut()
                    return .handled
                }
                return .ignored
            }
            // V4.15.0: ⌘0 reset zoom（macOS Photos/Finder 标准）—— 恢复 storedThumbnailSize
            .onKeyPress("0", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onResetZoom()
                    return .handled
                }
                return .ignored
            }
            // V4.17.0: ⌘E 导出（macOS Finder 标准）—— 走 batchExport 路径，
            //   单张多张都弹 NSOpenPanel 选目录
            .onKeyPress("e", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    onExport()
                    return .handled
                }
                return .ignored
            }
            // V4.49.1: ⌘↩ Return 进入沉浸式查看（macOS Photos 标准）
            //   Photos.app 用 Return 键进入全屏图片——快捷键 ⌘↩ 标准
            //   仅在 gridInputHandling 接受（多选/无选 .ignored 内部检查）
            .onKeyPress(.return) {
                onReturn()
                return .handled
            }
            // V4.37.2: ⌘[ / ⌘] 上下张切换（macOS Quick Look / Finder 标准）
            //   Photos.app 用 ←→ 方向键（gridInputHandling 已有）
            //   ⌘[/⌘] 是 macOS Quick Look 整个列表翻页的同款快捷键
            .onKeyPress("[", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    if canPrev { onPrev() }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("]", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    if canNext { onNext() }
                    return .handled
                }
                return .ignored
            }
    }
}
