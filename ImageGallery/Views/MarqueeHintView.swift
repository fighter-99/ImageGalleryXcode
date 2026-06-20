//
//  MarqueeHintView.swift
//  ImageGallery
//
//  V6.21.0 (Phase 1.1 UX polish): 圈选功能发现性提示
//   - 圈选 (marquee select) 是 Photos.app 核心交互, 但用户不知道有
//   - 首次启动 + 库有内容 + selection 空 → 在 grid 中心显示 floating tip
//   - 用户点 "知道了" 或首次 drag 后, hasShownMarqueeHint = true 永久隐藏
//   - 跟 macOS Photos "Drag to select" first-run 提示同模式
//

import SwiftUI

struct MarqueeHintView: View {
    /// V6.21.0: dismiss 闭包 — 用户点 "知道了" 或拖动时触发
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tint)
            Text(Copy.onboardingMarqueeTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(Copy.marqueeHintSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(action: onDismiss) {
                Text(Copy.marqueeHintDismiss)
                    .font(.callout.weight(.medium))
                    .frame(minWidth: 80)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 280)
        // V6.16.1: 暗色模式 — 半透明 + 模糊背景, 视觉分层
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }
}

#Preview {
    MarqueeHintView(onDismiss: {})
        .padding(40)
        .frame(width: 600, height: 400)
}