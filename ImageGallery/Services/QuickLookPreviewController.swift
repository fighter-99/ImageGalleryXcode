//
//  QuickLookPreviewController.swift
//  ImageGallery
//
//  V4.12.0: 空格键 QuickLook——macOS Photos/Finder 标准
//  SwiftUI 没有 .quickLookPreview modifier——必须走 AppKit QLPreviewPanel
//  + QLPreviewPanelDataSource 协议
//
//  架构：
//  - QuickLookPreviewController: NSObject + QLPreviewPanelDataSource
//    持有 urls + currentIndex，调 show() 时让 QLPreviewPanel.makeKeyAndOrderFront
//  - QLPreviewHostingView: NSView 子类
//    重写 acceptsPreviewPanelControl/beginPreviewPanelControl
//    把 panel.dataSource 指向 controller
//  - QuickLookBridge: NSViewRepresentable
//    在 ContentView .background 注入，SwiftUI 不显示但参与 firstResponder 链
//
//  流程：
//  1. 空格键 → gridInputHandling onSpace → controller.show(urls:, currentIndex:)
//  2. controller 调 QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
//  3. 系统沿 firstResponder 链找 acceptsPreviewPanelControl(_:) == true 的 view
//  4. QLPreviewHostingView 接走 + 设 panel.dataSource = self
//  5. QLPreviewPanel 显示当前 URL（NSImageView / QLPreviewView 渲染）
//  6. 按 ←→ 在 panel 内翻页（QLPreviewPanel 自动处理）
//

import AppKit
import QuickLookUI
import SwiftUI

@MainActor
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource {
    /// 当前 QuickLook 显示的 URL 列表（来自 visiblePhotos.fileURL）
    private var urls: [URL] = []
    /// 当前选中照片在 urls 数组中的索引（panel 起始位置）
    private var currentIndex: Int = 0

    /// 触发 QuickLook 悬浮预览
    /// - Parameters:
    ///   - urls: 完整预览 URL 列表（按 ←→ 翻页）
    ///   - currentIndex: 起始索引
    func show(urls: [URL], currentIndex: Int) {
        guard !urls.isEmpty, currentIndex < urls.count else { return }
        self.urls = urls
        self.currentIndex = currentIndex
        // V4.12.0: sharedPreviewPanel() 触发系统沿 firstResponder 链找接管 view
        //   QLPreviewHostingView.acceptsPreviewPanelControl(_:) → true 时接管
        //   然后 beginPreviewPanelControl 把 dataSource 设为 self
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            guard index >= 0, index < urls.count else { return nil }
            // NSURL 默认实现 QLPreviewItem 协议——直接返回
            return urls[index] as NSURL
        }
    }
}

// MARK: - QLPreviewHostingView

/// V4.12.0: NSView 子类，重写 QLPreviewPanel 接管方法
/// SwiftUI view 不响应 QLPreviewPanel，必须包一个 NSView 参与 firstResponder 链
final class QLPreviewHostingView: NSView {
    /// controller 引用（weak 避免循环）
    weak var controller: QuickLookPreviewController?

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        // 只有 controller 存在时接管（避免空状态时误接管）
        controller != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // V4.12.0: 系统调此方法时，把 panel.dataSource 指向 controller
        //   之后 panel 通过 dataSource 协议方法（numberOfPreviewItems / previewItemAt）取 URL
        panel.dataSource = controller
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // V4.12.0: panel 关闭时清空 dataSource 引用（避免循环）
        //   panel 关闭不会自动断，weak controller 不足以打破——必须显式 nil
        //   但 controller 是 weak，dataSource 是 strong/weak 由 panel 决定
        //   简单方案：保留 controller 引用，panel 关闭后由系统释放
    }
}

// MARK: - QuickLookBridge

/// V4.12.0: NSViewRepresentable 桥接——把 QLPreviewHostingView 注入 SwiftUI view tree
/// 用 .background 挂载：SwiftUI 不显示（透明 NSView）但参与 firstResponder 链
struct QuickLookBridge: NSViewRepresentable {
    let controller: QuickLookPreviewController

    func makeNSView(context: Context) -> NSView {
        let view = QLPreviewHostingView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // controller 是 @StateObject 单例，update 时只需更新引用
        (nsView as? QLPreviewHostingView)?.controller = controller
    }
}
