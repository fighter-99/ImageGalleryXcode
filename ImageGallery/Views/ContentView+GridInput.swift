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
        // V6.110.1 (Esc double-press bug fix): immersive 显示时 disable 整个 gridInputHandling
        //   之前 bug: ImmersivePhotoView 是 .overlay, 底层 ContentView.gridInputHandling 仍持焦点
        //     第一次 Esc → gridInputHandling 抢走事件 (清 selection, 返回 .handled)
        //     第二次 Esc → bubble 到 ImmersivePhotoView.onKeyPress(.escape) 才真 dismiss
        //     用户反馈: 第一次 Esc 后删除/快速查看按钮变灰 (因为 selection 清空)
        //   V6.110 试错: ImmersivePhotoView 加 @FocusState 想抢焦点 — 失败, .overlay 不能抢 sibling 焦点
        //   V6.110.1 正确: 让 gridInputHandling 知道 immersive state, 显示时整个 handler 返回 .ignored
        //     Esc → bubble 到 ImmersivePhotoView → 一次就 dismiss (selection 不动, 按钮不变灰)
        hasImmersivePhoto: Bool = false,
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
                // V6.110.1: immersive 显示时不抢 keyboard 事件, 让 ImmersivePhotoView 处理 ←→
                if hasImmersivePhoto { return .ignored }
                if canPrev { onPrev() }
                return .handled
            }
            .onKeyPress(.rightArrow) {
                if hasImmersivePhoto { return .ignored }
                if canNext { onNext() }
                return .handled
            }
            .onKeyPress(.escape) {
                // V6.110.1: immersive 显示时不响应 Esc, bubble 给 ImmersivePhotoView 一次就退出
                //   之前: hasSelection 时返回 .handled → 抢走 Esc → 用户要按 2 次 + selection 被清空 (按钮变灰)
                //   现在: 直接 .ignored → SwiftUI 把事件传给 sibling .overlay 内的 ImmersivePhotoView
                if hasImmersivePhoto { return .ignored }
                if hasSelection {
                    onEscape()
                    return .handled
                }
                return .ignored
            }
            // V4.12.0: 空格键 QuickLook——无选中时不响应（macOS Finder 行为一致）
            .onKeyPress(.space) {
                // V6.110.1: immersive 显示时空格 = ImmersivePhotoView.goNext (next photo)
                if hasImmersivePhoto { return .ignored }
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
            // V6.58 (audit P1.8): 之前无条件 onReturn() — 无选或多选时按 Enter 也进 immersive
            //   (无选时不该进, 多选时不应作为 1 张处理)
            //   现在 gate: 必须有 selection (hasSelection) 才进; 多选留给 caller 内部判断
            .onKeyPress(.return) {
                guard hasSelection else { return .ignored }
                onReturn()
                return .handled
            }
            // V6.96 P1 #4: 删 ⌘[/⌘] onKeyPress 双注册
            //   原 onKeyPress 跟 ImageGalleryApp NavigateMenuItems (.keyboardShortcut("[", modifiers: .command))
            //   同一组键被两处注册, SwiftUI "last-registered wins" 在不同 macOS 版本行为不稳
            //   现在只留菜单: 菜单 .keyboardShortcut 走 NavigateMenuItems 发 .navigatePrev/NextRequested 通知
            //   ContentView .onReceive 监听, 走 canPrev/canNext 边界检查
            //   好处: 菜单项有 label + a11y + ⌘[/⌘] 跟菜单名直接关联, 跟 Photos / Finder 一致
    }
}
