//
//  MultiSelectDetailView.swift
//  ImageGallery
//
//  多选时的详情面板占位视图。
//  V3.5.x：从 ContentView.swift 末尾拆出（V3.5.D 补漏）。
//  提示用户多选快捷键、批量删除方式。
//

import SwiftUI

struct MultiSelectDetailView: View {
    let count: Int

    @Environment(\.appAccent) private var appAccent: Color

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(Typography.emptyStateIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(appAccent)

            Text("已选 \(count) 张图片")
                .font(Typography.title2)
                .foregroundStyle(Surface.textPrimary)

            VStack(spacing: Spacing.xs) {
                Text("使用 Delete 键批量删除")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
                Text("使用 ⌘+点击 加选/取消选")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textTertiary)
                Text("使用 ⌥+拖动 框选")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}

#Preview {
    MultiSelectDetailView(count: 12)
        .frame(width: 320, height: 480)
}
