//
//  WindowAccessor.swift
//  ImageGallery
//
//  V4.8.0 NEW: NSViewRepresentable 桥接 NSWindow
//
//  用途：SwiftUI WindowGroup 创建的 NSWindow 需要桥接才能挂 NSToolbar
//  （SwiftUI .toolbar 是降级实现，Photos.app 风格必须用 NSToolbar / AppKit）
//
//  机制：
//  - 在 view body 嵌入一个零尺寸 NSView
//  - viewDidMoveToWindow 触发时调用 callback，传入 NSWindow
//  - callback 设置 window.toolbar = NSToolbar(...)，NSToolbar.delegate = ToolbarController.shared
//
//  单 window 安全——WindowGroup 当前项目只有 1 个 main window
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        view.callback = callback
        return view
    }

    // NSViewRepresentable 协议要求:updateNSView 必须显式实现,即使是空 body
    //   之前 V_window_layout_v2 (#6) 我误判"默认实现 empty body 即可"——错的,
    //   编译错:Type 'WindowAccessor' does not conform to protocol 'NSViewRepresentable'
    //
    // 实际行为:updateNSView 在 view 状态更新时被调用(SwiftUI 重渲 body 时),
    //   本 view 是零尺寸一次性 fire 桥接,不需要在 update 阶段做事
    //   callback 已在 viewDidMoveToWindow 里 fire 一次(hasConfigured 守门),
    //   这里只更新 callback 引用(同 #6 分析)
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? WindowAccessorView {
            view.callback = callback
        }
    }
}

/// 自定义 NSView，重写 viewDidMoveToWindow 在 window 设置时回调
private final class WindowAccessorView: NSView {
    /// window minSize 兜底——避免 SwiftUI `.windowResizability(.contentMinSize)` 在
    ///   极端布局下推算过小(例如 detail 关闭后 grid 收缩到 ~300pt,小屏用户挤崩)
    ///   720×480 = Photos.app 类似库的最小可用尺寸(三栏虽挤但仍可读)
    private static let fallbackMinSize = NSSize(width: 720, height: 480)

    var callback: ((NSWindow) -> Void)?
    private var hasConfigured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasConfigured, let window = self.window else { return }
        hasConfigured = true
        // 仅在 caller 没显式设置更小值时应用兜底 —— 避免覆盖未来精细调过的 minSize
        let current = window.minSize
        if current.width < Self.fallbackMinSize.width || current.height < Self.fallbackMinSize.height {
            window.minSize = NSSize(
                width: max(current.width, Self.fallbackMinSize.width),
                height: max(current.height, Self.fallbackMinSize.height)
            )
        }
        // V6.73.1 hotfix: 延迟 1 个 runloop tick — 同步调 callback 设 NSToolbar 会触发
        //   SwiftUI BarAppearanceBridge 在 hosting view 没完成 constraint pass 时 KVO displayMode
        //   EXC_BREAKPOINT crash "Cannot remove an observer for keyPath displayMode because
        //   it is not registered as an observer". 延迟让 SwiftUI NSHostingView 完成 initial constraint
        //   setup 后再 attach NSToolbar, observer 注册就稳定了。
        DispatchQueue.main.async { [weak window] in
            guard let window = window else { return }
            self.callback?(window)
        }
    }
}
