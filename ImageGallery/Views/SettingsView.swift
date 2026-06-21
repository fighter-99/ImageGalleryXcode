//
//  SettingsView.swift
//  ImageGallery
//
//  V6.39.0 (Settings Refactor): 重构 — 5 → 7 categories, 平衡密度, 补缺
//    原 5 个 categories (通用/外观/图库/强调色/关于) 密度不均: 通用 2 sections 空,
//    外观 4 sections 满; 字体大小在通用 / 语言在外观概念错位; 缺常用项.
//
//  V6.39.0 新结构:
//    1. 通用 (启动默认值 + 双击行为 + 高级 actions)
//    2. 外观 (主题 / 强调色 / 字体大小)
//    3. 图库 (导入 / 导出默认)
//    4. 回收站 (保留时长 / 清空 action)  [新独立]
//    5. 语言 [新独立]
//    6. 快捷键 (嵌入 KeyboardShortcutsSheet)  [新]
//    7. 关于 (版本 / 链接 / 版权)
//
//  新增 UserSettings 字段:
//    - defaultImportLocation: String? (LibrarySettingsView 选择)
//    - doubleClickAction: DoubleClickAction (GeneralSettingsView 选择)
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - V6.01: 节奏统一常量 (沿用)
private enum SettingsMetrics {
    static let labelColumnWidth: CGFloat = 80
    static let titleSubtitleGap: CGFloat = Spacing.sm
}

// MARK: - V6.39.0: 关于页面链接 (占位 → 真实 URL)
private enum SettingsLinks {
    static let projectHomepage = "https://github.com/"
    static let helpDocs = "https://github.com/"
    static let issueTracker = "https://github.com/"
}

// MARK: - V6.08: 安全的 Link (沿用)
@ViewBuilder
private func safeExternalLink(_ urlString: String, @ViewBuilder label: () -> some View) -> some View {
    if let url = URL(string: urlString) {
        Link(destination: url, label: label)
    } else {
        label()
            .foregroundStyle(.red)
            .accessibilityLabel(Copy.settingsAccessibilityLinkMisconfigured(urlString))
    }
}

// MARK: - V6.39.0: 设置类别 (7 categories, 平衡密度)
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general       // 通用: 启动默认值 + 双击行为 + 高级 actions
    case appearance    // 外观: 主题/强调色/字体大小
    case library       // 图库: 导入/导出默认
    case trash         // 回收站: 保留时长/清空 [新独立]
    case language      // 语言 [新独立]
    case shortcuts     // 快捷键: 嵌入 KeyboardShortcutsSheet [新]
    case about         // 关于

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return Copy.settingsCategoryGeneral
        case .appearance: return Copy.settingsCategoryAppearance
        case .library:    return Copy.settingsCategoryLibrary
        case .trash:      return Copy.settingsCategoryTrash
        case .language:   return Copy.settingsCategoryLanguage
        case .shortcuts:  return Copy.settingsCategoryShortcuts
        case .about:      return Copy.settingsCategoryAbout
        }
    }

    /// V6.41: category 简短描述 — Photos 风格 detail 顶部大标题下方 subtitle
    var subtitle: String {
        switch self {
        case .general:    return Copy.settingsCategoryGeneralSubtitle
        case .appearance: return Copy.settingsCategoryAppearanceSubtitle
        case .library:    return Copy.settingsCategoryLibrarySubtitle
        case .trash:      return Copy.settingsCategoryTrashSubtitle
        case .language:   return Copy.settingsCategoryLanguageSubtitle
        case .shortcuts:  return Copy.settingsCategoryShortcutsSubtitle
        case .about:      return Copy.settingsCategoryAboutSubtitle
        }
    }

    /// macOS Photos 风格 SF Symbol — sidebar 类别 icon
    ///   全部 .fill (solid) — 视觉重量统一 (V6.07 沿用)
    var icon: String {
        switch self {
        case .general:    return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .library:    return "photo.stack.fill"
        case .trash:      return "trash.fill"
        case .language:   return "globe"
        case .shortcuts:  return "keyboard.fill"
        case .about:      return "info.circle.fill"
        }
    }
}

