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

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarStyle.rowIconTextSpacing) {
                // 图标——V4.6.0 用 token 化字号/字重/框架宽度
                Image(systemName: icon)
                    .font(.system(size: SidebarStyle.iconSize, weight: SidebarStyle.iconWeight))
                    .foregroundStyle(currentIconColor)
                    .frame(width: SidebarStyle.iconFrameWidth)

                // 文字——V4.6.0 label 字号 16pt callout → 13pt system
                Text(label)
                    .font(isSelected ? SidebarStyle.labelSelectedFont : SidebarStyle.labelFont)
                    .foregroundStyle(currentLabelColor)
                    .lineLimit(1)

                Spacer(minLength: SidebarStyle.rowTextCountSpacing)

                // 计数——V4.6.0 用 SidebarStyle.countFont token
                if let count = count {
                    Text(Copy.sidebarCount(count))
                        .font(SidebarStyle.countFont)
                        .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.7))
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
        .animation(Animations.springGentle, value: isHovered)
        .animation(Animations.springGentle, value: isSelected)
    }

    /// 背景色：选中 > hover > 默认
    private var backgroundColor: Color {
        if isSelected { return SidebarStyle.activeBackground }
        if isHovered { return SidebarStyle.hoverBackground }
        return .clear
    }

    /// label 颜色：选中 > hover > 默认
    /// V4.6.0: 选中态用 labelActive（accent）而非 primary，加视觉锤
    private var currentLabelColor: Color {
        if isSelected { return SidebarStyle.labelActive }
        if isHovered { return SidebarStyle.labelHover }
        return SidebarStyle.labelDefault
    }

    /// icon 颜色：显式 iconColor（tag/智能 folder） > 选中/hover 用 accent > secondary
    /// V4.6.0: 与 label 颜色逻辑同步——视觉关联
    private var currentIconColor: Color {
        if let iconColor { return iconColor }
        if isSelected || isHovered { return SidebarStyle.iconActive }
        return SidebarStyle.iconDefault
    }
}
