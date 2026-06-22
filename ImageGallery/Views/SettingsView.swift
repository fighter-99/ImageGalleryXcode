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
    static let titleSubtitleGap: CGFloat = Spacing.sm
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
    // V6.70: 删 showingResetOnboardingConfirm — OnboardingView 取消
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
    // V6.XX: 键盘焦点导航——标记侧栏和内容区为独立 focus section
    @FocusState private var focusedCategory: SettingsCategory?

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
        HSplitView {
            // 左侧类别侧栏（macOS 标准 Preferences 布局）
            List(selection: selectedCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.title, systemImage: category.icon)
                        .tag(category)
                        .help("\(category.title) — \(category.subtitle)")
                }
            }
           .listStyle(.sidebar)
           .frame(minWidth: 160, idealWidth: 210)
            .focusSection()

            // 右侧内容区
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(selectedCategory.wrappedValue.title)
                            .font(Typography.headline)
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
                                // V6.70: 删 onResetOnboarding 参数 — OnboardingView 取消
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
            .focusSection()
        }
        .frame(
            // HSplitView 侧栏布局需要更宽的默认尺寸
            minWidth: 640, idealWidth: 800,
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
            // macOS System Settings 风格：分组背景容器
            Group {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
}
}
