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
// V5.57-1: 加 .about——macOS Photos.app 习惯，about 放最末

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general       // 通用：默认视图/排序
    case appearance    // 外观：缩略图大小/外观模式
    case library       // 图库：回收站保留时长
    case accent        // 强调色
    case about         // V5.57-1: 关于——版本号/build/链接

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "通用"
        case .appearance: return "外观"
        case .library:    return Term.library
        case .accent:     return "强调色"
        case .about:      return "关于"
        }
    }

    /// macOS Photos 风格 SF Symbol——sidebar 类别 icon
    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintbrush"
        case .library:    return "trash"
        case .accent:     return "paintpalette"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - V4.50.0: 主设置视图
// V5.57-1: detail 容器包 VStack(spacing: Spacing.lg) + 底部"恢复全部为默认"按钮
// V5.57-2: @SceneStorage 持久化 selectedCategory——关掉设置重开回到上次类别

struct SettingsView: View {
    // V5.57-2: @SceneStorage 持久化类别选择 (scope = scene, 不是 app)
    //   同时开 2 个 ImageGallery 窗口各自记忆——photos.app Settings scene 同模式
    //   字符串 (rawValue) 而非 enum——@SceneStorage 不直接支持 enum
    @SceneStorage("settingsSelectedCategoryRaw") private var selectedCategoryRaw: String = SettingsCategory.general.rawValue

