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
enum SettingsMetrics {
    static let labelColumnWidth: CGFloat = 80
    // V6.92.4: titleSubtitleGap Spacing.sm (8pt) → Spacing.xs (4pt)
    //   macOS Sonoma+ System Settings 真版 detail 顶部 title 跟 subtitle 间距约 4-6pt (紧凑)
    //   改 4pt 让 title 跟 subtitle 视觉"一体" (sub-header 风格), 跟真版一致
    static let titleSubtitleGap: CGFloat = Spacing.xs
}

// MARK: - V6.39.0 + V6.64.2: 关于页面链接 (占位 → 真实 GitHub URL)
// V6.64.2: 改 internal — 测试 Wave1A11yCrashTests 锁定 URL 防回退到 placeholder
enum SettingsLinks {
    // V6.64.2: 从占位 "github.com/" 改为 fighter-99/ImageGalleryXcode 真项目 URL
    //   跟 git remote origin 一致. 即使项目还没正式发布, 链接打开也是有效仓库 (404 之前是 better than placeholder)
    static let projectHomepage = "https://github.com/fighter-99/ImageGalleryXcode"
    static let helpDocs = "https://github.com/fighter-99/ImageGalleryXcode#readme"
    static let issueTracker = "https://github.com/fighter-99/ImageGalleryXcode/issues"
}

