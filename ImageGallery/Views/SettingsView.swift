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
// V5.58-1: 接收 UserSettings 实例, 4 个子 View 改用 @Bindable 直接绑 UserSettings
//   (去掉子 view 的 @AppStorage 双写, 改用 $settings.xxx Binding)

struct SettingsView: View {
    // V5.58-1: 接收注入的 UserSettings 实例——从 ImageGalleryApp Settings scene 传过来
    //   不是 @State 不是 @Environment——是普通的 let (init 时拿到引用即可)
    let settings: UserSettings

    // V5.57-2: @SceneStorage 持久化类别选择 (scope = scene, 不是 app)
    //   同时开 2 个 ImageGallery 窗口各自记忆——photos.app Settings scene 同模式
    //   字符串 (rawValue) 而非 enum——@SceneStorage 不直接支持 enum
    @SceneStorage("settingsSelectedCategoryRaw") private var selectedCategoryRaw: String = SettingsCategory.general.rawValue

    // V5.92: search 文本状态——sidebar 顶部搜索框过滤 categories
    @State private var searchText: String = ""

    private var selectedCategory: Binding<SettingsCategory> {
        Binding(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general },
            set: { selectedCategoryRaw = $0.rawValue }
        )
    }

    /// V5.92: search 过滤后的 categories (空查询显示全部)
    private var filteredCategories: [SettingsCategory] {
        guard !searchText.isEmpty else { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter { category in
            category.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            // V5.92: sidebar 顶部加 search field——过滤 categories
            //   输入文字时实时过滤, 清空恢复全部
            // V5.93: 侧边栏始终可见——删窗口可隐藏功能 (Photos 偏好设置范式)
            //   .navigationSplitViewColumnWidth 加 fixed 240pt (跟 Photos 接近, 紧凑)
            VStack(spacing: 0) {
                List(filteredCategories, selection: selectedCategory) { category in
                    Label(category.title, systemImage: category.icon)
                        .tag(category)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "搜索设置")
        } detail: {
            // V5.89: 拆 cards → fluid rows——detail 改 ScrollView 包 VStack(spacing: Spacing.xxl)
            //   之前每个 section 是大卡片 (背景 + padding + 圆角),看着像表单
            //   改成 fluid rows (无 card 背景, photos.app 偏好设置风格)
            //   padding 统一在外层 (Spacing.xl),section 之间 Spacing.xxl 24pt 留白
            // V5.93: 删 slide-left 动画 (.move edge: .trailing)——改 fade only (.opacity)
            //   Photos 偏好设置范式: 切 category 是 fade, 无 slide (iOS 风格)
            // V5.93: Reset 按钮从内嵌 detail 底部移到 toolbar (主操作入口)
            // V5.94: spacing xxl(24pt) → lg(16pt)——Photos 偏好设置实际节奏, 紧凑
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Group {
                        switch selectedCategory.wrappedValue {
                        case .general:
                            GeneralSettingsView(settings: settings)
                        case .appearance:
                            AppearanceSettingsView(settings: settings)
                        case .library:
                            LibrarySettingsView(settings: settings)
                        case .accent:
                            AccentSettingsView(settings: settings)
                        case .about:
                            AboutSettingsView()
                        }
                    }
                    .id(selectedCategory.wrappedValue)  // V4.55.0: 强制 SwiftUI 视为不同视图（transition 关键）
                    .transition(.opacity)  // V5.93: 删 .move(edge: .trailing)——fade only, Photos 范式
                    .animation(Animations.standard, value: selectedCategory.wrappedValue)  // V4.55.0: 驱动 transition
                }
                .padding(Spacing.xl)  // V5.89: 统一外层 padding
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 480, minHeight: 360)  // V5.89: 略放大 (480 跟 Photos 接近)
        }
        .navigationTitle("设置")
        // V5.93: 加 toolbar——Reset All + Help (Photos 偏好设置主操作入口)
        //   之前 Reset All 在内嵌 detail 底部, 跟用户距离远; 现在放 toolbar 1-click
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    settings.reset()
                } label: {
                    Label("恢复全部为默认", systemImage: "arrow.counterclockwise")
                }
                .help("恢复全部设置为默认")
            }
            ToolbarItem(placement: .primaryAction) {
                Link(destination: URL(string: "https://github.com/")!) {
                    Label("帮助", systemImage: "questionmark.circle")
                }
                .help("使用帮助")
            }
        }
    }
}

