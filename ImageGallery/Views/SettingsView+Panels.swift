import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 安全的 Link (沿用)
@ViewBuilder
func safeExternalLink(_ urlString: String, @ViewBuilder label: () -> some View) -> some View {
    if let url = URL(string: urlString) {
        Link(destination: url, label: label)
    } else {
        label()
            .foregroundStyle(.red)
            .accessibilityLabel(Copy.settingsAccessibilityLinkMisconfigured(urlString))
    }
}

// MARK: - 通用 (启动默认值 + 双击行为 + 高级 actions + V6.90.0: 快捷键)
struct GeneralSettingsView: View {
    @Bindable var settings: UserSettings
    // V6.70: 删 onResetOnboarding 参数 — OnboardingView 取消
    let onOpenDataFolder: () -> Void
    // V6.41: 从 toolbar 移下来 — Reset 跟 destructive actions 同 section
    let onResetAll: () -> Void
    // V6.90.0: 加 onShowShortcuts — 快捷键 row 合并到通用 (原 ShortcutsSettingsView)
    let onShowShortcuts: () -> Void

    var body: some View {
        // V6.42: Photos 风格 — 每个 setting 一个 PhotosSettingRow
        // V6.90.0: 4 个 section — 1) 默认视图模式  2) 默认排序  3) 双击行为  4) 高级 actions (含快捷键入口 + 数据文件夹 + 恢复默认)

        // 默认视图模式
        PhotosSettingRow(
            title: Copy.settingsDefaultViewTitle,
            description: Copy.settingsDefaultViewSubtitle
        ) {
            Picker("", selection: $settings.appViewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Copy.settingsDefaultViewTitle)
        }

        // 默认排序
        PhotosSettingRow(
            title: Copy.settingsDefaultSortTitle,
            description: Copy.settingsDefaultSortSubtitle
        ) {
            Picker("", selection: $settings.sortOption) {
                ForEach(SortOption.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Copy.settingsDefaultSortTitle)
        }

        // V6.79: 默认缩略图大小 slider 删 — toolbar 集成 slider (Photos 真版 view options 模式)
        //   toolbar 直接改 settings.thumbnailSize (持久化), SettingsView slider 单一入口消除
        //   ThumbnailSizePreview 也删 (slider 已无, preview 跟着无意义)
        //   Copy.settingsThumbnailSizeTitle/Subtitle 等文案保留 (reset 提示仍引用)

        // V6.43: 双击行为 — PhotosSettingRadios 替代 Picker (2 选项, vertical stack 更 Photos)
        PhotosSettingRadios(
            title: Copy.settingsDoubleClickTitle,
            description: Copy.settingsDoubleClickSubtitle,
            options: DoubleClickAction.allCases,
            selection: $settings.appDoubleClickAction,
            label: { $0.displayName },
            optionDescription: { _ in nil }
        )

        // 高级 actions — destructive 操作就地放 (Photos 风格就近)
        //   用 SettingsSection 容器包 3 个 PhotosSettingRow — V6.92.3 视觉统一
        //   之前 1 个 PhotosSettingRow (快捷键) + 2 个 HStack (数据文件夹/重置) 视觉不一致
        //   现在统一 PhotosSettingRow 包装, 整个 section 3 row 同 widget, 视觉锤一致
        SettingsSection(
            title: Copy.settingsAdvancedTitle,
            subtitle: Copy.settingsAdvancedSubtitle
        ) {
            // V6.90.0: 快捷键 row — PhotosSettingRow + 显示 button (替代原 ShortcutsSettingsView)
            //   跟 macOS Sonoma+ System Settings 真版 "Shortcuts" 入口一致
            PhotosSettingRow(
                title: Copy.settingsShortcutsTitle,
                description: Copy.settingsShortcutsSubtitle
            ) {
                Button(Copy.settingsShortcutsShowButton, action: onShowShortcuts)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            // V6.92.3: 打开数据文件夹 — HStack 改 PhotosSettingRow (视觉一致)
            //   PhotosSettingRow 提供 title + description + trailing control 跟其他 row 一致
            //   description 为 nil (旧 HStack 只有 label, 没有 description)
            PhotosSettingRow(
                title: Copy.settingsOpenDataFolderLabel,
                description: nil
            ) {
                Button(Copy.settingsOpenDataFolderButton, action: onOpenDataFolder)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(Copy.settingsOpenDataFolderTooltip)  // V6.46: 详细 tooltip
            }
            // V6.92.3: 重置默认 — HStack 改 PhotosSettingRow (视觉一致)
            //   destructive button role 保留 (PhotosSettingRow trailing 接受任何 View)
            PhotosSettingRow(
                title: Copy.settingsResetAllLabel,
                description: nil
            ) {
                Button(Copy.settingsResetAll, role: .destructive, action: onResetAll)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
    }
}

// MARK: - 外观 (主题 / 强调色 / 字体大小)
struct AppearanceSettingsView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        // V6.42: Photos 风格 — 每个 setting 一个 PhotosSettingRow
        //   标题 16pt semibold + 11pt secondary description (跟 macOS Sonoma+ System Settings 一致)
        //   trailing control 推到右侧 (Picker / Slider / Toggle)

        // 缩略图布局
        PhotosSettingRow(
            title: Copy.settingsLayoutTitle,
            description: Copy.settingsLayoutSubtitle
        ) {
            Picker("", selection: $settings.thumbnailLayoutMode) {
                ForEach(ThumbnailLayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Copy.settingsLayoutTitle)
        }

        // 主题
        PhotosSettingRow(
            title: Copy.settingsAppearanceTitle,
            description: Copy.settingsAppearanceSubtitle
        ) {
            Picker("", selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Copy.settingsAppearanceTitle)
        }

        // 字体大小
        PhotosSettingRow(
            title: Copy.settingsFontSizeTitle,
            description: Copy.settingsFontSizeSubtitle
        ) {
            Picker("", selection: $settings.appFontScale) {
                ForEach(FontScale.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }

        // 强调色 — V6.44 重构: 不走 PhotosSettingRow trailing (会聚集右侧)
        //   改成独立 section block — title/subtitle 顶部, 9 色 swatch 在下方 2 行 (5 + 4)
        //   视觉: 标题为锚点, colors 下方展开 — 跟 macOS Sonoma+ Photos accent picker 接近
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: SettingsMetrics.titleSubtitleGap) {
                Text(Copy.settingsAccentSectionTitle)
                    .font(Typography.headline)
                Text(Copy.settingsAccentSectionSubtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                let colors = AccentColor.allCases
                let halfPoint = (colors.count + 1) / 2  // 9 colors → 5 + 4 split
                HStack(spacing: Spacing.md) {
                    ForEach(colors.prefix(halfPoint)) { accent in
                        AccentSwatch(
                            accent: accent,
                            isSelected: settings.accentColorID == accent.rawValue,
                            onTap: { settings.accentColorID = accent.rawValue }
                        )
                    }
                }
                HStack(spacing: Spacing.md) {
                    ForEach(colors.dropFirst(halfPoint)) { accent in
                        AccentSwatch(
                            accent: accent,
                            isSelected: settings.accentColorID == accent.rawValue,
                            onTap: { settings.accentColorID = accent.rawValue }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 图库 (导入/导出 + V6.90.0: 回收站)
struct LibrarySettingsView: View {
    @Bindable var settings: UserSettings
    @State private var showingImportLocationPanel = false
    // V6.90.0: 加 onEmptyTrash — 回收站 row 合并到图库 (原 TrashSettingsView 内容)
    let onEmptyTrash: () -> Void

    var body: some View {
        // V6.42: Photos 风格 — 每个 setting 一个 PhotosSettingRow
        // V6.90.0: 5 个 section 用 SettingsSection 容器分组 — section 间间距 16pt (V6.90.6)
        //   1) 默认导入位置  2) 自动去重 + 自动缩略图  3) 导出格式  4) 导出质量  5) 回收站

        // 默认导入位置
        PhotosSettingRow(
            title: Copy.settingsImportLocationTitle,
            description: Copy.settingsImportLocationSubtitle
        ) {
            HStack(spacing: Spacing.sm) {
                Text(currentImportLocationDisplay)
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .trailing)
                Button(Copy.settingsImportLocationChooseButton) {
                    showingImportLocationPanel = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if settings.defaultImportLocation != nil {
                    Button(Copy.settingsImportLocationClearButton) {
                        settings.defaultImportLocation = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImportLocationPanel,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                settings.defaultImportLocation = url.absoluteString
            }
        }

        // V6.43: PhotosCheckbox — 替代 .toggle (switch), 用蓝填充方框 + 白勾
        // V6.58 (audit P1.6): 传 @Binding 直接绑 — 之前传 Bool + onToggle 分离,
        //   外部 mutation (例如 reset()) 不会更新 checkbox 视觉
        PhotosCheckbox(
            title: Copy.settingsImportTitle,
            description: Copy.settingsImportSubtitle,
            isOn: $settings.autoDeduplicate
        )

        PhotosCheckbox(
            title: Copy.settingsAutoThumbnailsLabel,
            description: Copy.settingsAutoGenerateThumbnailsDescription,
            isOn: $settings.autoGenerateThumbnails
        )

        // V6.43: PhotosSettingRadios — 3 个导出格式选项垂直 stacked
        PhotosSettingRadios(
            title: Copy.settingsExportTitle,
            description: Copy.settingsExportSubtitle,
            options: ExportFormat.allCases,
            selection: $settings.appExportFormat,
            label: { $0.displayName },
            optionDescription: { _ in nil }
        )

        // 导出质量 (Slider) — 保留 PhotosSettingRow (slider 复合 row)
        PhotosSettingRow(
            title: Copy.settingsQualityLabel,
            description: nil
        ) {
            HStack(spacing: Spacing.sm) {
                Slider(value: $settings.defaultExportQuality, in: 0.5...1.0, step: 0.05)
                    .frame(width: 160)
                    .accessibilityLabel(Copy.settingsQualityLabel)
                    .accessibilityValue("\(Int(settings.defaultExportQuality * 100))%")
                Text(Copy.exportQualityPercent(Int(settings.defaultExportQuality * 100)))
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }

        // V6.90.0: 回收站 section 合并 — 原 TrashSettingsView 内容
        //   视觉分组: 直接用 PhotosSettingRadios (跟原 TrashSettingsView 一致),
        //   不用 SettingsSection wrapper (PhotosSettingRadios 自己有 title + description header)
        // V6.43: Photos 真版 radio group — 4 个保留时长选项垂直 stacked
        PhotosSettingRadios(
            title: Copy.settingsRetentionTitle,
            description: Copy.settingsRetentionSubtitle,
            options: TrashRetentionDays.allCases,
            selection: $settings.appTrashRetentionDays,
            label: { $0.displayName },
            optionDescription: { _ in nil }
        )

        // V6.90.0: 清空回收站 action — 单独 PhotosSettingRow (跟 Library 其他 row 一致)
        PhotosSettingRow(
            title: Copy.settingsEmptyTrashTitle,
            description: Copy.settingsEmptyTrashSubtitle
        ) {
            Button(Copy.settingsEmptyTrashButton, role: .destructive, action: onEmptyTrash)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(Copy.settingsEmptyTrashTooltip)  // V6.46: 详细 tooltip
        }
    }

    private var currentImportLocationDisplay: String {
        if let urlString = settings.defaultImportLocation,
           let url = URL(string: urlString) {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return Copy.settingsImportLocationEmpty
    }
}

// MARK: - V6.39.0 NEW: 语言 (独立 category)
struct LanguageSettingsView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        // V6.42: Photos 风格 row
        PhotosSettingRow(
            title: Copy.settingsLanguageTitle,
            description: Copy.settingsLanguageSubtitle
        ) {
            Picker("", selection: $settings.appLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}

// MARK: - 关于
// V6.90.0: 重构为 3 段分组 — Header (app icon + 名称 + 版本) / Information (链接 + 系统信息) / Footer (版权)
//   跟 macOS Sonoma+ System Settings About 真版 3 段布局一致
struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            // === Header section ===
            // 标准 macOS 关于布局 — app icon + 名称 + 版本左对齐
            HStack(spacing: Spacing.lg) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.appIcon, style: .continuous))
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(Copy.appName)
                        .font(Typography.title)
                    Text(AppVersion.current.displayString)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // === Information section ===
            // V6.90.0: 合并链接 + 系统信息 2 个 section 为 1 个 "Information" section
            //   视觉分组跟 macOS Sonoma+ System Settings About 真版一致 (header + information + footer)
            // V6.88.4: 3 个 link 全部统一 row 模式 (icon + title + Spacer + arrow.up.right.square.tertiary)
            SettingsSection(title: Copy.settingsLinksTitle, subtitle: nil) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // V6.88.4: projectHomepage row — icon "house" + title + arrow
                    safeExternalLink(SettingsLinks.projectHomepage) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "house")
                                .foregroundStyle(.secondary)
                            Text(Copy.settingsProjectHomepage)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // V6.86.5: helpDocs row — icon questionmark.circle + title + arrow (V6.88.4 跟其他统一)
                    safeExternalLink(SettingsLinks.helpDocs) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                            Text(Copy.settingsHelpDocs)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .help(Copy.settingsHelpTooltip)
                    // V6.88.4: issueTracker row — icon exclamationmark.bubble + title + arrow
                    safeExternalLink(SettingsLinks.issueTracker) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundStyle(.secondary)
                            Text(Copy.settingsIssueTracker)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // V6.90.0: macOS 版本信息 合并到 Links section 内 — 跟 macOS 真版 "Information" section 一致
                    Divider()
                        .padding(.vertical, Spacing.xs)
                    HStack {
                        Text(Copy.settingsAboutMacOSVersionLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ProcessInfo.processInfo.operatingSystemVersionString)
                            .font(Typography.captionMono)
                            .foregroundStyle(Surface.textSecondary)
                    }
                }
            }

            // === Footer section ===
            // 版权 section — 多行文字, 保留 SettingsSection 容器
            SettingsSection(title: Copy.settingsCopyrightTitle, subtitle: nil) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(Copy.settingsCopyright)
                        .font(Typography.body)
                    Text(Copy.builtWithStack)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                }
            }
        }
    }
}


// MARK: - V6.42: Photos 风格 setting row 组件

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
                            .font(Typography.headline)
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

// V6.79: 删 ThumbnailSizePreview struct — SettingsView slider 已删, preview 跟着无意义
//   之前 toolbar +- 按钮临时改 live, slider 改 stored, 2 处入口; V6.79 单一 toolbar slider 入口
//   toolbar 本身有 thumbnailSize label 显示当前值 (即时反馈), 不需要 preview icon