// MARK: - V6.39.0: 主设置视图
struct SettingsView: View {
    let settings: UserSettings

    // V6.45: 持久化最后选中 category — 跨 app restart 记忆
    //   之前 @SceneStorage 只在 scene 生命周期内保留, 关 app 后丢失
    //   现在 UserSettings.lastSettingsCategory 持久化到 UserDefaults
    //   用 @State + custom init 从 settings 读取 (替代 @SceneStorage)
    @State private var selectedCategoryRaw: String

    @State private var showingResetConfirm = false
    @State private var showingResetOnboardingConfirm = false
    @State private var showingEmptyTrashConfirm = false

    // V6.45: custom init — 用 settings.lastSettingsCategory 初始化 selectedCategoryRaw
    //   替代 @SceneStorage 默认值, 实现跨 app restart 记忆
    init(settings: UserSettings) {
        self.settings = settings
        self._selectedCategoryRaw = State(initialValue: settings.lastSettingsCategory)
    }

    // V6.51: Window 入场动画 — 打开 Settings 时 fade (0→1) + scale (0.98→1.0)
    //   macOS 标准窗口入场 (easeOut 200ms) — 视觉锤"窗口活过来"
    //   跟 macOS Sonoma+ System Settings 行为对齐
    @State private var appearanceProgress: Double = 0
    @State private var showingShortcutsSheet = false

