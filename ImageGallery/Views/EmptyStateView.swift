//
//  EmptyStateView.swift
//  ImageGallery
//
//  V3.6.9 NEW: 统一空状态组件。
//  之前 3 处各自实现（PhotoGridView.emptyState / EmptyDetailView / TrashDetailView 等），
//  集中后：
//  - 统一间距 / 字号 / 颜色 token
//  - 可选 CTA 按钮（PhotoGridView 的"导入图片" 按钮）
//  - 统一 iconColor（accent / secondary / destructive）
//
//  用法：
//  ```
//  EmptyStateView(
//      icon: "photo.on.rectangle.angled",
//      title: "还没有图片",
//      subtitle: "拖入图片，或点击下方按钮开始添加",
//      action: EmptyStateView.Action(label: "导入图片", systemImage: "square.and.arrow.down") {
//          onImport()
//      }
//  )
//  ```
//

import SwiftUI

struct EmptyStateView: View {
    /// 可选的 CTA 动作（按钮）
    struct Action {
        let label: String
        var systemImage: String? = nil
        let onTap: () -> Void
    }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = .accentColor
    var action: Action? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // 大图标（hierarchical rendering 自动适配暗色）
            Image(systemName: icon)
                .font(Typography.emptyStateIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            // 标题 + 副标题
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.title2)
                    .foregroundStyle(Surface.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.body)
                        .foregroundStyle(Surface.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            // 可选 CTA 按钮
            if let action {
                Button(action: action.onTap) {
                    if let systemImage = action.systemImage {
                        Label(action.label, systemImage: systemImage)
                    } else {
                        Text(action.label)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }
}

#Preview("简单空状态") {
    EmptyStateView(
        icon: "photo",
        title: "选择一张图片",
        subtitle: "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选"
    )
    .frame(width: 320, height: 480)
}

#Preview("带 CTA") {
    EmptyStateView(
        icon: "photo.on.rectangle.angled",
        title: "还没有图片",
        subtitle: "拖入图片，或点击下方按钮开始添加",
        action: EmptyStateView.Action(
            label: "导入图片",
            systemImage: "square.and.arrow.down"
        ) {}
    )
    .frame(width: 600, height: 400)
}
