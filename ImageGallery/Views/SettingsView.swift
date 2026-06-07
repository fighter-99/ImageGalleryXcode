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
    // V3.6.13: 默认缩略图大小（同一 key 共享 ContentView 的 storedThumbnailSize）
    @AppStorage("thumbnailSize") private var defaultThumbnailSize: Double = 170
    // V3.6.13: 默认视图模式（PhotoGridView 用的 viewModeRaw key）
    @AppStorage("viewModeRaw") private var defaultViewModeRaw: String = ViewMode.grid.rawValue
    // V3.6.13: 默认排序
    @AppStorage("sortOption") private var defaultSortOption: String = SortOption.importedAtDesc.rawValue

    // V3.6.13: 用 let 显式类型避免 Swift 推断循环
    private let defaultViewModeOptions: [ViewMode] = ViewMode.allCases
    private let defaultSortOptions: [SortOption] = SortOption.allCases

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

            // V3.6.13 NEW: 缩略图 section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("缩略图")
                    .font(Typography.headline)

                Text("设置默认缩略图大小（拖动 slider 调整）。当前会话用 toolbar 临时改的会在重启后恢复默认值。")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)

                HStack {
                    Slider(value: $defaultThumbnailSize, in: 100...250, step: 10)
                    Text("\(Int(defaultThumbnailSize))")
                        .font(Typography.captionMono)
                        .foregroundStyle(Surface.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            // V3.6.13 NEW: 视图模式 section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("默认视图模式")
                    .font(Typography.headline)

                // V3.6.13: 不用 ForEach + enum，避免 Swift 推断循环
                Picker("视图模式", selection: $defaultViewModeRaw) {
                    Text("网格").tag(ViewMode.grid.rawValue)
                    Text("列表").tag(ViewMode.list.rawValue)
                    Text("时间线").tag(ViewMode.timeline.rawValue)
                }
                .pickerStyle(.segmented)
            }

            // V3.6.13 NEW: 默认排序 section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("默认排序")
                    .font(Typography.headline)

                Picker("排序", selection: $defaultSortOption) {
                    Text("导入时间 ↓").tag(SortOption.importedAtDesc.rawValue)
                    Text("导入时间 ↑").tag(SortOption.importedAtAsc.rawValue)
                    Text("文件名 A-Z").tag(SortOption.filenameAsc.rawValue)
                    Text("文件大小 ↓").tag(SortOption.fileSizeDesc.rawValue)
                    Text("文件大小 ↑").tag(SortOption.fileSizeAsc.rawValue)
                    Text("自定义顺序").tag(SortOption.customOrder.rawValue)
                }
                .pickerStyle(.menu)
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
        .frame(width: 480, height: 600)  // V3.6.13: 加高以容纳新增 3 个 section
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