    private var selectedCategory: Binding<SettingsCategory> {
        Binding(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general },
            set: {
                selectedCategoryRaw = $0.rawValue
                // V6.45: 持久化到 UserSettings (跨 app restart 记忆)
                settings.lastSettingsCategory = $0.rawValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // V6.41.1: Photos 风格顶部 tab 栏 — 替代 NavigationSplitView sidebar
            //   之前误判截图: 以为 Photos 用 sidebar, 实际是顶部 3 个 tab (通用/iCloud/共享图库)
            //   我们 7 category 用 ScrollView(.horizontal) 支持横向滚动
            //   选中态: 圆角背景 + tint 色图标/文字 (跟 Photos iCloud tab 选中态一致)
            // V6.50: tab bar 加 .background(.bar) — macOS 标准 toolbar 视觉
            //   之前透明背景, 跟 content 区域无视觉分隔. 现在 frosted glass 效果
            //   跟 macOS Sonoma+ Photos 真版 Preferences 顶部 tab 视觉一致
            CategoryTabBar(selection: selectedCategory)
                .background(.bar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // V6.41: Photos 风格 detail 顶部 — 大标题 + subtitle
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(selectedCategory.wrappedValue.title)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(selectedCategory.wrappedValue.subtitle)
                            .font(Typography.body)
                            .foregroundStyle(Surface.textSecondary)
                    }
                    .padding(.bottom, Spacing.sm)
                    Group {
                        switch selectedCategory.wrappedValue {
                        case .general:
                            GeneralSettingsView(
                                settings: settings,
                                onResetOnboarding: { showingResetOnboardingConfirm = true },
                                onOpenDataFolder: openDataFolder,
                                onResetAll: { showingResetConfirm = true }
                            )
                        case .appearance:
                            AppearanceSettingsView(settings: settings)
                        case .library:
                            LibrarySettingsView(settings: settings)
                        case .trash:
                            TrashSettingsView(
                                settings: settings,
                                onEmptyTrash: { showingEmptyTrashConfirm = true }
                            )
                        case .language:
                            LanguageSettingsView(settings: settings)
                        case .shortcuts:
                            ShortcutsSettingsView(onShowShortcuts: { showingShortcutsSheet = true })
                        case .about:
                            AboutSettingsView()
                        }
                    }
                    .id(selectedCategory.wrappedValue)
                    .transition(.opacity)
                    .animation(Animations.standard, value: selectedCategory.wrappedValue)
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            // V6.47: 缩 window minimum — Photos 真版 ~520pt wide × 400pt tall
            //   之前 640x480 让小屏用户被迫滚动, 不灵活
            minWidth: 520, idealWidth: 720,
            minHeight: 400, idealHeight: 560
        )
        // V6.51: Window 入场 fade + scale 动画 — macOS 标准 200ms ease-out
        //   打开 Settings 时从透明 + 98% scale → 完整, 视觉锤"窗口活过来"
        //   跟 macOS Sonoma+ System Settings / Photos 真版 Preferences 入场行为对齐
        .scaleEffect(0.98 + 0.02 * appearanceProgress, anchor: .center)
        .opacity(appearanceProgress)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                appearanceProgress = 1
            }
        }
        .navigationTitle(Copy.settingsTitle)
        // V6.41: 完全删 toolbar — macOS Photos Settings 风格
        //   之前 Reset + Help 2 个 toolbar item 太显眼, 跟 Photos "窗口只有 traffic light" 风格冲突
        //   Reset 移到 General > 高级 (跟"重置 Onboarding"同 section, destructive 上下文就近)
        //   Help 移到 About > 链接 (已有 3 个 safeExternalLink)
        //   ⓘ button 走右下角 overlay (Photos 风格, 极轻量浮层) — 见 detail overlay
        // V6.41: 右下角 ⓘ help button — Photos 真版浮层圆形 button, 不抢戏
        .overlay(alignment: .bottomTrailing) {
            safeExternalLink(SettingsLinks.helpDocs) {
                Image(systemName: "questionmark")
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: Circle())
            }
            .help(Copy.settingsHelpTooltip)
            .padding(Spacing.md)
        }
        // V6.45: 改用 .alert (macOS 真版 dialog window) — 替代 iOS 风格 .confirmationDialog sheet
        //   macOS Photos 用真 dialog, 不是从底部弹的 action sheet
        .alert(
            Copy.settingsResetConfirmTitle,
            isPresented: $showingResetConfirm
        ) {
            Button(Copy.settingsResetConfirmAction, role: .destructive) {
                settings.reset()
            }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(Copy.settingsResetConfirmMessage)
        }
        // V6.45: Reset Onboarding → .alert
        .alert(
            Copy.settingsResetOnboardingConfirmTitle,
            isPresented: $showingResetOnboardingConfirm
        ) {
            Button(Copy.settingsResetOnboardingConfirmAction, role: .destructive) {
                settings.hasSeenOnboarding = false
            }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(Copy.settingsResetOnboardingConfirmMessage)
        }
        // V6.45: Empty Trash → .alert
        .alert(
            Copy.settingsEmptyTrashConfirmTitle,
            isPresented: $showingEmptyTrashConfirm
        ) {
            Button(Copy.settingsEmptyTrashConfirmAction, role: .destructive) {
                emptyTrash()
            }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(Copy.settingsEmptyTrashConfirmMessage)
        }
        // V6.39.0: 完整 KeyboardShortcutsSheet (V5.60-7 已存在, 复用)
        .sheet(isPresented: $showingShortcutsSheet) {
            KeyboardShortcutsSheet()
        }
    }

    // MARK: - V6.39.0: Action handlers

    /// 打开数据文件夹 (NSWorkspace file viewer — macOS 标准 "Reveal in Finder")
    ///   不需要 ModelContext — 直接打开 Application Support/ImageGallery/
    private func openDataFolder() {
        // V6.39.0: PhotoStorage 只暴露 photosDirectory (Photos/ 子目录),
        //   deletingLastPathComponent → Application Support/ImageGallery/
        let url = PhotoStorage.shared.photosDirectory.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 清空回收站 — 走 ContentViewModel.grid.emptyTrash
    ///   V6.39.0: 这里需要 ContentViewModel 引用, 但 SettingsView 不持有
    ///   改: 发 NotificationCenter 通知, ContentViewModel 监听后调 emptyTrash
    ///   或者: 直接走 NSWorkspace 弹 "清空回收站" 走 trash 服务
    ///   选择: NotificationCenter (跟 .newFolderRequested / .speakRequested 同一 pattern)
    private func emptyTrash() {
        NotificationCenter.default.post(name: .emptyTrashRequested, object: nil)
    }
}

// MARK: - V6.39.0: NotificationCenter 事件
extension Notification.Name {
    static let emptyTrashRequested = Notification.Name("settings.emptyTrashRequested")
}

