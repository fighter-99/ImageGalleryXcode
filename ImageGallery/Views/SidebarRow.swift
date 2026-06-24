//
//  SidebarRow.swift
//  ImageGallery
//
//  V3.5.8 侧栏精修：自定义 row 组件。
//  Photos.app + Finder 混合风格：hover 浅背景 + 选中 accent 圆角。
//
//  V4.1.0 B: 选中态加粗（视觉锤）
//  V4.6.0: token 化 + 行高统一 28pt + label 字号 13pt
//    - 之前 .callout (16pt) 太大，sidebar 显得拥挤
//    - 显式 .frame(height: 28) 替代隐式 padding 算高
//    - 所有视觉常量改用 SidebarStyle.* token
//    - 选中背景从 0.10 → 0.12（Surface.selected 同步升级）
//
//  设计原则（V4.4.5 浅框教训）：
//  - 无 resting shadow / hover shadow——纯 background 颜色变化区分状态
//  - 背景 inset 4pt 让"胶囊"不贴侧栏边缘（macOS 标准）
//

import SwiftUI

/// 侧栏 item row
/// - 默认：无背景，secondary 色图标 + primary 色 85% 文字
/// - hover：SidebarStyle.hoverBackground 浅背景 + 100% 文字
/// - 选中：SidebarStyle.activeBackground 圆角背景（0.12 accent）+ accent 色加粗文字
struct SidebarRow: View {
    let icon: String
    let iconColor: Color?
    let label: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    // V6.32.1: 暗色模式感知 — selected/selectedStrong opacity 在 light/dark 不同
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarStyle.rowIconTextSpacing) {
                // 图标——V4.6.0 用 token 化字号/字重/框架宽度
                Image(systemName: icon)
                    .font(Typography.sidebarIcon)
                    .foregroundStyle(currentIconColor)
                    .frame(width: SidebarStyle.iconFrameWidth)

                // 文字——V4.6.0 label 字号 16pt callout → 13pt system
                Text(label)
                    .font(isSelected ? SidebarStyle.labelSelectedFont : SidebarStyle.labelFont)
                    .foregroundStyle(currentLabelColor)
                    .lineLimit(1)

                Spacer(minLength: SidebarStyle.rowTextCountSpacing)

                // 计数——V4.6.0 用 SidebarStyle.countFont token
                // V6.32.1: 暗色下 opacity 从 0.7 → 0.85 (.secondary 在暗色下更暗, 0.7 太弱看不清)
                // V6.95 B: count == 0 时不显示 (避免视觉噪音, 跟 Photos 真版一致)
                // V6.95 D: count.formatted(.number) 千分位 (1234 → "1,234", 大库易读)
                if let count = count, count > 0 {
                    Text(count.formatted(.number))
                        .font(SidebarStyle.countFont)
                        .foregroundStyle(currentCountColor)
                }
            }
            // V4.6.0: 显式 .frame(height: 28) 统一行高
            .frame(height: SidebarStyle.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SidebarStyle.rowHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: SidebarStyle.rowCornerRadius)
                    .fill(backgroundColor)
                    // 让背景不到边缘 4pt——macOS 标准"胶囊"风格
                    .padding(.horizontal, SidebarStyle.rowBackgroundInset)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        // V3.6.41: 升级 hover/选中 动画到 spring（统一 cell 动画风格）
        .animation(Animations.standard, value: isHovered)
        .animation(Animations.standard, value: isSelected)
        // V6.69 (Wave 2 收尾): hover lift 1.02 + Elevation.subtle → standard
        //   之前 SidebarRow 只换背景, 没 scale — 跟 PhotoThumbnailView hover (V6.65) 不一致
        //   现在 hover: 1.02 微 scale + Animations.standard (跟 isHovered 同一动画曲线)
        //   Photos.app Sonoma+ 实测 sidebar row hover 微 scale 视觉锤
        //   reduce motion 时 scale 跳值无动画 (Animations.standard 自动检查)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        // V6.96 P0 #3: 删重复 .animation——上面 L82 已经有 .animation(Animations.standard, value: isHovered),
        //   之前 scaleEffect 后又挂一遍, SwiftUI 内部跑两遍比较, 浪费 type-checker
        //   现在 scale 跟随 isHovered 变化由上面那个统一处理
        // V6.22.2 (P2 #8): VoiceOver 标签 — 之前 0 标签, 盲人用户不能用
        //   - label: sidebar item 名称 + count ("图库 50 张")
        //   - hint: "显示所有照片" / "筛选重复图" 等 role 描述
        //   - value (选中): "已选中" / "未选中" 让用户感知状态
        .accessibilityLabel(count.map { Copy.sidebarCount($0) } ?? label)
        .accessibilityHint(accessibilityHint)
        .accessibilityValue(isSelected ? Copy.accessibilitySelected : Copy.accessibilityUnselected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 背景色：选中 > hover > 默认
    /// macOS 标准 sidebar 选中态——NSColor.alternateSelectedControlBackgroundColor 系统实色
    private var backgroundColor: Color {
        if isSelected { return SidebarStyle.activeBackground(for: colorScheme) }
        if isHovered { return SidebarStyle.hoverBackground }
        return .clear
    }

    /// 计数 text 颜色：选中 → accent (跟 macOS Sonoma+ 真版一致), 默认 → secondary.opacity
    /// V6.96: 选中色改 .accentColor — 之前 .white 适配旧灰色 activeBackground
    ///   现在 activeBackground 改 accentColor.opacity(0.15), label/icon 都用 .accentColor, count 同步
    private var currentCountColor: Color {
        if isSelected { return SidebarStyle.labelActive }
        return colorScheme == .dark ? Color.secondary.opacity(0.85) : Color.secondary.opacity(0.7)
    }

    /// label 颜色：选中 > hover > 默认——选中时用 white（系统标准）
    private var currentLabelColor: Color {
        if isSelected { return SidebarStyle.labelActive }
        if isHovered { return SidebarStyle.labelHover }
        return SidebarStyle.labelDefault
    }

    /// icon 颜色：显式 iconColor（tag/智能 folder） > 选中/hover 用 white > secondary
    private var currentIconColor: Color {
        if let iconColor { return iconColor }
        if isSelected { return SidebarStyle.iconActive }
        if isHovered { return SidebarStyle.iconActive }
        return SidebarStyle.iconDefault
    }

    /// V6.22.2 (P2 #8): VoiceOver hint — 描述 sidebar item 角色 (display all / filter / etc.)
    ///   简单 fallback: "显示 sidebar item" + icon name 让盲人用户理解操作
    ///   V6.37.4: 走 Copy.sidebarRowShowLabel(name:) — printf %@ 而非 Swift 插值
    private var accessibilityHint: String {
        Copy.sidebarRowShowLabel(label)
    }
}
