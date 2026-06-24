//
//  EmptyStateView.swift
//  ImageGallery
//
//  V3.6.9 NEW: 统一空状态组件。
//  V4.9.0: 加 secondaryAction 支持双 CTA
//  V6.61: 视觉重做——圆形软色背景 + Photos.app 风格 icon 居中
//    - 新增 Style 枚举 (accent / neutral / warning / destructive)
//    - 取代 iconColor 参数 (style 自动派生 icon + backdrop 颜色)
//    - CTA 横向排列 (主右 / 次左), 符合 macOS 按钮惯例
//    - 标题改 .title2.semibold, 副标题限最大宽度 360pt 防止大窗口下拉伸
//
//  用法：
//  ```
//  EmptyStateView(
//      icon: "photo.on.rectangle.angled",
//      title: "还没有图片",
//      subtitle: "拖入图片，或点击下方按钮开始添加",
//      style: .accent,
//      primaryAction: EmptyStateView.Action(
//          label: "导入图片",
//          systemImage: IconNames.squareAndArrowDown,
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
    @State private var appeared = false
    /// V6.61 NEW: 视觉样式——派生 backdrop 圆形填充色 + icon tint
    ///   取代之前的 iconColor 单独参数,让"视觉意图"统一管控
    enum Style {
        /// 引导类: 导入、查看 (蓝色圆形 + 蓝色 icon)
        case accent
        /// 预期空: 空文件夹/标签/回收站 (浅灰圆形 + 灰 icon)
        case neutral
        /// 警告: 临时性提示 (橙色圆形 + 橙色 icon)
        case warning
        /// 错误: 存储不可用等 (红色圆形 + 红色 icon)
        case destructive
    }

    /// 可选的 CTA 动作（按钮）
    struct Action {
        let label: String
        var systemImage: String? = nil
        let onTap: () -> Void
    }

    let icon: String
    let title: String
    var subtitle: String? = nil
    /// V6.61: 用 style 取代 iconColor,集中管控"意图 → 颜色"映射
    var style: Style = .accent
    /// 主操作（borderedProminent + 大尺寸）
    var primaryAction: Action? = nil
    /// 次要操作（bordered + 中尺寸）
    var secondaryAction: Action? = nil
    /// 是否使用原生 ContentUnavailableView 风格（macOS 15+）
    var useNativeStyle: Bool = false

    @ViewBuilder
    var body: some View {
        if useNativeStyle {
            nativeBody
        } else {
            customBody
        }
    }

    // MARK: - macOS 原生风格 (ContentUnavailableView)
    
    private var nativeBody: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .foregroundStyle(Surface.textPrimary)
        } description: {
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Surface.textSecondary)
            }
        } actions: {
            actionButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customBody: some View {
        VStack(spacing: Spacing.xxl) {
            // V6.97 P3-3: 装饰 icon 标 hidden — VoiceOver 跳过 120pt 圆形 backdrop + SF Symbol
            //   真实意图 (标题/subtitle/CTA) 在下面 .accessibilityElement(.combine) 整体读出
            backdropIcon
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Surface.textPrimary)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Surface.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 360)
            // V6.97 P3-3: title + subtitle 合并成一组 — VoiceOver 连续读
            //   .isHeader 标记让用户能"跳到下个标题"快捷键 (VO+Cmd+H) 定位
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(subtitle.map { "\(title)。\($0)" } ?? title)

            if primaryAction != nil || secondaryAction != nil {
                // V6.61: CTA 横向——次左 / 主右,符合 macOS 按钮次序惯例
                HStack(spacing: Spacing.sm) {
                    if let secondaryAction {
                        Button(action: secondaryAction.onTap) {
                            actionLabel(secondaryAction)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        // V6.97 P3-3: 次要 CTA 显式 .accessibilityHint — 让 VoiceOver 用户知道结果
                        .accessibilityHint(Copy.accessibilityActionHintSecondary)
                    }
                    if let primaryAction {
                        Button(action: primaryAction.onTap) {
                            actionLabel(primaryAction)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        // V6.97 P3-3: 主要 CTA 显式 .accessibilityHint
                        .accessibilityHint(Copy.accessibilityActionHintPrimary)
                    }
                }
            }
        }
        .padding(Spacing.xxl)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(Animations.standard) { appeared = true } }
    }

    // MARK: - 视觉子组件

    /// V6.61 NEW: 圆形软色背景 + 居中 icon——Photos.app 风格空状态视觉锤
    ///   120pt 圆形 + 56pt hierarchical icon — 取代之前"裸 icon 浮在中间"
    ///   圆形 fill 由 style 派生 (accent 12% / neutral 6% / warning 12% / destructive 12%)
    private var backdropIcon: some View {
        ZStack {
            Circle()
                .fill(backdropFill)
                .frame(width: 120, height: 120)
            Image(systemName: icon)
                .font(Typography.heroBackdropIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func actionLabel(_ action: Action) -> some View {
        if let systemImage = action.systemImage {
            Label(action.label, systemImage: systemImage)
        } else {
            Text(action.label)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if primaryAction != nil || secondaryAction != nil {
            HStack(spacing: Spacing.sm) {
                if let secondaryAction {
                    Button(action: secondaryAction.onTap) {
                        actionLabel(secondaryAction)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                if let primaryAction {
                    Button(action: primaryAction.onTap) {
                        actionLabel(primaryAction)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - 样式解析

    private var backdropFill: Color {
        switch style {
        case .accent:       return Color.accentColor.opacity(0.12)
        case .neutral:      return Color.primary.opacity(0.06)
        case .warning:      return Color.orange.opacity(0.12)
        case .destructive:  return Color.red.opacity(0.12)
        }
    }

    private var iconTint: Color {
        switch style {
        case .accent:       return .accentColor
        case .neutral:      return Surface.textSecondary
        case .warning:      return Color.orange
        case .destructive:  return .red
        }
    }
}

#Preview("简单空状态") {
    EmptyStateView(
        icon: "photo",
        title: "选择一张图片",
        subtitle: "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选"
    )
    .frame(width: SheetMetrics.compactWidth, height: SheetMetrics.compactHeight)
}

#Preview("带主 CTA") {
    EmptyStateView(
        icon: "photo.on.rectangle.angled",
        title: "还没有图片",
        subtitle: "拖入图片，或点击下方按钮开始添加",
        primaryAction: EmptyStateView.Action(
            label: "导入图片",
            systemImage: IconNames.squareAndArrowDown
        ) {}
    )
    .frame(width: SheetMetrics.standardWidth, height: SheetMetrics.standardHeight)
}

#Preview("带主+次 CTA") {
    EmptyStateView(
        icon: "magnifyingglass",
        title: "没有匹配的照片",
        subtitle: "试试其他关键词，或清除搜索",
        primaryAction: EmptyStateView.Action(
            label: "清除搜索",
            systemImage: IconNames.xmarkCircle
        ) {},
        secondaryAction: EmptyStateView.Action(
            label: Copy.viewAll
        ) {}
    )
    .frame(width: SheetMetrics.standardWidth, height: SheetMetrics.standardHeight)
}

#Preview("中性 (空回收站)") {
    EmptyStateView(
        icon: "trash",
        title: "回收站是空的",
        subtitle: "删除的图片会在 30 天后自动清除",
        style: .neutral,
        primaryAction: EmptyStateView.Action(
            label: "查看全部",
            systemImage: "photo.on.rectangle.angled"
        ) {}
    )
    .frame(width: SheetMetrics.standardWidth, height: SheetMetrics.standardHeight)
}

#Preview("错误 (存储不可用)") {
    EmptyStateView(
        icon: "exclamationmark.triangle",
        title: "无法访问存储",
        subtitle: "请检查磁盘权限或重新连接",
        style: .destructive,
        primaryAction: EmptyStateView.Action(
            label: "重试",
            systemImage: "arrow.clockwise"
        ) {}
    )
    .frame(width: SheetMetrics.standardWidth, height: SheetMetrics.standardHeight)
}
