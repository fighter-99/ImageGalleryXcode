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

// MARK: - V6.01: 节奏统一常量
//
// V6.01: 统一 3 个 SettingsView 内部常量, 之前散在 7+ 处, 改一处全跟
//   - labelColumnWidth: 80pt (label 80pt 左 + control 右 对齐 Photos 偏好设置)
//   - 之前 LibrarySettingsView 用 60pt, 跟 General/Appearance 不齐
//   - titleSubtitleGap: 8pt (V5.45 13 token 体系的 Spacing.sm)
//   - 之前用字面量 4, 跨 Spacing.xs/sm 节奏跳跃
//
// 暂不抽到 DesignTokens.swift——只 SettingsView 用, 后续 ContentView 复用再 promote
private enum SettingsMetrics {
    static let labelColumnWidth: CGFloat = 80
    static let titleSubtitleGap: CGFloat = Spacing.sm
}

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
    /// V6.07: 全部加 .fill (solid)——视觉重量统一
    ///   之前 mix: gearshape/paintbrush/trash 看起来更重, paintpalette/info.circle 看起来更轻
    ///   (gearshape 齿多视觉密度高, paintbrush 单线视觉密度低)
    ///   改 .fill 后 5 个 icon 都是 solid, 视觉重量齐整——sidebar 类别一眼能扫
    ///   跟 macOS Sonoma+ System Settings sidebar 范式一致
    var icon: String {
        switch self {
        case .general:    return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .library:    return "trash.fill"
        case .accent:     return "paintpalette.fill"
        case .about:      return "info.circle.fill"
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

    private var selectedCategory: Binding<SettingsCategory> {
        Binding(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general },
            set: { selectedCategoryRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            // V5.93: 侧边栏始终可见——删窗口可隐藏功能 (Photos 偏好设置范式)
            //   .navigationSplitViewColumnWidth 加 fixed 240pt (跟 Photos 接近, 紧凑)
            // V5.98: 删 sidebar 搜索框——macOS Photos 偏好设置范式无 search, 5 个 category
            //   加搜索是过度设计 (V5.92), 占视觉空间且隐藏 .about (用户报告 4 个 category)
            List(SettingsCategory.allCases, selection: selectedCategory) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
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
            // V6.00: 改 minWidth/Height → idealWidth/Height + maxHeight——给 Settings 窗口合理默认尺寸
            //   之前 minWidth: 480, minHeight: 360 让窗口能拉到 1500+pt 高 (用户报告), 大量空白
            //   改 idealHeight: 580, maxHeight: 720——窗口自动 size-to-content
            //   跟 macOS Photos 偏好设置范式一致 (Photos 也是固定 ~580pt 高)
            .frame(
                minWidth: 640, idealWidth: 760,
                minHeight: 480, idealHeight: 580, maxHeight: 720
            )
        }
        .navigationTitle("设置")
        // V5.93: 加 toolbar——Reset All + Help (Photos 偏好设置主操作入口)
        //   之前 Reset All 在内嵌 detail 底部, 跟用户距离远; 现在放 toolbar 1-click
        // V6.06: placement .primaryAction → .automatic——macOS 14+ Settings scene
        //   .primaryAction 渲染不稳定 (用户报告 4 张截图都看不到 toolbar)
        //   .automatic 让 SwiftUI 自动选 placement, Settings scene 兼容更好
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    settings.reset()
                } label: {
                    Label("恢复全部为默认", systemImage: "arrow.counterclockwise")
                }
                .help("恢复全部设置为默认")
            }
            ToolbarItem(placement: .automatic) {
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

    // V6.04: 删 defaultViewModeOptions——视图模式搬到外观跟缩略图布局合并
    private let defaultSortOptions: [SortOption] = SortOption.allCases

    var body: some View {
        // V5.95: HStack label 左 / control 右——Photos 偏好设置范式
        //   之前 Picker 占整 row 宽, 像表单; 现在 label 左 + control 右 紧凑
        // V6.04: 删"默认视图模式"section——搬到外观跟"缩略图布局"合并
        //   之前 视图模式(grid/list/timeline) 跟 缩略图布局(square/squareFit) 拆 2 个 section
        //   概念重叠 (都关于图片显示), 跨 通用/外观 2 个 page 不便对照

        SettingsSection(
            title: "默认排序",
            subtitle: "启动时图片按以下规则排序"
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("排序")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Picker("", selection: $settings.sortOption) {
                    ForEach(defaultSortOptions) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()  // V5.95: menu picker 不撑满, 留 trailing 视觉缓冲
            }
        }
        // V6.04: 通用 page 只剩"默认排序"1 个 section——视图模式搬到外观
        //   IA 角度: 排序跟内容组织有关, 留在通用; 显示模式/布局跟外观有关, 搬走
    }
}

// MARK: 外观（缩略图大小/缩略图布局/外观模式）
// V5.57-1: 加"缩略图布局"区 (方格/按比例)——之前仅 toolbar densityMenu 暴露
// V5.58-1: 改用 @Bindable UserSettings——去 3 个 @AppStorage 双写

private struct AppearanceSettingsView: View {
    // V5.58-1: @Bindable UserSettings 单一真相源——替换 3 个 @AppStorage
    @Bindable var settings: UserSettings

    var body: some View {
        // V6.04: 合并"视图模式"(从通用搬来) + "缩略图布局"为 1 个 section
        //   之前 2 个独立 section, 跨 page (通用/外观) 不便对照
        //   现在 1 section 2 Picker——视图模式 (grid/list/timeline) + 布局 (方格/按比例)
        //   概念都是 '启动时的图片显示', 合并更紧凑
        SettingsSection(
            title: "默认视图",
            subtitle: "启动应用时的图片排列方式和缩略图形状。视图模式决定整体布局, 布局决定单个 cell 形状。"
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("视图模式")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Picker("", selection: $settings.viewModeRaw) {
                    Text(Copy.viewModeGrid).tag(ViewMode.grid.rawValue)
                    Text(Copy.viewModeList).tag(ViewMode.list.rawValue)
                    Text(Copy.viewModeTimeline).tag(ViewMode.timeline.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("布局")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Picker("", selection: $settings.thumbnailLayoutMode) {
                    ForEach(ThumbnailLayoutMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }

        SettingsSection(
            title: "缩略图大小",
            subtitle: "默认缩略图尺寸。拖动 slider 实时预览缩略图大小。当前会话用 toolbar 临时改的会在重启后恢复。"
        ) {
            // V6.02: 拆 2 行——slider row + preview row
            //   之前 1 行放 slider + 40pt 数字 + 100pt preview + spacer, 总宽 ~400pt
            //   跟其他 section 'label 80pt + control 撑满' 节奏不齐, trailing 也不齐
            //   现在: slider row 跟其他 section 同节奏 (label + slider + 数字)
            //         preview row 居中 100x100, 视觉重心独立
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("大小")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Slider(value: $settings.thumbnailSize, in: 100...250, step: 10)
                Text(Copy.thumbnailSizeLabel(Int(settings.thumbnailSize)))
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
                Spacer()
            }
            // V6.02: 预览挪到独立行——label column 80pt 占位 (跟其他 row 同节奏)
            HStack(alignment: .center, spacing: Spacing.md) {
                Color.clear.frame(width: SettingsMetrics.labelColumnWidth)  // 占位对齐 slider row
                // V5.57-2: 实时预览——SF Symbol 按 size 缩放
                // V5.99: card 背景 + 1pt 描边——暗色可见
                ThumbnailSizePreview(size: $settings.thumbnailSize)
            }
        }

        SettingsSection(
            title: "外观",
            subtitle: "应用整体外观。\u{201C}跟随系统\u{201D} 会随 macOS 切换自动调整。"
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("外观")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Picker("", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
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
        // V6.03: 删外层 VStack 包装——之前 VStack(spacing: .sm) 让 2 toggle 行有 8pt gap
        //   跟 导出/自动清理 section 的 2 HStack back-to-back 节奏不齐
        //   改: 2 HStack 直列 (0pt gap), 跟 导出/自动清理 节奏统一
        //   Text 用 .frame(maxWidth: .infinity) 撑满左侧, Toggle 推到 trailing
        //   跟其他 section 不同: 此处 label 不固定 80pt (label 6+ 中文字 80pt 装不下)
        SettingsSection(
            title: "导入",
            subtitle: "拖入或选择文件夹导入图片时的默认行为。"
        ) {
            HStack {
                Text("导入时自动去重").frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $settings.autoDeduplicate).labelsHidden()
            }
            HStack {
                Text("导入时生成缩略图").frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $settings.autoGenerateThumbnails).labelsHidden()
            }
        }

        // V5.90: 导出——默认导出格式/质量
        // V5.95: HStack label 左 / control 右
        SettingsSection(
            title: "导出",
            subtitle: "导出图片时的默认格式和质量。"
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("格式")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Picker("", selection: $settings.defaultExportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(alignment: .center, spacing: Spacing.md) {
                Text("质量")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Slider(value: $settings.defaultExportQuality, in: 0.5...1.0, step: 0.05)
                Text("\(Int(settings.defaultExportQuality * 100))%")
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 40, alignment: .trailing)
                Spacer()  // V5.95: trailing Spacer 防 slider 撑满 row
            }
        }

        // V5.58-1: 自动清理——回收站保留时长
        SettingsSection(
            title: "自动清理",
            subtitle: "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。"
        ) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Text("保留时长")
                    .frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Picker("", selection: $settings.trashRetentionDays) {
                    ForEach(TrashRetentionDays.allCases) { days in
                        Text(days.displayName).tag(days.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer()
            }
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
            subtitle: "选择应用的主色调，影响按钮、选中状态、链接等。"
        ) {
            // V6.03: 5 → 3 列——9 colors ÷ 3 = 3 行整, 之前 5 列末行 4 colors 残缺
            //   3 列 × 3 行 = 9 cells, 视觉方阵, 无空白 cell
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3),
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
// V5.98: 删 onReset 闭包 + "重置本节"按钮——macOS Photos 偏好设置**没有**这按钮
//   之前 V5.92 加的 per-section reset 是过度设计, 暗色下还不可见 (.secondary 跟背景同色)
//   全局重置保留在 toolbar "恢复全部为默认" 按钮 (V5.93) — 主操作入口
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
            // V5.98: 删右上角"重置本节"按钮 + onReset HStack——title/subtitle 直接左对齐
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
// V5.99: 修暗色下完全不可见问题——.quaternary 暗色 ≈ 背景, .secondary SF Symbol 也暗
//   改 Surface.cardBackground + 1pt cardBorder 描边, icon 改 .primary
//   Photos 范式: 预览框跟 .searchable bg 视觉重量一致, 边界明确

private struct ThumbnailSizePreview: View {
    @Binding var size: Double

    var body: some View {
        ZStack {
            // V5.99: card 背景 + 1pt 边框——暗色下视觉边界明确
            //   之前 .quaternary 暗色 ≈ 背景色, 100x100 box 看不见
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Surface.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Surface.cardBorder, lineWidth: 1)
                }
            Image(systemName: "photo")
                .font(.system(size: 100))
                .scaleEffect(displayScale)
                .foregroundStyle(.primary)  // V5.99: 暗色下也清晰可见
        }
        .frame(width: 100, height: 100)
        .help("实时预览缩略图大小")
    }

    /// V5.57-2: size 100..250 映射到 scale 0.3..1.0
    private var displayScale: Double {
        0.3 + (size - 100) / 150 * 0.7
    }
}