// MARK: - 通用 (启动默认值 + 双击行为 + 高级 actions)
private struct GeneralSettingsView: View {
    @Bindable var settings: UserSettings
    let onResetOnboarding: () -> Void
    let onOpenDataFolder: () -> Void
    // V6.41: 从 toolbar 移下来 — Reset 跟"重置 Onboarding"同 section (destructive 上下文就近)
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
        }

        // V6.48: 默认缩略图大小 — PhotosSettingRow 紧凑化 (SettingsSection 3 HStack → PhotosSettingRow + 1 preview 行)
        //   之前 SettingsSection 有 title + slider row + min/max row + preview = 4 HStack 视觉割裂
        //   现在 PhotosSettingRow 统一 title/subdescription + slider (1 row), 下方 preview + min/max (1 row)
        //   跟 macOS Sonoma+ System Settings 紧凑布局对齐
        PhotosSettingRow(
            title: Copy.settingsThumbnailSizeTitle,
            description: Copy.settingsThumbnailSizeSubtitle
        ) {
            HStack(spacing: Spacing.sm) {
                Slider(value: $settings.thumbnailSize, in: 100...250, step: 10)
                    .frame(width: 160)
                Text(Copy.thumbnailSizeLabel(Int(settings.thumbnailSize)))
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        // V6.48: min/max + preview — 独立 1 行 (紧跟 PhotosSettingRow 之后, 视觉紧凑)
        HStack(spacing: Spacing.md) {
            Text(Copy.settingsThumbnailSizeSmall)
                .font(Typography.caption)
                .foregroundStyle(Surface.textSecondary)
            Spacer()
            ThumbnailSizePreview(size: $settings.thumbnailSize)
            Spacer()
            Text(Copy.settingsThumbnailSizeLarge)
                .font(Typography.caption)
                .foregroundStyle(Surface.textSecondary)
        }

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
            HStack {
                Text(Copy.settingsResetOnboardingLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(Copy.settingsResetOnboardingButton, role: .destructive, action: onResetOnboarding)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(Copy.settingsResetOnboardingTooltip)  // V6.46: 详细 tooltip
            }
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
private struct AppearanceSettingsView: View {
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
private struct LibrarySettingsView: View {
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
        PhotosCheckbox(
            title: Copy.settingsImportTitle,
            description: Copy.settingsImportSubtitle,
            isOn: $settings.autoDeduplicate.wrappedValue,
            onToggle: { settings.autoDeduplicate.toggle() }
        )

        PhotosCheckbox(
            title: Copy.settingsAutoThumbnailsLabel,
            description: Copy.settingsAutoGenerateThumbnailsDescription,
            isOn: $settings.autoGenerateThumbnails.wrappedValue,
            onToggle: { settings.autoGenerateThumbnails.toggle() }
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
private struct TrashSettingsView: View {
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
private struct LanguageSettingsView: View {
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
private struct ShortcutsSettingsView: View {
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
private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            // V6.42: Photos 风格 row — 应用信息 (icon + name + version)
            PhotosSettingRow(
                title: Copy.appName,
                description: AppVersion.current.displayString
            ) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.appIcon, style: .continuous))
                }
            }

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

// MARK: - V6.41.1: Photos 风格顶部 tab 栏 (替代 NavigationSplitView sidebar)
//
// 截图1.png 观察: Photos.app macOS Sonoma+ Settings 用顶部 tab 切换 (3 个),
// 不是 sidebar. 选中 tab: 圆角背景 + tint 色图标/文字 + tint 文字 label.
// 我们 7 category 用 ScrollView(.horizontal) 支持横向滚动.
//
// 视觉规范 (跟截图 iCloud tab 一致):
//   - tab 宽 80pt, 高 56pt
//   - icon 24pt (跟 sidebar 字号 13pt 区分, 更突出)
//   - label caption (11pt)
//   - 选中: Color.accentColor.opacity(0.15) 圆角背景 + tint 图标/文字
//   - 未选: 透明背景 + secondary 图标/文字
//   - hover: 极轻 .quaternary 背景

private struct CategoryTabBar: View {
    @Binding var selection: SettingsCategory

    // V6.49: @FocusState — auto-focus 当前选中 tab (键盘 accessibility)
    //   打开 Settings 时焦点自动落在 "通用" tab, 用户可直接 ↑↓ ←→ 切换 (macOS 真版模式)
    //   Photos 真版也这样做 — 打开 Preferences 焦点立即可操作
    @FocusState private var focusedCategory: SettingsCategory?

    var body: some View {
        // V6.47: ScrollViewReader 监听 selection 变化 → 自动滚到选中 tab
        //   之前: 7 个 tab 横排, 选中 tab 若超出视口会被截断, 用户看不到自己选的
        //   现在: scrollTo(selection, anchor: .center) 自动滚到选中 (类似 macOS Sonoma+ Photos)
        // V6.49: 加 onAppear auto-focus — 焦点自动落到当前 selection
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(SettingsCategory.allCases) { category in
                        CategoryTabButton(
                            category: category,
                            isSelected: selection == category,
                            onTap: { selection = category }
                        )
                        .id(category)  // ScrollViewReader anchor (SettingsCategory Hashable)
                        // V6.49: focus binding — 每个 tab 都跟 focusedCategory 关联, 切 tab 时焦点跟着走
                        .focused($focusedCategory, equals: category)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity)  // 居中 (跟 Photos 顶部 tab 居中布局一致)
            }
            .onChange(of: selection) { _, new in
                withAnimation(Animations.quick) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        // V6.49: Auto-focus 当前选中 tab (Settings 打开时焦点立即可操作)
        //   DispatchQueue.main.asyncAfter 0.05s — 等 window focus + onAppear 都稳定后再设焦点
        //   避免 macOS window 还没 focus 时调用 focusedCategory = nil
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedCategory = selection
            }
        }
    }
}

private struct CategoryTabButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        // V6.45: hover state — 未选 tab 鼠标悬停时背景变 .quaternary (轻浮视觉反馈)
        //   选中 tab 用 accent 圆角背景 (已有), hover 在未选 tab 上才有意义
        // V6.46: hierarchical rendering — SF Symbol 多色梯度 (跟 macOS Sonoma+ System Settings 一致)
        //   默认 monochrome 是单色, hierarchical 给我们 tint 颜色的多色梯度 (视觉更丰富)
        @State var isHovered = false
        return Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    // V6.46: hierarchical — 多色梯度, macOS Sonoma+ 真版 System Settings 风格
                    .symbolRenderingMode(.hierarchical)
                Text(category.title)
                    .font(Typography.caption)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Surface.textSecondary)
            .frame(width: 80, height: 56)
            .background(
                isSelected ? Color.accentColor.opacity(0.15)
                : (isHovered ? Color.primary.opacity(0.06) : .clear),
                in: RoundedRectangle(cornerRadius: Radius.md)
            )
        }
        .buttonStyle(.plain)
        // V6.47: tooltip 显示 "Title — Subtitle" — 让用户 hover 时理解 category 用途
        //   之前只显示 title (例如 "回收站"), 用户不知道里面有什么
        //   现在显示 "回收站 — 回收站保留时长与清空" — 跟 macOS Sonoma+ Settings 一致
        .help("\(category.title) — \(category.subtitle)")
        .onHover { isHovered = $0 }
    }
}

