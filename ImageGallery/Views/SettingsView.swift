//
//  SettingsView.swift
//  ImageGallery
//
//  V3.6.13: 设置面板——单滚动视图 6 section（强调色/回收站/缩略图/视图/排序/外观）
//  V4.13.0: 改 Settings scene——独立 Preferences 窗口（⌘,）
//  V4.50.0: 改造 Photos 风格——sidebar 4 类 + detail 布局
//    之前单滚动 VStack 改为 NavigationSplitView
//    4 类别：通用 / 外观 / 图库 / 强调色
//    删 "完成" 按钮（macOS 标准：红 traffic light 关闭窗口）
//
//  设计原则：
//  - sidebar 用系统 List .sidebar 风格——macOS 偏好设置标准
//  - 每类独立子 View——@AppStorage 在子 View 里也能正常工作
//  - 不改 @AppStorage keys（向后兼容用户已存的偏好）
//

import SwiftUI

// MARK: - V4.50.0: 设置类别（sidebar 项）

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general       // 通用：默认视图/排序
    case appearance    // 外观：缩略图大小/外观模式
    case library       // 图库：回收站保留时长
    case accent        // 强调色

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "通用"
        case .appearance: return "外观"
        case .library:    return "图库"
        case .accent:     return "强调色"
        }
    }

    /// macOS Photos 风格 SF Symbol——sidebar 类别 icon
    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintbrush"
        case .library:    return "trash"
        case .accent:     return "paintpalette"
        }
    }
}

// MARK: - V4.50.0: 主设置视图

struct SettingsView: View {
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            // Sidebar: 类别列表
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            // Detail: 选中类别的设置内容
            //   NavigationSplitView 自动提供 sidebar/detail 切换
            //   Photos.app 标准：sidebar 选中高亮 + detail 切换
            Group {
                switch selectedCategory {
                case .general:
                    GeneralSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .library:
                    LibrarySettingsView()
                case .accent:
                    AccentSettingsView()
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
        .navigationTitle("设置")
        // V4.50.0: 删 .padding(Spacing.xl) 和固定 width 480 height 700
        //   NavigationSplitView 自动撑开——macOS 标准偏好设置窗口自适应
        //   Photos.app 偏好窗口也是自适应大小
    }
}

// MARK: - V4.50.0: 4 类设置子 View
//
// 设计：每类独立 View + @AppStorage 在子 View
//   优势：每类独立测试 + 维护，SettingsView 仅做 sidebar/detail 路由
//

// MARK: 通用（默认视图/排序）

private struct GeneralSettingsView: View {
    @AppStorage("viewModeRaw") private var defaultViewModeRaw: String = ViewMode.grid.rawValue
    @AppStorage("sortOption") private var defaultSortOption: String = SortOption.importedAtDesc.rawValue

    private let defaultViewModeOptions: [ViewMode] = ViewMode.allCases
    private let defaultSortOptions: [SortOption] = SortOption.allCases

    var body: some View {
        SettingsSection(title: "默认视图模式", subtitle: "启动应用时使用的图片显示布局") {
            Picker("视图模式", selection: $defaultViewModeRaw) {
                Text("网格").tag(ViewMode.grid.rawValue)
                Text("列表").tag(ViewMode.list.rawValue)
                Text("时间线").tag(ViewMode.timeline.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsSection(title: "默认排序", subtitle: "启动时图片按以下规则排序") {
            Picker("排序", selection: $defaultSortOption) {
                ForEach(defaultSortOptions) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

// MARK: 外观（缩略图大小/外观模式）

private struct AppearanceSettingsView: View {
    @AppStorage("thumbnailSize") private var defaultThumbnailSize: Double = 170
    @AppStorage("appearanceMode") private var appearanceModeRaw: Int = AppearanceMode.defaultValue.rawValue

    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .defaultValue },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        SettingsSection(
            title: "缩略图大小",
            subtitle: "默认缩略图尺寸。当前会话用 toolbar 临时改的会在重启后恢复。"
        ) {
            HStack {
                Slider(value: $defaultThumbnailSize, in: 100...250, step: 10)
                Text("\(Int(defaultThumbnailSize))")
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }

        SettingsSection(
            title: "外观",
            subtitle: "应用整体外观。\u{201C}跟随系统\u{201D} 会随 macOS 切换自动调整。"
        ) {
            Picker("外观", selection: appearanceModeBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: 图库（回收站保留时长）

private struct LibrarySettingsView: View {
    @AppStorage("trashRetentionDays") private var retentionDays: Int = TrashRetentionDays.defaultValue.rawValue

    var body: some View {
        SettingsSection(
            title: "自动清理",
            subtitle: "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。"
        ) {
            Picker("保留时长", selection: $retentionDays) {
                ForEach(TrashRetentionDays.allCases) { days in
                    Text(days.displayName).tag(days.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: 强调色

private struct AccentSettingsView: View {
    @AppStorage("accentColorID") private var accentColorID: String = AccentColor.system.rawValue

    var body: some View {
        SettingsSection(
            title: "强调色",
            subtitle: "选择应用的主色调，影响按钮、选中状态、链接等。"
        ) {
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
    }
}

// MARK: - V4.50.0: 通用 settings section 容器

/// Photos.app 偏好设置 panel 风格——每类设置有标题 + 副标题 + 内容
/// 抽到统一组件减少 4 个子 View 重复
private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.headline)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.panel, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - 强调色色板（V3.6.13 抽出独立 View）

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
    }
}