    private var selectedCategory: Binding<SettingsCategory> {
        Binding(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general },
            set: { selectedCategoryRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar: 类别列表
            List(SettingsCategory.allCases, selection: selectedCategory) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            // Detail: 选中类别的设置内容
            //   NavigationSplitView 自动提供 sidebar/detail 切换
            //   Photos.app 标准：sidebar 选中高亮 + detail 切换
            //   V4.55.0: 加 .id + .transition + .animation——切换时 detail 内容淡入+右移
            //     仿 V3.6.44 DetailPane 模式（.id(viewKind) 强制 SwiftUI 视为不同视图触发 transition）
            //   V5.57-1: 包 VStack(spacing: Spacing.lg)——多卡片间自动有间距
            //     + 底部"恢复全部为默认"按钮（macOS 偏好无 undo/确认，Photos.app 同模式）
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Group {
                    switch selectedCategory.wrappedValue {
                    case .general:
                        GeneralSettingsView()
                    case .appearance:
                        AppearanceSettingsView()
                    case .library:
                        LibrarySettingsView()
                    case .accent:
                        AccentSettingsView()
                    case .about:
                        AboutSettingsView()
                    }
                }
                .id(selectedCategory.wrappedValue)  // V4.55.0: 强制 SwiftUI 视为不同视图（transition 关键）
                .transition(.opacity.combined(with: .move(edge: .trailing)))  // V4.55.0: 渐入+右移——Photos 风格
                .animation(Animations.standard, value: selectedCategory.wrappedValue)  // V4.55.0: 驱动 transition

                // V5.57-1: 恢复全部为默认——不挂确认弹窗（macOS Photos.app 偏好无确认）
                //   写入 12 个 @AppStorage key 到 *.defaultValue/inline literal
                //   Phase 3 改为走 model.settings 单一真相源
                Spacer(minLength: Spacing.md)
                HStack {
                    Spacer()
                    Button("恢复全部为默认") {
                        resetAllSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
        .navigationTitle("设置")
        // V4.50.0: 删 .padding(Spacing.xl) 和固定 width 480 height 700
        //   NavigationSplitView 自动撑开——macOS 标准偏好设置窗口自适应
        //   Photos.app 偏好窗口也是自适应大小
    }

    /// V5.57-1: 恢复全部 12 个设置项为默认
    ///   复用 *.defaultValue (Models/{TrashRetentionDays,AppearanceMode,ThumbnailLayoutMode,AccentColor}.swift)
    ///   inline literal 默认值与 ContentView.swift @AppStorage 声明对齐
    ///   Phase 3 推 model.settings 后改用 UserSettings.reset() 单一入口
    private func resetAllSettings() {
        // V5.57-1: 写回 UserDefaults 12 个 key——临时写在 View 层, Phase 3 迁 model
        let defaults = UserDefaults.standard
        defaults.set(ViewMode.grid.rawValue, forKey: "viewModeRaw")
        defaults.set(true, forKey: "showSidebar")
        defaults.set(false, forKey: "showDetail")
        defaults.set(AccentColor.system.rawValue, forKey: "accentColorID")
        defaults.set(TrashRetentionDays.defaultValue.rawValue, forKey: "trashRetentionDays")
        defaults.set(AppearanceMode.defaultValue.rawValue, forKey: "appearanceMode")
        defaults.set(200.0, forKey: "thumbnailSize")  // V5.30: 240 → 200
        defaults.set("all", forKey: "sidebarSelection")
        defaults.set(SortOption.filenameAsc.rawValue, forKey: "sortOption")  // V5.31 default
        defaults.set(ThumbnailLayoutMode.defaultValue.rawValue, forKey: "thumbnailLayoutMode")
        defaults.set(220.0, forKey: "sidebarColumnWidth")
        defaults.set(360.0, forKey: "detailColumnWidth")
        // V5.55-2 scrollAnchorPhotoID 不在 reset 范围——是 per-window 状态, 不应被一键抹掉
    }
}

// MARK: - V4.50.0: 4 类设置子 View
//
// 设计：每类独立 View + @AppStorage 在子 View
//   优势：每类独立测试 + 维护，SettingsView 仅做 sidebar/detail 路由
//

// MARK: 通用（默认视图/排序/窗口）
// V5.57-1: 加"窗口"区 (2 toggle)——与菜单 ⌃⌘S/⌘I 同源, 设置文档化统一入口

private struct GeneralSettingsView: View {
    @AppStorage("viewModeRaw") private var defaultViewModeRaw: String = ViewMode.grid.rawValue
    @AppStorage("sortOption") private var defaultSortOption: String = SortOption.importedAtDesc.rawValue
    // V5.57-1: 窗口 2 toggle——与 ContentView.swift:147/151 同 key, 双向同步
    @AppStorage("showSidebar") private var showSidebar: Bool = true
    @AppStorage("showDetail") private var showDetail: Bool = false

    private let defaultViewModeOptions: [ViewMode] = ViewMode.allCases
    private let defaultSortOptions: [SortOption] = SortOption.allCases

    var body: some View {
        SettingsSection(title: "默认视图模式", subtitle: "启动应用时使用的图片显示布局") {
            Picker("视图模式", selection: $defaultViewModeRaw) {
                Text(Copy.viewModeGrid).tag(ViewMode.grid.rawValue)
                Text(Copy.viewModeList).tag(ViewMode.list.rawValue)
                Text(Copy.viewModeTimeline).tag(ViewMode.timeline.rawValue)
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

        // V5.57-1: 窗口 toggle——与菜单 ⌃⌘S / ⌘I 写同一 key, 即时生效
        SettingsSection(
            title: "窗口",
            subtitle: "控制侧栏和详情面板的显示。也可在「显示」菜单用 ⌃⌘S / ⌘I 切换。"
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle("显示侧栏", isOn: $showSidebar)
                Toggle("显示详情面板", isOn: $showDetail)
            }
        }
    }
}

// MARK: 外观（缩略图大小/缩略图布局/外观模式）
// V5.57-1: 加"缩略图布局"区 (方格/按比例)——之前仅 toolbar densityMenu 暴露

private struct AppearanceSettingsView: View {
    @AppStorage("thumbnailSize") private var defaultThumbnailSize: Double = 200  // V5.16: 170→200 行高
    // V5.57-1: thumbnailLayoutMode 从 toolbar 升入设置——用户单一入口
    @AppStorage("thumbnailLayoutMode") private var thumbnailLayoutModeRaw: Int = ThumbnailLayoutMode.defaultValue.rawValue
    @AppStorage("appearanceMode") private var appearanceModeRaw: Int = AppearanceMode.defaultValue.rawValue

    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .defaultValue },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    // V5.57-1: thumbnailLayoutMode Int → enum 双向 binding
    private var thumbnailLayoutModeBinding: Binding<ThumbnailLayoutMode> {
        Binding(
            get: { ThumbnailLayoutMode(rawValue: thumbnailLayoutModeRaw) ?? .defaultValue },
            set: { thumbnailLayoutModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        // V5.57-1: 缩略图布局——.square (1:1 裁切) / .squareFit (1:1 letterbox macOS Photos 真版)
        SettingsSection(
            title: "缩略图布局",
            subtitle: "方格：1:1 居中裁切（iOS Photos 风格）。按比例：1:1 letterbox 不裁切（macOS Photos 真版）。"
        ) {
            Picker("缩略图布局", selection: thumbnailLayoutModeBinding) {
                ForEach(ThumbnailLayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsSection(
            title: "缩略图大小",
            subtitle: "默认缩略图尺寸。拖动 slider 实时预览缩略图大小。当前会话用 toolbar 临时改的会在重启后恢复。"
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Slider(value: $defaultThumbnailSize, in: 100...250, step: 10)
                Text(Copy.thumbnailSizeLabel(Int(defaultThumbnailSize)))
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
                // V5.57-2: 实时预览——SF Symbol 按 size 缩放
                ThumbnailSizePreview(size: $defaultThumbnailSize)
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

// MARK: 关于（V5.57-1 新增 6 类）
//
// macOS Photos.app 习惯——About 放最末
// 内容：app 图标 + 名称 + 版本 + build + 版权 + 链接
// 版本号从 AppVersion.current 读（Bundle.main.infoDictionary + fallback）
//

private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // V5.57-1: 大图标 + 名称 + 版本号——居中
            HStack(alignment: .center, spacing: Spacing.lg) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("ImageGallery")
                        .font(Typography.title2)
                    Text(AppVersion.current.displayString)
                        .font(Typography.body)
                        .foregroundStyle(Surface.textSecondary)
                    Text("macOS 照片管理")
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                }
                Spacer()
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.panel, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            // V5.57-1: 链接行——占位 URL, Phase 4 可改
            SettingsSection(
                title: "链接",
                subtitle: nil
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Link(destination: URL(string: "https://github.com/")!) {
                        Label("项目主页", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/")!) {
                        Label("使用帮助", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://github.com/")!) {
                        Label("问题反馈", systemImage: "exclamationmark.bubble")
                    }
                }
            }

            // V5.57-1: 版权 + 致谢
            SettingsSection(
                title: "版权",
                subtitle: nil
            ) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("© 2026 ImageGallery")
                        .font(Typography.body)
                    Text("Built with SwiftUI + SwiftData")
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
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

// MARK: - 缩略图大小 slider 实时预览（V5.57-2）
//
// 100pt 固定容器内放 SF Symbol "photo" + scaleEffect
//   displayScale 范围 0.3..1.0——size=100 → 30pt, size=250 → 100pt
//   用 scaleEffect 而非 font size——SF Symbol 缩放不重设布局
//
// 用 SF Symbol 而非真样图:
//   - 零 file 依赖, 零 async load
//   - Phase 3 推 model.settings 改造时可换真 sample photo
//

private struct ThumbnailSizePreview: View {
    @Binding var size: Double

    var body: some View {
        ZStack {
            // V5.57-2: 灰底容器——预览区视觉边界
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "photo")
                .font(.system(size: 100))
                .scaleEffect(displayScale)
                .foregroundStyle(.secondary)
        }
        .frame(width: 100, height: 100)
        .help("实时预览缩略图大小")
    }

    /// V5.57-2: size 100..250 映射到 scale 0.3..1.0
    private var displayScale: Double {
        0.3 + (size - 100) / 150 * 0.7
    }
}
