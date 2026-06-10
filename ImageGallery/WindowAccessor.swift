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

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? WindowAccessorView {
            view.callback = callback
        }
    }
}

/// 自定义 NSView，重写 viewDidMoveToWindow 在 window 设置时回调
private final class WindowAccessorView: NSView {
    var callback: ((NSWindow) -> Void)?
    private var hasConfigured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasConfigured, let window = self.window else { return }
        hasConfigured = true
        callback?(window)
    }
}
