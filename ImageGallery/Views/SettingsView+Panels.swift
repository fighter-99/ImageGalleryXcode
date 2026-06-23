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

// MARK: - 通用 (启动默认值 + 双击行为 + 高级 actions)
struct GeneralSettingsView: View {
    @Bindable var settings: UserSettings
    // V6.70: 删 onResetOnboarding 参数 — OnboardingView 取消
    let onOpenDataFolder: () -> Void
    // V6.41: 从 toolbar 移下来 — Reset 跟 destructive actions 同 section
    let onResetAll: () -> Void

    var body: some View {
        // V6.42: Photos 风格 — 每个 setting 一个 PhotosSettingRow

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
        //   不用 PhotosSettingRow — 因为有 3 个 button rows, 用 SettingsSection 容器
        SettingsSection(
            title: Copy.settingsAdvancedTitle,
            subtitle: Copy.settingsAdvancedSubtitle
        ) {
            HStack {
                Text(Copy.settingsOpenDataFolderLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(Copy.settingsOpenDataFolderButton, action: onOpenDataFolder)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(Copy.settingsOpenDataFolderTooltip)  // V6.46: 详细 tooltip
            }
            // V6.70: 删 HStack onboarding row — OnboardingView 取消 (8 行)
            HStack {
                Text(Copy.settingsResetAllLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - 图库 (导入/导出)
struct LibrarySettingsView: View {
    @Bindable var settings: UserSettings
    @State private var showingImportLocationPanel = false

    var body: some View {
        // V6.42: Photos 风格 — 每个 setting 一个 PhotosSettingRow

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
    }

    private var currentImportLocationDisplay: String {
        if let urlString = settings.defaultImportLocation,
           let url = URL(string: urlString) {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return Copy.settingsImportLocationEmpty
    }
}

// MARK: - V6.39.0 NEW: 回收站 (从图库拆出)
struct TrashSettingsView: View {
    @Bindable var settings: UserSettings
    let onEmptyTrash: () -> Void

    var body: some View {
        // V6.43: Photos 真版 radio group — 4 个保留时长选项垂直 stacked
        //   替代之前的 Picker .menu dropdown — Photos 风格是直接看到所有选项
        PhotosSettingRadios(
            title: Copy.settingsRetentionTitle,
            description: Copy.settingsRetentionSubtitle,
            options: TrashRetentionDays.allCases,
            selection: $settings.appTrashRetentionDays,
            label: { $0.displayName },
            optionDescription: { _ in nil }
        )

        // V6.43: 清空回收站 action — PhotosSettingRow + destructive Button
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

// MARK: - V6.39.0 NEW: 快捷键 (嵌入 KeyboardShortcutsSheet 入口)
struct ShortcutsSettingsView: View {
    let onShowShortcuts: () -> Void

    var body: some View {
        // V6.42: Photos 风格 row
        PhotosSettingRow(
            title: Copy.settingsShortcutsTitle,
            description: Copy.settingsShortcutsSubtitle
        ) {
            Button(Copy.settingsShortcutsShowButton, action: onShowShortcuts)
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }
}

// MARK: - 关于
struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
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

            // 链接 section — 多个 external links, 用 SettingsSection 容器
            SettingsSection(title: Copy.settingsLinksTitle, subtitle: nil) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    safeExternalLink(SettingsLinks.projectHomepage) {
                        Label(Copy.settingsProjectHomepage, systemImage: "arrow.up.right.square")
                    }
                    safeExternalLink(SettingsLinks.helpDocs) {
                        Label(Copy.settingsHelpDocs, systemImage: "book")
                    }
                    safeExternalLink(SettingsLinks.issueTracker) {
                        Label(Copy.settingsIssueTracker, systemImage: "exclamationmark.bubble")
                    }
                }
            }

            // V6.50: 系统信息 section — macOS 版本 (ProcessInfo.operatingSystemVersionString)
            //   给用户 / 客服报告 bug 时方便确认环境
            SettingsSection(title: Copy.settingsAboutSystemInfoTitle, subtitle: nil) {
                HStack {
                    Text(Copy.settingsAboutMacOSVersionLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        .font(Typography.captionMono)
                        .foregroundStyle(Surface.textSecondary)
                }
            }

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
