//
//  TitlebarFrostedGlass.swift
//  ImageGallery
//
//  V5.48 NEW: macOS Photos.app 风格磨砂玻璃 titlebar/toolbar 背景
//  Photos/Finder/Safari/Notes 等系统 app 都有统一半透 titlebar+toolbar 区域
//
//  macOS API: NSVisualEffectView (AppKit 原生)
//    - material = .bar → 工具栏/标题栏专用磨砂玻璃
//    - blendingMode = .behindWindow → 内容滚动时半透显示
//    - state = .followsWindowActiveState → 失焦时变暗（macOS 标准行为）
//
//  与 V4.37.3 TitlebarAccessoryController 关系：
//    - TitlebarAccessoryController: titlebar 区域内的 ⓘ 按钮（layoutAttribute = .trailing）
//    - TitlebarFrostedGlass: titlebar+toolbar 整条背景（插入 window.contentView 顶部）
//    两者 z-order: visualEffect 在底，按钮系统渲染在最上面
//
//  V5.48 之前: window.titlebarAppearsTransparent = true → 系统默认浅灰/深灰纯色填充
//  V5.48 之后: 显式 .bar material → Photos.app 风格磨砂玻璃
//

import AppKit

/// V5.48: titlebar+toolbar 整条的磨砂玻璃背景
/// Photos/Finder/Safari 风格——内容滚动时半透显示
///
/// 实现要点:
///   - NSVisualEffectView (AppKit 原生, macOS 10.10+)
///   - material = .bar (工具栏/标题栏专用 material, 比 .regular 浅)
///   - blendingMode = .behindWindow (窗口内容透过来, 形成磨砂效果)
///   - state = .followsWindowActiveState (失焦时自动变暗)
///   - autoresizingMask = [.width] (宽度跟窗口, 高度固定 52pt)
@MainActor
final class TitlebarFrostedGlass: NSVisualEffectView {
    /// V5.48: unified titlebar+toolbar 合并高度 = titlebar 28pt + toolbar 24pt ≈ 52pt
    /// 实测 macOS Sonoma 上 .unified style 是 52pt, 后续 macOS 版本可能变
    /// 保守写 52——Toolbar 高度可调
    static let height: CGFloat = 52

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: TitlebarFrostedGlass.height))
        // V5.48: .titlebar material——Photos 工具栏/标题栏风格
        //   NSVisualEffectView.Material 没有 .bar (SwiftUI 14+ Material 才有)
        //   .titlebar 是 NSVisualEffectView 专为 titlebar/toolbar 设计的材质
        //   .underWindowBackground 比 .titlebar 更深——不适合工具栏
        //   .popover 比 .titlebar 更浅——会"飘"起来
        material = .titlebar
        // V5.48: 内容滚动时半透显示——content 画在 visualEffect 上面
        blendingMode = .behindWindow
        // V5.48: 跟随窗口激活状态——失焦时变暗（macOS 标准行为）
        //   .active 强制亮（少用, 仅特殊场景）
        //   .inactive 强制暗（少用）
        //   .followsWindowActiveState 推荐（用户期望行为）
        state = .followsWindowActiveState
        // V5.48: 宽度跟窗口, 高度由本 view 自身 frame 决定
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        // V5.48: programmatic-only——给空默认值满足 Swift two-phase init
        super.init(coder: coder)
    }
}