// MARK: - V6.42: Photos 风格 setting row 组件
//
// 截图1.png 视觉规范:
//   - 顶层 group label: 16pt semibold (Photos iCloud page "iCloud 照片")
//   - 描述: 11pt secondary, indent 跟 group label 起点对齐
//   - radio 选项: 圆圈 + label, **indented +32pt** from group
//   - radio 描述: 11pt secondary, indent 跟 radio 对齐
//
// PhotosSettingRow — 单个 setting row (title + desc + trailing control)
//   替代之前 "label 80pt 固定列宽 + Picker" 模式
// PhotosRadioGroup — radio 选项容器 (用于 hierarchical settings)

/// V6.42: Photos 风格 setting row — 单行设置 (title + description + trailing control)
///   Title 16pt semibold + 11pt secondary description (跟截图 iCloud 行的 visual hierarchy 一致)
///   trailing control 在 right (Picker / Toggle / Slider)
private struct PhotosSettingRow<Trailing: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.description = description
        self.trailing = trailing
    }

    var body: some View {
        // V6.42: Photos 风格 — leading 是 title/desc stack, trailing 是 control
        //   Spacer 让 control 推到右侧; baseline alignment 让 control 跟 title 对齐
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.md)
            trailing()
        }
    }
}

/// V6.42: Photos 风格 radio option — 单个 radio 选项
///   圆圈 + label (14pt regular) + description (11pt)
///   Photos 选中态: 实心圆点 (蓝) — 用 SF Symbol circle.inset.filled
///   未选中: 空圆圈 — SF Symbol circle
private struct PhotosRadioOption<Trailing: View>: View {
    let title: String
    let description: String?
    let isSelected: Bool
    let onTap: () -> Void
    @ViewBuilder let trailing: (() -> Trailing)?

