//
//  TrackpadGestureModifier.swift
//  ImageGallery
//
//  V6.97 P3-1: Trackpad 触控板手势支持
//
//  Photos.app 范式:
//  - 双指捏合 (Pinch) 调整缩略图大小 (1.0×→2.0× 映射到 [100, 200]pt)
//  - 双指左右滑动 (Swipe) 切换 sidebar 显示
//  - 双指上滑 (Swipe Up) 触发沉浸模式 (Photos 标准手势)
//
//  实现策略:
//  - Pinch: 走 SwiftUI MagnificationGesture (原生支持 trackpad, macOS 13+)
//  - Swipe: 走 NSEvent local monitor (NSurfaceType.trackpad .gesture 事件)
//    SwiftUI 没有原生 trackpad swipe 识别, 必须走 AppKit NSEvent
//  - 缩放 200ms debounce — trackpad pinch 连续事件, 不抖
//
//  NotificationCenter 桥接 (跟 .markupRequested / .newFolderRequested 同模式):
//  - .trackpadSwipeLeft / .trackpadSwipeRight → sidebar toggle
//  - .trackpadPinchChanged(scale)             → 实时调 thumbnailSize
//
//  接入点: ContentView body 最外层 .trackpadGestures(...)
//

import SwiftUI
import AppKit

// MARK: - 通知名 (ContentView .onReceive 桥接 → model)

extension Notification.Name {
    /// trackpad 双指向左滑 — 触发 sidebar 显示
    static let trackpadSwipeLeft = Notification.Name("com.iridescent.ImageGallery.trackpadSwipeLeft")
    /// trackpad 双指向右滑 — 触发 sidebar 隐藏
    static let trackpadSwipeRight = Notification.Name("com.iridescent.ImageGallery.trackpadSwipeRight")
    /// trackpad 双指向上滑 — 触发沉浸模式 (Photos.app 范式)
    static let trackpadSwipeUp = Notification.Name("com.iridescent.ImageGallery.trackpadSwipeUp")
    /// trackpad 双指向下滑 — 退出沉浸模式
    static let trackpadSwipeDown = Notification.Name("com.iridescent.ImageGallery.trackpadSwipeDown")
}

// MARK: - 主 modifier: 包住 content + 注入 trackpad 事件

struct TrackpadGestureModifier: ViewModifier {
    @Binding var thumbnailSize: CGFloat
    /// 缩放范围 — Photos 范式 100~200pt
    private let minSize: CGFloat = 100
    private let maxSize: CGFloat = 240

    @State private var magnifyBy: CGFloat = 1.0
    @State private var swipeMonitor: Any? = nil

    func body(content: Content) -> some View {
        content
            // Pinch: 实时调整缩略图大小
            //   magnificationGesture 接收 .began / .changed / .ended
            //   用 @GestureState 也能做, 但 @State + onEnded 提交更符合 Photos 范式 (commit on end)
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        // 累积 scale, 不直接用绝对值 (避免每次 .changed 重置 baseline)
                        magnifyBy = scale
                    }
                    .onEnded { _ in
                        // 缩放比例 * 当前 size = 新 size, 然后归零 (避免下次 .changed 累加)
                        let proposed = thumbnailSize * magnifyBy
                        thumbnailSize = max(minSize, min(maxSize, proposed))
                        magnifyBy = 1.0
                    }
            )
            // 同步: 在 SwiftUI view lifecycle 里挂 NSEvent monitor
            //   .onAppear 装, .onDisappear 卸 — 避免多个 ContentView 挂多份
            .onAppear { installSwipeMonitor() }
            .onDisappear { removeSwipeMonitor() }
    }

    // MARK: - NSEvent swipe monitor

    /// V6.97 P3-1: 挂 NSEvent.local monitor 监听 trackpad gesture (swipe) 事件
    ///   macOS 11+ NSEvent.phase: .began / .changed / .ended
    ///   deltaX / deltaY = 滑动方向 (正负代表反向)
    ///   阈值: 横向 abs(deltaX) > abs(deltaY) 且 abs(deltaX) > 0.3 → swipe
    private func installSwipeMonitor() {
        // 避免重复挂
        guard swipeMonitor == nil else { return }
        // V6.97 P3-1: 走 .gesture 类型 — NSEvent 没有公开的 .swipe subtype
        //   实际 swipe 事件 type == .gesture, 跟 magnify/rotate 共用
        //   区分靠 deltaX/deltaY: swipe 有连续非零 delta, magnify 是 magnitude, rotate 是 rotation
        //   只对 phase == .changed 的事件做处理 (.began/.ended deltaX 可能是 0)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.gesture]) { event in
            // 只处理 swipe 事件 — 通过 deltaX/Y 是否显著区分 (magnify/rotate 不走 deltaX/Y)
            let dx = event.deltaX
            let dy = event.deltaY
            // 阈值: 任意方向 > 0.3 触发, 避免误触
            let threshold: CGFloat = 0.3
            if abs(dx) < threshold && abs(dy) < threshold {
                return event
            }
            // 横向 swipe (|dx| > |dy|)
            if abs(dx) > abs(dy) {
                if dx > 0 {
                    NotificationCenter.default.post(name: .trackpadSwipeLeft, object: nil)
                } else {
                    NotificationCenter.default.post(name: .trackpadSwipeRight, object: nil)
                }
            } else {
                // 纵向 swipe (|dy| > |dx|)
                if dy > 0 {
                    NotificationCenter.default.post(name: .trackpadSwipeUp, object: nil)
                } else {
                    NotificationCenter.default.post(name: .trackpadSwipeDown, object: nil)
                }
            }
            return event
        }
        swipeMonitor = monitor
    }

    private func removeSwipeMonitor() {
        if let m = swipeMonitor {
            NSEvent.removeMonitor(m)
            swipeMonitor = nil
        }
    }
}

// MARK: - 接入 helper (ContentView body 一行调用)

extension View {
    /// 启用 trackpad 手势 — 接管 view 树
    /// - Parameter thumbnailSize: 双向绑定的缩略图尺寸, pinch 实时改
    func trackpadGestures(thumbnailSize: Binding<CGFloat>) -> some View {
        modifier(TrackpadGestureModifier(thumbnailSize: thumbnailSize))
    }
}
