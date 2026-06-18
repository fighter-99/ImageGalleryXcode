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

import SwiftUI

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

    @Environment(\.colorScheme) private var colorScheme
    // V6.21.4 (audit fix #1): @State progress — duration 内 1.0 → 0.0 真动画
    //   之前 V6.21.1 ProgressView(value: 1) hardcode static, bar 永远 100% 不动
    @State private var progress: Double = 1

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.callout)
                    .foregroundStyle(type.tint)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                // V6.21.1: close button — 用户主动 dismiss (不等 auto)
                //   .buttonStyle(.plain) 避免 macOS 自动应用 bordered 样式
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            // V6.21.4 (audit fix #1): 真正 progress 动画 — duration 内从 1.0 → 0.0
            //   @State progress + .task(id: duration) — view 出现时启动 task, 50ms 间隔更新
            //   toast 主动 dismiss (close button) → task 自动 cancel (isCancelled)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(type.tint)
                .scaleEffect(x: 1, y: 0.5, anchor: .leading)
                .opacity(0.6)
                .frame(height: 2)
                .padding(.horizontal, 4)
                .animation(.linear(duration: 0.05), value: progress)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(type.tint.opacity(0.3), lineWidth: 0.5)
        )
        // V6.16.1: 暗色模式阴影加强
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.55 : 0.15),
            radius: colorScheme == .dark ? 14 : 10,
            y: 4
        )
        // V6.21.4 (audit fix #1): progress countdown task — duration 秒内 progress 1 → 0
        //   task(id: duration) view 出现时启动, 消失时自动 cancel (toast 主动 dismiss / 队列下一 toast)
        //   50ms tick 平衡精度 + CPU (避免 16ms 触发过度)
        .task(id: duration) {
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                progress = max(0, 1 - elapsed / duration)
                if progress <= 0 { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ToastView(message: "已导入 12 张图片", type: .success, duration: 2.5, onDismiss: {})
        ToastView(message: "复制失败：磁盘空间不足", type: .error, duration: 5.0, onDismiss: {})
        ToastView(message: "已切换到「旅行」文件夹", type: .info, duration: 2.5, onDismiss: {})
        ToastView(message: "复制 0 张图片 — selection 为空", type: .warning, duration: 2.5, onDismiss: {})
    }
    .padding()
    .frame(width: 400)
}