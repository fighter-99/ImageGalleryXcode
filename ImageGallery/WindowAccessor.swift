//
//  WindowAccessor.swift
//  ImageGallery
//
//  V4.8.0 NEW: NSViewRepresentable 桥接 NSWindow
//
//  用途：SwiftUI WindowGroup 创建的 NSWindow 需要 AppKit 桥接,做 fallback minSize
//  + setFrameAutosaveName 持久化窗口位置/尺寸
//
//  V6.74.2: callback 改 no-op — 原 NSToolbar 配置入口 (WindowViewModel.configureToolbar) 整方法删
//    ToolbarController / TitlebarAccessoryController 整文件删, 不再需要 AppKit NSToolbar 桥接
//    保留 fallback minSize + setFrameAutosaveName 作为 window chrome 兜底
//  （跟 AppDelegate frame 持久化 V3.7.1 不冲突 — setFrameAutosaveName 走 NSWindowFrame 主键,
//    AppDelegate 写 4-key (size.w/h, position.x/y); 启动 AppDelegate 先跑, setFrameAutosaveName 跳过）
//
//  机制：
//  - 在 view body 嵌入一个零尺寸 NSView
//  - viewDidMoveToWindow 触发时执行 window minSize 兜底 + setFrameAutosaveName
//  - callback 留作 future hook (默认 no-op)
//
//  单 window 安全——WindowGroup 当前项目只有 1 个 main window
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    // V6.74.2: callback 默认 no-op — 原 NSToolbar 唯一 caller 已删, 保留作 future hook
    let callback: (NSWindow) -> Void = { _ in }

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
    //   config 在 viewDidMoveToWindow 里 fire 一次(hasConfigured 守门),
    //   这里只更新 callback 引用
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? WindowAccessorView {
            view.callback = callback
        }
    }
}

/// 自定义 NSView，重写 viewDidMoveToWindow 在 window 设置时执行 chrome 配置
private final class WindowAccessorView: NSView {
    /// window minSize 兜底——避免 SwiftUI `.windowResizability(.contentMinSize)` 在
    ///   极端布局下推算过小(例如 detail 关闭后 grid 收缩到 ~300pt,小屏用户挤崩)
    ///   720×480 = Photos.app 类似库的最小可用尺寸(三栏虽挤但仍可读)
    private static let fallbackMinSize = NSSize(width: 720, height: 480)

    // V6.74.2: callback 默认 no-op — 未来如要 AppKit 桥接再注入
    var callback: ((NSWindow) -> Void)? = { _ in }
    private var hasConfigured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasConfigured, let window = self.window else { return }
        hasConfigured = true
        // 保留 fallback minSize — 极端布局下兜底 (跟 AppDelegate 4-key frame 持久化不冲突)
        let current = window.minSize
        if current.width < Self.fallbackMinSize.width || current.height < Self.fallbackMinSize.height {
            window.minSize = NSSize(
                width: max(current.width, Self.fallbackMinSize.width),
                height: max(current.height, Self.fallbackMinSize.height)
            )
        }
        // V6.73.1 hotfix: 延迟 1 个 runloop tick — 同步调 callback 会触发 SwiftUI BarAppearanceBridge
        //   在 hosting view 没完成 constraint pass 时 KVO observer race.
        //   延迟让 SwiftUI NSHostingView 完成 initial constraint setup 后再调 callback / setFrameAutosaveName
        DispatchQueue.main.async { [weak window] in
            guard let window = window else { return }
            // V6.74.2: callback 调 — 现在默认 no-op, 保留作 future hook (NSToolbar 删后无 caller)
            self.callback?(window)
            // 窗口位置/大小持久化 — macOS 原生 NSWindow frame autosave
            //   setFrameAutosaveName 自动保存/恢复窗口位置和大小到 UserDefaults
            window.setFrameAutosaveName("ImageGallery")
        }
    }
}
