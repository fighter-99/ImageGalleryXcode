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
//  V4.9.0: 加 secondaryAction 支持双 CTA
//  - primaryAction: 主操作（borderedProminent + 大尺寸）
//  - secondaryAction: 次要操作（bordered + 中尺寸）
//  - 区分"空状态"（icon + 引导文案）vs "错误状态"（exclamationmark.triangle + 重试）
//
//  用法：
//  ```
//  EmptyStateView(
//      icon: "photo.on.rectangle.angled",
//      title: "还没有图片",
//      subtitle: "拖入图片，或点击下方按钮开始添加",
//      primaryAction: EmptyStateView.Action(
//          label: "导入图片",
//          systemImage: "square.and.arrow.down",
//          onTap: onImport
//      ),
//      secondaryAction: EmptyStateView.Action(
//          label: "了解更多",
//          onTap: showHelp
//      )
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
    /// V4.9.0: 重命名 action → primaryAction（更清晰区分主/次 CTA）
    var primaryAction: Action? = nil
    /// V4.9.0 NEW: 次要 CTA——bordered + 中尺寸（不抢主 CTA 视觉）
    var secondaryAction: Action? = nil

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

            // CTA 按钮区（主 + 次）
            if primaryAction != nil || secondaryAction != nil {
                VStack(spacing: Spacing.sm) {
                    if let primaryAction {
                        Button(action: primaryAction.onTap) {
                            if let systemImage = primaryAction.systemImage {
                                Label(primaryAction.label, systemImage: systemImage)
                            } else {
                                Text(primaryAction.label)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .buttonStyle(.pressable)
                    }
                    if let secondaryAction {
                        Button(action: secondaryAction.onTap) {
                            if let systemImage = secondaryAction.systemImage {
                                Label(secondaryAction.label, systemImage: systemImage)
                            } else {
                                Text(secondaryAction.label)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
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

#Preview("带主 CTA") {
    EmptyStateView(
        icon: "photo.on.rectangle.angled",
        title: "还没有图片",
        subtitle: "拖入图片，或点击下方按钮开始添加",
        primaryAction: EmptyStateView.Action(
            label: "导入图片",
            systemImage: "square.and.arrow.down"
        ) {}
    )
    .frame(width: 600, height: 400)
}

#Preview("带主+次 CTA") {
    EmptyStateView(
        icon: "magnifyingglass",
        title: "没有匹配的照片",
        subtitle: "试试其他关键词，或清除搜索",
        primaryAction: EmptyStateView.Action(
            label: "清除搜索",
            systemImage: "xmark.circle"
        ) {},
        secondaryAction: EmptyStateView.Action(
            label: "查看全部"
        ) {}
    )
    .frame(width: 600, height: 400)
}
