//
//  TitlebarFrostedGlass.swift
//  ImageGallery
//
//  V5.48 NEW: macOS Photos.app 风格磨砂玻璃 titlebar/toolbar 背景
//  Photos/Finder/Safari/Notes 等系统 app 都有统一半透 titlebar+toolbar 区域
//
//  macOS API: NSVisualEffectView (AppKit 原生)
//    - material = .titlebar → 工具栏/标题栏专用磨砂玻璃
//    - blendingMode = .behindWindow → 内容滚动时半透显示
//    - state = .followsWindowActiveState → 失焦时变暗（macOS 标准行为）
//
//  V5.48-3: 用 NSTitlebarAccessoryViewController 接入（不用 window.contentView）
//    - 之前 V5.48-2 错把 visualEffect 加到 window.contentView
//    - contentView 是工具栏**下方**的内容区, 永远只能是"工具栏下方的 strip"
//    - 用户要求"工具栏**本身**有磨砂玻璃"——必须把 visualEffect 加到 titlebar 区域
//    - NSTitlebarAccessoryViewController.layoutAttribute = .top 把 view 放在 unified titlebar+toolbar 区域上方
//    - toolbar items 渲染在 accessory view 上面——视觉"工具栏有磨砂玻璃"
//
//  与 V4.37.3 TitlebarAccessoryController 关系：
//    - TitlebarAccessoryController: layoutAttribute = .trailing (右上角 ⓘ 按钮)
//    - TitlebarFrostedGlassController: layoutAttribute = .top (整条磨砂玻璃背景)
//    两者都加在 titlebar 区域, z-order 互不干扰
//
//  V6.12.3.1: ⚠️ 上方"toolbar items 渲染在 accessory 上面"是错的, 实际不能 work
//    V6.12.3 试图在 ContentViewModel 配置 toolbar 时挂载本 controller, 实测:
//      layoutAttribute = .top + .titlebar material + 52pt 高 + window.titleVisibility = .hidden
//      + window.toolbarStyle = .unified 一起用时, accessory view 压住 toolbar 区域,
//      toolbar 按钮不可见, 整个顶部变灰色长条.
//    本类写好了但**不要直接挂载**——除非有人找到正确的 z-order / layout 处理方式.
//    替代方案: 依赖 macOS 系统提供的 .unified toolbar style 自动 vibrancy (本项目已在用),
//    或重新设计 accessory 高度 / blending 关系.
//    决定: 暂保留类不动, 加这条注释防 V6.13+ 再踩坑.
//


import AppKit

/// V5.48: titlebar+toolbar 整条的磨砂玻璃背景
/// Photos/Finder/Safari 风格——内容滚动时半透显示
///
/// 实现要点:
///   - NSVisualEffectView (AppKit 原生, macOS 10.10+)
///   - material = .titlebar (工具栏/标题栏专用 material)
///   - blendingMode = .behindWindow (窗口内容透过来, 形成磨砂效果)
///   - state = .followsWindowActiveState (失焦时自动变暗)
///   - 全宽 + 固定 52pt 高 (unified titlebar+toolbar 合并高度)
@MainActor
final class TitlebarFrostedGlass: NSVisualEffectView {
    /// V5.48: unified titlebar+toolbar 合并高度 = titlebar 28pt + toolbar 24pt ≈ 52pt
    static let height: CGFloat = 52

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: TitlebarFrostedGlass.height))
        // V5.48: .titlebar material——Photos 工具栏风格
        //   NSVisualEffectView.Material 没有 .bar (SwiftUI 14+ 才有)
        //   .titlebar 是 NSVisualEffectView 专为 titlebar/toolbar 设计的材质
        material = .titlebar
        // V5.48: 内容滚动时半透显示
        blendingMode = .behindWindow
        // V5.48: 跟随窗口激活状态——失焦时变暗（macOS 标准行为）
        state = .followsWindowActiveState
    }

    required init?(coder: NSCoder) {
        // V5.48: programmatic-only——给空默认值满足 Swift two-phase init
        super.init(coder: coder)
    }
}

/// V5.48-3 NEW: NSTitlebarAccessoryViewController 包装
///   - layoutAttribute = .top → accessory view 放在 unified titlebar+toolbar 区域顶部
///   - view 容纳 TitlebarFrostedGlass (NSVisualEffectView)
///   - 全宽 (用 widthAnchor 拉到窗口宽)
///   - 高度 = 52pt (unified titlebar+toolbar 合并高度)
///
/// 与 V4.37.3 TitlebarAccessoryController 关系:
///   - V4.37.3: layoutAttribute = .trailing (右上角 ⓘ 按钮, 小尺寸)
///   - V5.48-3: layoutAttribute = .top (整条磨砂玻璃背景, 大尺寸)
///   两者都是 titlebar accessory, 系统分别渲染, 互不干扰
@MainActor
final class TitlebarFrostedGlassController: NSTitlebarAccessoryViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        let visualEffect = TitlebarFrostedGlass()
        // V5.48-3: accessory view 容纳 visualEffect
        //   visualEffect 全宽 + 52pt 高 (unified titlebar+toolbar 合并高度)
        view = visualEffect
        // V5.48-3: layoutAttribute = .top → 把 accessory 放在 titlebar 区域顶部
        //   在 .unified 风格下, "顶部" = 整个 unified titlebar+toolbar 区域上方
        //   toolbar items 渲染在 accessory 上面——视觉"工具栏有磨砂玻璃"
        layoutAttribute = .top
    }

    required init?(coder: NSCoder) {
        // V5.48-3: programmatic-only——给空默认值满足 Swift two-phase init
        super.init(coder: coder)
    }

    /// V5.48-3: view 装入后设约束——visualEffect 填满 accessory view
    ///   NSTitlebarAccessoryViewController 的 view 尺寸由系统根据 layoutAttribute 决定
    ///   这里用 anchor 拉 visualEffect 到 view 边界
    override func loadView() {
        super.loadView()
        guard let visualEffect = view as? TitlebarFrostedGlass else { return }
        // 全宽 + 全高——让 visualEffect 跟 accessory view 边界一致
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
