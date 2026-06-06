//
//  EmptyDetailView.swift
//  ImageGallery
//
//  未选中图片时的详情面板占位视图。
//  V3.5.x：从 ContentView.swift 末尾拆出（V3.5.D 补漏）。
//  提示用户选择图片、可用快捷键。
//

import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "photo")
                .font(Typography.emptyStateIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Surface.textTertiary)

            Text("选择一张图片")
                .font(Typography.body)
                .foregroundStyle(Surface.textSecondary)

            Text("← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选")
                .font(Typography.caption)
                .foregroundStyle(Surface.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyDetailView()
        .frame(width: 320, height: 480)
}
