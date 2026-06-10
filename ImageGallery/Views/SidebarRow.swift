//
//  SidebarRow.swift
//  ImageGallery
//
//  V3.5.8 侧栏精修：自定义 row 组件。
//  Photos.app + Finder 混合风格：hover 浅背景 + 选中 accent 圆角。
//

import SwiftUI

/// 侧栏 item row
/// - 默认：无背景，secondary 色图标 + primary 色文字
/// - hover：Surface.hover 浅背景
/// - 选中：Surface.selected 圆角背景 + accent 色文字
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
            HStack(spacing: 8) {
                // 图标：V3.6.41 选中/hover 时亮度提升（secondary → primary）
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor ?? (isSelected || isHovered ? Color.accentColor : Color.secondary))
                    .frame(width: 18)

                // 文字
                Text(label)
                    // V4.1.0 B: 选中态加粗（Photos.app 风格）——视觉锤
                    .font(isSelected ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? Color.primary : Color.primary.opacity(0.85)))
                    .lineLimit(1)

                Spacer(minLength: 4)

                // 计数：V3.6.41 选中时提升到 secondary 色（更醒目）
                if let count = count {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(backgroundColor)
                    .padding(.horizontal, 4)  // 让背景不到边缘，macOS 标准风格
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        // V3.6.41: 升级 hover/选中 动画到 springGentle（统一 cell 动画风格）
        .animation(Animations.springGentle, value: isHovered)
        .animation(Animations.springGentle, value: isSelected)
    }

    /// 背景色：选中 > hover > 默认
    private var backgroundColor: Color {
        if isSelected { return Surface.selected }
        if isHovered { return Surface.hover }
        return .clear
    }
}
