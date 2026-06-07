//
//  SettingsView.swift
//  ImageGallery
//
//  V3.5.D：设置面板（sheet 形式）。
//  当前只包含"强调色"选择。后续可扩展：默认缩略图大小、默认视图模式、行为偏好等。
//
//  入口：菜单栏 ImageGallery > 设置...（⌘,）
//  由 ContentView 监听 .openSettingsRequested 通知后弹出 sheet。
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("accentColorID") private var accentColorID: String = AccentColor.system.rawValue
    // V3.6 NEW: 回收站保留时长（rawValue 用 @AppStorage 持久化）
    @AppStorage("trashRetentionDays") private var retentionDays: Int = TrashRetentionDays.defaultValue.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // 标题
            HStack {
                Text("设置")
                    .font(Typography.title)
                Spacer()
            }

            Divider().background(Surface.separator)

            // 强调色 section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("强调色")
                    .font(Typography.headline)

                Text("选择应用的主色调，影响按钮、选中状态、链接等。")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 5),
                    spacing: Spacing.md
                ) {
                    ForEach(AccentColor.allCases) { accent in
                        AccentSwatch(
                            accent: accent,
                            isSelected: accentColorID == accent.rawValue,
                            onTap: { accentColorID = accent.rawValue }
                        )
                    }
                }
            }

            // V3.6 NEW: 回收站 section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("回收站")
                    .font(Typography.headline)

                Text("删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)

                Picker("自动清理", selection: $retentionDays) {
                    ForEach(TrashRetentionDays.allCases) { days in
                        Text(days.displayName).tag(days.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()

            // 底部
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 480, height: 420)  // V3.6: 加高以容纳回收站 section
        .background(Surface.canvas)
    }
}

// MARK: - 强调色色板

struct AccentSwatch: View {
    let accent: AccentColor
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 32, height: 32)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Surface.textPrimary : Surface.cardBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                }

                Text(accent.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(accent.displayName)
    }
}

#Preview {
    SettingsView()
}