// MARK: - V4.50.0: 4 类设置子 View
//
// 设计：每类独立 View + @AppStorage 在子 View
//   优势：每类独立测试 + 维护，SettingsView 仅做 sidebar/detail 路由
//

// MARK: 通用（默认视图/排序）
// V5.57-1: 加"窗口"区 (2 toggle)——与菜单 ⌃⌘S/⌘I 同源, 设置文档化统一入口
// V5.90: 删"窗口"区——跟 菜单"显示"重复, 改用菜单 ⌃⌘S / ⌘I 切换即可
// V5.58-1: 改用 @Bindable UserSettings——去 4 个 @AppStorage 双写

private struct GeneralSettingsView: View {
    // V5.58-1: @Bindable 让 $settings.xxx 直接是 Binding<T>——SwiftUI 标准 pattern
    @Bindable var settings: UserSettings

    private let defaultViewModeOptions: [ViewMode] = ViewMode.allCases
    private let defaultSortOptions: [SortOption] = SortOption.allCases

    var body: some View {
        SettingsSection(
            title: "默认视图模式",
            subtitle: "启动应用时使用的图片显示布局",
            onReset: { settings.resetGeneral() }
        ) {
            Picker("视图模式", selection: $settings.viewModeRaw) {
                Text(Copy.viewModeGrid).tag(ViewMode.grid.rawValue)
                Text(Copy.viewModeList).tag(ViewMode.list.rawValue)
                Text(Copy.viewModeTimeline).tag(ViewMode.timeline.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsSection(
            title: "默认排序",
            subtitle: "启动时图片按以下规则排序",
            onReset: { settings.resetGeneral() }
        ) {
            Picker("排序", selection: $settings.sortOption) {
                ForEach(defaultSortOptions) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        // V5.92: 2 sections 都共用 resetGeneral()——视图模式 + 默认排序
        // V5.90: 删"窗口"section——showSidebar/showDetail toggle 跟菜单"显示"重复
    }
}

// MARK: 外观（缩略图大小/缩略图布局/外观模式）
// V5.57-1: 加"缩略图布局"区 (方格/按比例)——之前仅 toolbar densityMenu 暴露
// V5.58-1: 改用 @Bindable UserSettings——去 3 个 @AppStorage 双写

private struct AppearanceSettingsView: View {
    // V5.58-1: @Bindable UserSettings 单一真相源——替换 3 个 @AppStorage
    @Bindable var settings: UserSettings

    var body: some View {
        // V5.57-1: 缩略图布局——.square (1:1 裁切) / .squareFit (1:1 letterbox macOS Photos 真版)
        // V5.58-1: Picker 直接绑 $settings.thumbnailLayoutMode (Int)——通过 .tag(Int) 路由
        // V5.92: 3 sections 都共用 resetAppearance()——一次重置布局/大小/外观
        SettingsSection(
            title: "缩略图布局",
            subtitle: "方格：1:1 居中裁切（iOS Photos 风格）。按比例：1:1 letterbox 不裁切（macOS Photos 真版）。",
            onReset: { settings.resetAppearance() }
        ) {
            Picker("缩略图布局", selection: $settings.thumbnailLayoutMode) {
                ForEach(ThumbnailLayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsSection(
            title: "缩略图大小",
            subtitle: "默认缩略图尺寸。拖动 slider 实时预览缩略图大小。当前会话用 toolbar 临时改的会在重启后恢复。",
            onReset: { settings.resetAppearance() }
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Slider(value: $settings.thumbnailSize, in: 100...250, step: 10)
                Text(Copy.thumbnailSizeLabel(Int(settings.thumbnailSize)))
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
                // V5.57-2: 实时预览——SF Symbol 按 size 缩放
                ThumbnailSizePreview(size: $settings.thumbnailSize)
            }
        }

        SettingsSection(
            title: "外观",
            subtitle: "应用整体外观。\u{201C}跟随系统\u{201D} 会随 macOS 切换自动调整。",
            onReset: { settings.resetAppearance() }
        ) {
            Picker("外观", selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: 图库（导入/导出/自动清理）
// V5.58-1: 改用 @Bindable UserSettings——去 @AppStorage("trashRetentionDays")
// V5.90: 加"导入" + "导出"区——平衡 IA (单 section 类别显得空)

private struct LibrarySettingsView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        // V5.90: 导入——默认从哪个文件夹导入
        // V5.92: 3 sections 都共用 resetLibrary()——一次重置导入/导出/清理
        SettingsSection(
            title: "导入",
            subtitle: "拖入或选择文件夹导入图片时的默认行为。",
            onReset: { settings.resetLibrary() }
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle("导入时自动去重", isOn: $settings.autoDeduplicate)
                Toggle("导入时生成缩略图", isOn: $settings.autoGenerateThumbnails)
            }
        }

        // V5.90: 导出——默认导出格式/质量
        SettingsSection(
            title: "导出",
            subtitle: "导出图片时的默认格式和质量。",
            onReset: { settings.resetLibrary() }
        ) {
            Picker("格式", selection: $settings.defaultExportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .center, spacing: Spacing.md) {
                Text("质量")
                    .frame(width: 60, alignment: .leading)
                Slider(value: $settings.defaultExportQuality, in: 0.5...1.0, step: 0.05)
                Text("\(Int(settings.defaultExportQuality * 100))%")
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }

        // V5.58-1: 自动清理——回收站保留时长
        SettingsSection(
            title: "自动清理",
            subtitle: "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。",
            onReset: { settings.resetLibrary() }
        ) {
            Picker("保留时长", selection: $settings.trashRetentionDays) {
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
// V5.58-1: 改用 @Bindable UserSettings——去 @AppStorage("accentColorID")

private struct AccentSettingsView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        SettingsSection(
            title: "强调色",
            subtitle: "选择应用的主色调，影响按钮、选中状态、链接等。",
            onReset: { settings.resetAccent() }
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 5),
                spacing: Spacing.md
            ) {
                ForEach(AccentColor.allCases) { accent in
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

// MARK: 关于（V5.57-1 新增 6 类）
//
// macOS Photos.app 习惯——About 放最末
// 内容：app 图标 + 名称 + 版本 + build + 版权 + 链接
// 版本号从 AppVersion.current 读（Bundle.main.infoDictionary + fallback）
// V5.91: 重构——小图标 (96→48) + 删 card 背景 (跟其他 detail 一致 fluid rows)

private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            // V5.91: 重构——48x48 小图标 + name + version, 删 96x96 大图标 + card bg
            SettingsSection(title: "应用信息", subtitle: nil) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ImageGallery")
                            .font(Typography.headline)
                        Text(AppVersion.current.displayString)
                            .font(Typography.caption)
                            .foregroundStyle(Surface.textSecondary)
                    }
                }
            }

            // V5.91: 链接行——占位 URL, Phase 4 可改
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

            // V5.91: 版权 + 致谢
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
// V5.89: 改 fluid rows——删 card 背景 + padding, 仿 macOS Photos 偏好设置风格
//   之前: title/subtitle + content 在 Surface.panel 卡片里 (padding.lg + Radius.md 圆角)
//   现在: title/subtitle + content 无背景, padding 由外层 ScrollView .padding(Spacing.xl) 统一
//   section 之间 Spacing.xxl 24pt 留白 (Photos.app 同节奏)
// V5.92: 加 onReset 闭包——右上角 ghost button "重置本节", 调 settings.resetXxx()
// V5.94: 加 flashTrigger 闭包——reset 后 section 闪淡黄 bg 0.5s 提示'已重置'
//   父 sub-view 持 @State flashTrigger, 每次 onReset 时 += 1 触发 onChange
private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let onReset: (() -> Void)?
    let onResetFlash: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        onReset: (() -> Void)? = nil,
        onResetFlash: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onReset = onReset
        self.onResetFlash = onResetFlash
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // V5.92: title 跟 onReset 按钮同行——title 左,reset 按钮右 (右对齐)
            HStack(alignment: .top) {
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
                Spacer()
                // V5.92: 右上角 ghost button "重置本节"——macOS Photos 偏好设置范式
                if let onReset = onReset {
                    Button("重置本节", action: onReset)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // V5.89: 删 .padding(Spacing.lg) 和 .background(Surface.panel, ...)——fluid rows
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