// MARK: - V6.39.0: 设置类别 (7 categories, 平衡密度)
// V6.90.0: 7 → 5 categories 合并 — 回收站并入图库, 快捷键并入通用
//   跟 macOS Sonoma+ System Settings 实际 5-6 categories 接近, segmented 视觉密度减 30%
//   跳: 快捷键走 menu (KeyboardShortcutsSheet 走 Help menu), 跟 macOS 真版一致
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general       // 通用: 启动默认值 + 双击行为 + 高级 actions + 快捷键 (V6.90 并入)
    case appearance    // 外观: 主题/强调色/字体大小
    case library       // 图库: 导入/导出 + 回收站 (V6.90 并入)
    case language      // 语言
    case about         // 关于

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return Copy.settingsCategoryGeneral
        case .appearance: return Copy.settingsCategoryAppearance
        case .library:    return Copy.settingsCategoryLibrary
        case .language:   return Copy.settingsCategoryLanguage
        case .about:      return Copy.settingsCategoryAbout
        }
    }

    /// V6.41: category 简短描述 — Photos 风格 detail 顶部大标题下方 subtitle
    var subtitle: String {
        switch self {
        case .general:    return Copy.settingsCategoryGeneralSubtitle
        case .appearance: return Copy.settingsCategoryAppearanceSubtitle
        case .library:    return Copy.settingsCategoryLibrarySubtitle
        case .language:   return Copy.settingsCategoryLanguageSubtitle
        case .about:      return Copy.settingsCategoryAboutSubtitle
        }
    }

    /// V6.86.4: macOS Sonoma+ System Settings / Photos Preferences 风格 SF Symbol — sidebar 类别 icon
    ///   全部 outline (non-fill) — 视觉锤跟系统 Settings 一致
    ///   原 V6.07 沿用全部 .fill (solid), light mode 视觉重量重, 跟 System Settings 真版对比露馅
    ///   现在 outline 细线, 选中态视觉锤用 Surface.selected 背景 (不用 icon 形状变化)
    /// V6.90.0: 删 .trash / .shortcuts case (合并后无)
    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintbrush"
        case .library:    return "photo.stack"
        case .language:   return "globe"
        case .about:      return "info.circle"
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
    // V6.70: 删 showingResetOnboardingConfirm — OnboardingView 取消
    @State private var showingEmptyTrashConfirm = false

    // V6.45: custom init — 用 settings.lastSettingsCategory 初始化 selectedCategoryRaw
    //   替代 @SceneStorage 默认值, 实现跨 app restart 记忆
    init(settings: UserSettings) {
        self.settings = settings
        self._selectedCategoryRaw = State(initialValue: settings.lastSettingsCategory)
    }

    // V6.86.2: 删 appearanceProgress @State — 之前 V6.51 加的 scale (0.98→1.0) + opacity 入场动画
    //   跟 macOS Sonoma+ System Settings / Photos Preferences 真版入场行为不一致
    //   Apple 系统级 Settings 窗口是系统自动 crossfade (无 scale), 主动写 scale 暴露"非真版"
    //   删 @State + 删 .scaleEffect/.opacity/.onAppear modifier — 走系统自动 crossfade
   @State private var showingShortcutsSheet = false
    // V6.87: 删 focusedCategory @FocusState — V6.49 加的"自动 focus 第一个 sidebar tab"
    //   现在是顶部 tab bar (button 模式), 不是 sidebar selection, 不需要 @FocusState 焦点管理
    //   tab bar 用户主动 hover/click 即触发 action, 无需 keyboard focus 自动落点

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
        // V6.87: NavigationSplitView → VStack(spacing: 0) — 取消 sidebar, 顶部 tab + 单列内容
        //   跟 macOS Sonoma+ System Settings Preferences 真版顶部 tab 模式一致
        //   VStack(spacing: 0) 让 tab bar 跟内容间无缝衔接 (跟 macOS 真版 Preferences 一致)
        //   保留 V6.86.0/1/2/3/4/5/6/8 全部 polish (Form+GroupBox / 28pt 大标题 / outline icon / 大底部呼吸 / asymmetric transition / About 页 help link)
        VStack(spacing: 0) {
            // 顶部 tab bar — 替代 V6.86 NavigationSplitView sidebar
            //   7 个 SettingsCategory 横排, ScrollView(.horizontal) 紧凑窗口可滚动
            //   ScrollViewReader 自动滚到选中 tab (V6.47 lesson)
            //   .background(.bar) 跟 macOS Sonoma+ System Settings 真版 toolbar 视觉一致 (V6.50)
            CategoryTabBar(selection: selectedCategory)

            // 内容区 (原 V6.86 detail ScrollView 整体保留)
            ScrollView {
                // V6.90.6: VStack spacing Spacing.md (12pt) → Spacing.lg (16pt)
                //   Form+GroupBox section 间间距 16pt 跟 macOS Sonoma+ System Preferences 多 section 页面视觉锤一致
                //   之前 12pt 紧凑, 视觉分组弱; 改 16pt 让每个 row + section 间视觉分组更清晰
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: SettingsMetrics.titleSubtitleGap) {
                        // V6.91.4: detail 顶部 chrome 简化 — 28pt semibold → .title2 (22pt regular)
                        //   原 V6.86.3 改 28pt semibold 跟 macOS Sonoma+ Photos Preferences 真版一致
                        //   但 macOS 真版 System Settings 顶部是 22pt regular (Photos 是 28pt — 两个真版不一致)
                        //   用户实测觉得装饰性过高, 跟 System Settings 路线 (顶部 segmented) 视觉不协调
                        //   改 .title2 (22pt regular) 视觉克制, 跟 segmented 24pt 高度比例协调
                        //   不加 Typography token (跟 V6.86.3 决策一致 — 22pt 是装饰性特殊)
                        Text(selectedCategory.wrappedValue.title)
                            .font(.title2)
                            .foregroundStyle(.primary)
                        // V6.91.4: subtitle 字号 caption (11pt) → body (13pt)
                        //   原 11pt 在 22pt title 下面视觉对比过强, 像 "title + tiny subtitle"
                        //   改 13pt 后 title 跟 subtitle 视觉层级更平滑 (22pt + 13pt 比例自然)
                        //   跟 macOS Sonoma+ System Settings 真版 detail 顶部 1:1
                        Text(selectedCategory.wrappedValue.subtitle)
                            .font(Typography.body)
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // V6.88.3: title 跟 subtitle 间距 Spacing.xs (4pt) → SettingsMetrics.titleSubtitleGap (Spacing.sm = 8pt)
                    //   28pt title + 11pt subtitle 之间需要更多呼吸空间 (真版约 6-10pt)
                    //   复用已有 SettingsMetrics.titleSubtitleGap = 8pt, 跟 AboutSettingsView 标题一致
                    //   整体 padding bottom Spacing.md (12pt) → Spacing.lg (16pt) — title 跟内容卡片视觉分组更清晰
                    .padding(.bottom, Spacing.lg)
                    Group {
                        switch selectedCategory.wrappedValue {
                        case .general:
                            GeneralSettingsView(
                                settings: settings,
                                // V6.70: 删 onResetOnboarding 参数 — OnboardingView 取消
                                onOpenDataFolder: openDataFolder,
                                onResetAll: { showingResetConfirm = true },
                                // V6.90.0: 加 onShowShortcuts — 快捷键 row 合并到通用
                                onShowShortcuts: { showingShortcutsSheet = true }
                            )
                        case .appearance:
                            AppearanceSettingsView(settings: settings)
                        case .library:
                            // V6.90.0: 加 onEmptyTrash — 回收站 row 合并到图库
                            LibrarySettingsView(
                                settings: settings,
                                onEmptyTrash: { showingEmptyTrashConfirm = true }
                            )
                        case .language:
                            LanguageSettingsView(settings: settings)
                        case .about:
                            AboutSettingsView()
                        }
                    }
                    .id(selectedCategory.wrappedValue)
                    // V6.91.2: 删 V6.86.8 加的 asymmetric scale + opacity transition (跟 macOS Sonoma+ System Settings 真版对齐)
                    //   V6.86.8 让切换 '浮上来' (scale 0.96→1.0 + opacity 0→1, 200ms ease-out)
                    //   但 macOS 真版 System Settings 切换 category 是即时切换 (无 transition, 无 scale)
                    //   主动写 transition 反而 '装', 不像 macOS 真版
                    //   删 .transition + .animation — 走 segmented 系统 widget 的即时切换
                    //   .id(selectedCategory) 保留 — 防止 SwiftUI 复用 view 状态 (跨 category)
                }
                // V6.86.6: 详情底部 32pt 呼吸空间 — 跟 macOS Sonoma+ System Settings 一致
                //   原来 .padding(Spacing.xl) 顶部/左右 20pt, 底部 20pt — 最后一行 row 贴窗底 20pt
                //   改后 .padding(.bottom, Spacing.xl + 32) = 52pt — 视觉呼吸
                //   (ScrollView 内 Spacer(minLength:) 不撑空间, 用 .padding 累加实现)
                // V6.88.3: .padding(.top, Spacing.xl) (20pt) → Spacing.xxl (24pt)
                //   tab bar 60pt + Divider 1pt → 内容顶部 24pt 视觉呼吸
                //   跟 macOS Sonoma+ System Settings 真版 detail 顶部距离一致 (24-28pt)
                // V6.90.5: .padding(.top, Spacing.xxl) (24pt) → Spacing.lg (16pt) — chrome 整合
                //   segmented 60pt + Divider tint 0.3 1pt → 内容顶部 16pt 视觉呼吸
                //   让 chrome 跟 detail 视觉上是一体, 跟 macOS Sonoma+ System Preferences 真版一致
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl + 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // V6.91.3: window minimum 540×420 视觉建议 — 跟 macOS Sonoma+ System Settings 真版一致
        //   原 V6.47 520×400 略小, segmented 5 categories 在 520pt 宽度可能挤
        //   改 540×420 让 segmented + 28pt title + section content 完美 fit
        //   SwiftUI Settings scene 自动管理 window 大小, .frame minWidth/minHeight 是视觉建议
        .frame(minWidth: 540, minHeight: 420)
        // V6.86.2: 删 V6.51 加的 .scaleEffect + .opacity + .onAppear window 入场动画
        //   macOS Sonoma+ System Settings / Photos Preferences 窗口入场是系统自动 crossfade
        //   主动写 scale (0.98→1.0) 反而暴露"非真版" — 让系统接管即可
        //   视觉对比: 打开 Settings 跟打开系统设置完全一致 (无 scale, 系统 crossfade)
        .navigationTitle(Copy.settingsTitle)
        // V6.86.5: 完全删 V6.41 加的右下角 ⓘ help 浮层 (10 行)
        //   原 V6.41 .overlay(alignment: .bottomTrailing) 是手画伪浮层, 跟 macOS Sonoma+ System Settings 真版风格不一致
        //   Apple System Settings 的 Help 是 About 页底部的 link row, 不是手画 widget
        //   删 .overlay — helpDocs 链接改在 About 页底部突出展示 (V6.86.5 AboutSettingsView 改)
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
        // V6.70: 删 Reset Onboarding alert — OnboardingView 取消
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


struct SettingsSection<Content: View>: View {
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
        // V6.92.2: VStack spacing Spacing.md (12pt) → Spacing.lg (16pt)
        //   section header 跟 Form 间距 12pt 偏紧, 跟 macOS Sonoma+ System Settings 真版 16-20pt 接近
        //   改 16pt 让 section header 跟 Form 视觉分组更清晰, 跟真版一致
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: SettingsMetrics.titleSubtitleGap) {
                // V6.92.1: section header 颜色克制 — accentColor → .primary
                //   V6.91.1 改 accentColor 跟 segmented 选中色统一 — 但 macOS 真版 System Settings
                //   section header 用 .primary (跟 row title 同色), 不用 accent
                //   改 .primary 让 section header 跟 PhotosSettingRadios.title (.primary) 颜色统一
                //   视觉更克制 (跟真版一致)
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // V6.86.1: macOS 14+ SwiftUI 原生 Form + GroupBox
            //   原手写 VStack + Color(nsColor: .controlBackgroundColor) + RoundedRectangle(8pt)
            //   改后 Form 自动用 Sonoma+ grouped 圆角 12pt + Material-based 背景
            //   跟 macOS Sonoma+ System Settings 真版容器像素级一致
            //   (Photos Preferences / System Settings / Xcode Preferences 都是 Form + GroupBox 模式)
            Form {
                GroupBox {
                    content()
                }
            }
            .formStyle(.grouped)  // macOS 14+ explicit grouped, 跟 Sonoma+ System Settings 一致
        }
    }
}

