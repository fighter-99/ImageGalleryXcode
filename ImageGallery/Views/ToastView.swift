//
//  ToastView.swift
//  ImageGallery
//
//  轻量级提示条。底部弹出，自动消失。
//
//  V6.21.1 (Phase 1.2 UX polish):
//  - 加 .warning 类型 (橙色, 用于"复制 0 张图片"等需注意但非错误场景)
//  - 加 close button (用户主动 dismiss, 不等 duration)
//  - 加底部 progress indicator (duration 内 100% → 0%, 让用户知道 toast 几时消失)
//  - 顶部 padding 从 80pt → 8pt (紧贴 status bar 上方, Photos 范式)
//
//  V6.29.1 (IA — Undo ⌘Z toast):
//  - 加 undoAction 闭包支持 — 破坏性操作后 toast 显示 [撤销] 按钮 (Photos.app 范式)
//  - 点 [撤销] 触发 undo + auto-dismiss toast
//  - 跟 ImageGalleryUndoManager.registerUndoOnly() 联动 (⌘Z 也能撤销同一操作)
//

import SwiftUI
import AppKit  // V6.64.1 (A11y): NSAccessibility.post announcement — VoiceOver 朗读 toast

struct ToastView: View {
    enum ToastType {
        case info
        case success
        case error
        case warning   // V6.21.1: 橙色 (例: "复制 0 张图片" / "导出文件已存在")

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .accentColor
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            }
        }
    }

    let message: String
    let type: ToastType
    /// V6.21.4: duration 参数 — progress bar countdown 用 (之前 V6.21.1 hardcode 1 不动)
    let duration: TimeInterval
    /// V6.21.1: close button 闭包 — caller (MainLayoutView) 调 enqueueToast 的反向操作, 把 toastQueue.removeFirst()
    let onDismiss: () -> Void
    /// V6.29.1: undo action 闭包 — nil 时不显示 [撤销] 按钮
    ///   触发时: 调 undo + onDismiss (auto close toast)
    let undoAction: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    // V6.96 P0 #4: 进度条真实现 — duration 内 1.0 → 0.0
    //   之前 V6.21.1 注释承诺, V6.21.4 audit 改注释但 body 里没真 ProgressView
    //   toast 进入瞬间 1.0, 持续 duration 秒后 0.0——告诉用户几时消失
    @State private var progress: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.callout)
                .foregroundStyle(type.tint)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let undoAction {
                Button {
                    undoAction()
                    onDismiss()
                } label: {
                    Text(Copy.undo)
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(Copy.toastUndoHelp)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        // V6.96 P0 #4: 底部 2pt 进度条 — 跟整体圆角一致, 用 type.tint 颜色
        //   配合下面 .task(id: duration) 在 duration 秒内从 1.0 动画到 0.0
        //   duration == 0 (永久 toast) 时隐藏
        .overlay(alignment: .bottom) {
            if duration > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(type.tint)
                        .frame(width: geo.size.width * progress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.15),
            radius: colorScheme == .dark ? 14 : 8,
            y: colorScheme == .dark ? 4 : 3
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
        .accessibilityAddTraits(undoAction != nil ? .updatesFrequently : [])
        .onAppear {
            NSAccessibility.post(
                element: NSApp.mainWindow as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: message,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue
                ]
            )
        }
        .task(id: duration) {
            guard duration > 0 else { return }
            // V6.96 P0 #4: 进度条动画 — progress 从 1.0 在 duration 秒内线性到 0.0
            //   用 Timer.publish 每 0.05s 推进一帧, 比 SwiftUI withAnimation 更可控
            progress = 1.0
            let totalSteps = 20
            let stepInterval = duration / Double(totalSteps)
            for step in 0..<totalSteps {
                try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
                if Task.isCancelled { return }
                let pct = 1.0 - Double(step + 1) / Double(totalSteps)
                withAnimation(.linear(duration: stepInterval)) {
                    progress = pct
                }
            }
        }
    }  // closes var body

}
#Preview {
    VStack(spacing: 12) {
        ToastView(message: "已导入 12 张图片", type: .success, duration: 2.5, onDismiss: {}, undoAction: nil)
        // V6.29.1 preview: undo toast
        ToastView(message: "已移到回收站 5 张", type: .info, duration: 5, onDismiss: {}, undoAction: { print("undo") })
        ToastView(message: "复制失败：磁盘空间不足", type: .error, duration: 5.0, onDismiss: {}, undoAction: nil)
        ToastView(message: "已切换到「旅行」文件夹", type: .info, duration: 2.5, onDismiss: {}, undoAction: nil)
        ToastView(message: "复制 0 张图片 — selection 为空", type: .warning, duration: 2.5, onDismiss: {}, undoAction: nil)
    }
    .padding()
    .frame(width: 400)
}