    init(
        title: String,
        description: String? = nil,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.onTap = onTap
        self.trailing = trailing
    }

    var body: some View {
        // V6.45: hover state — radio option 在鼠标悬停时背景微微变深
        //   Photos 真版 feedback: hover 给用户"可点"暗示, 不像 click 按钮那么重
        @State var isHovered = false
        return Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                            .font(Typography.caption)
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Spacing.md)
                if let trailing {
                    trailing()
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                isHovered && !isSelected ? Surface.hover : .clear,
                in: RoundedRectangle(cornerRadius: Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// V6.43: Photos 风格 checkbox — SF Symbol 模拟 macOS Sonoma+ 蓝填充框
///   选中: `checkmark.square.fill` (蓝底白勾)
///   未选: `square` (灰框)
///   替代 .toggle 的 switch 样式 — macOS Photos 用 checkbox 而非 switch
private struct PhotosCheckbox: View {
    let title: String
    let description: String?
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        // V6.48: hover 反馈 — 跟 PhotosRadioOption + CategoryTabButton 一致
        //   未选 checkbox 悬停时 Surface.hover 浅背景 — 用户感觉"可点"
        //   选中时不显示 hover (避免视觉冲突)
        @State var isHovered = false
        return Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                            .font(Typography.caption)
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Spacing.md)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                isHovered && !isOn ? Surface.hover : .clear,
                in: RoundedRectangle(cornerRadius: Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// V6.43: Photos 风格 setting with radios — vertical stack of PhotosRadioOption
///   用于 settings 有多个选项 (替代 .menu Picker + SettingsSection 嵌套)
///   跟截图 iCloud page "iCloud 照片" group label 一样: title + description + 子 radios stacked
private struct PhotosSettingRadios<T: Hashable>: View {
    let title: String
    let description: String?
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let optionDescription: (T) -> String?

    init(
        title: String,
        description: String? = nil,
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String,
        optionDescription: @escaping (T) -> String? = { _ in nil }
    ) {
        self.title = title
        self.description = description
        self.options = options
        self._selection = selection
        self.label = label
        self.optionDescription = optionDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    PhotosRadioOption(
                        title: label(option),
                        description: optionDescription(option),
                        isSelected: selection == option,
                        onTap: { selection = option }
                    )
                }
            }
        }
    }
}

// MARK: - 通用 settings section 容器 (沿用 V5.89 fluid rows 设计)
private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: SettingsMetrics.titleSubtitleGap) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 强调色色板 (沿用)
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

// MARK: - 缩略图大小 slider 实时预览 (沿用)
private struct ThumbnailSizePreview: View {
    @Binding var size: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Surface.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Surface.cardBorder, lineWidth: 1)
                }
            Image(systemName: "photo")
                .font(Typography.thumbnailPreview)
                .scaleEffect(displayScale)
                .foregroundStyle(.primary)
        }
        .frame(width: 100, height: 100)
        .help(Copy.settingsThumbnailSizeHelpTooltip)
    }

    private var displayScale: Double {
        0.3 + (size - 100) / 150 * 0.7
    }
}
