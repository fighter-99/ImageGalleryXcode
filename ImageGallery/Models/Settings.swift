//
//  Settings.swift
//  ImageGallery
//
//  V5.52-2: 12 个 @AppStorage 镜像到 @Observable class
//  原因: @AppStorage 是 SwiftUI DynamicProperty, 不能放在非 View 类里
//  View 保留 @AppStorage 作为 source of truth (兼容外部写: ImageGalleryApp menu / SettingsView)
//  Model 通过 Binding 同步到 Settings 字段, didSet 写回 UserDefaults
//
//  V5.58-1: 加 init() 从 UserDefaults 读 13 字段——修 V5.52-2 漏的 init-from-UserDefaults
//    之前 UserSettings 永远从硬编码默认开始, 必须 ContentView L512-523 push 才能拿到持久化值
//    现在 init() 一次性从 UserDefaults 读, model 变成真正的 in-memory source of truth
//    SettingsView 子 View 改用 @Bindable UserSettings, 不再需要 @AppStorage 双写
//
//  命名: SwiftUI 自带 Settings scene (ImageGalleryApp.swift:92 用作 `Settings { SettingsView() }`),
//  所以本类改名 UserSettings, 但 ContentViewModel 里 `var settings = UserSettings()` 字段仍叫 settings (调用点短)
//
//  注意: @Observable macro 只支持 class 不支持 struct, 所以 UserSettings 是 final class
//  (而不是 @Observable struct 拷贝值语义——我们需要引用语义让 view 订阅变化)
//

import Foundation
import SwiftUI

/// V5.52: 13 个 UserDefaults 键的 @Observable 镜像 (V5.58-1 加 init() 从 UserDefaults 读)
/// - View 持有 @AppStorage (source of truth) → 推到 model.settings via Binding
/// - Settings 字段被改时 didSet 写回 UserDefaults (双写保持外部兼容)
/// - Future V5.52 String Catalog 时: 直接换 NSLocalizedString fallback
@MainActor
@Observable
final class UserSettings {
    // V6.12 收尾 ②: UserDefaults 实例注入——测试传 isolated suite 防污染
    //   默认 .standard (生产), 测试 `UserSettings(defaults: isolatedSuite)` 自隔离
    //   didSet 通过 self.defaults 写回, 不再硬编码 UserDefaults.standard
    private let defaults: UserDefaults

    // MARK: - 12 个 @AppStorage 镜像 (key 跟 ContentView 对齐, 防止脱节)

    /// V3.6.13: viewMode 改用 @AppStorage 持久化 (SettingsView 可设默认)
    /// ContentView @AppStorage("viewModeRaw") = ViewMode.grid.rawValue
    var viewModeRaw: String = ViewMode.grid.rawValue {
        didSet { defaults.set(viewModeRaw, forKey: "viewModeRaw") }
    }

    /// V3.6.13: 侧栏可见性 (ImageGalleryApp 菜单 ⌃⌘S 写)
    var showSidebar: Bool = true {
        didSet { defaults.set(showSidebar, forKey: "showSidebar") }
    }

    /// V3.6.13: 详情面板可见性 (ImageGalleryApp 菜单 ⌃⌘D / ⌘I 写)
    /// V5.60-1: 默认 true (V5.22 改 false, V5.60-1 改回 true——用户要求"详情面板常驻")
    ///   老用户 @AppStorage 已有 stored showDetail=false 不动 (仅新装/重置生效)
    ///   手动 ⌘I / ⌘⌃D / titlebar 按钮仍可 toggle——不锁死
    var showDetail: Bool = true {
        didSet { defaults.set(showDetail, forKey: "showDetail") }
    }

    /// V3.6.13: 强调色 (SettingsView AccentSettingsView 写)
    var accentColorID: String = AccentColor.system.rawValue {
        didSet { defaults.set(accentColorID, forKey: "accentColorID") }
    }

    /// V3.6.13: 回收站保留天数 (SettingsView LibrarySettingsView 写)
    var trashRetentionDays: Int = TrashRetentionDays.defaultValue.rawValue {
        didSet { defaults.set(trashRetentionDays, forKey: "trashRetentionDays") }
    }

    /// V3.6.22: 外观模式 (SettingsView AppearanceSettingsView 写)
    var appearanceMode: Int = AppearanceMode.defaultValue.rawValue {
        didSet { defaults.set(appearanceMode, forKey: "appearanceMode") }
    }

    /// V5.30: 240 → 200 默认 (Photos 真版密度); SettingsView slider 写
    var thumbnailSize: Double = 200 {
        didSet { defaults.set(thumbnailSize, forKey: "thumbnailSize") }
    }

    /// V3.6.13: 侧栏选中项 (跟 sidebarSelection @AppStorage 同步)
    var sidebarSelection: String = "all" {
        didSet { defaults.set(sidebarSelection, forKey: "sidebarSelection") }
    }

    /// V5.31: importedAtDesc → filenameAsc 默认
    var sortOption: String = SortOption.filenameAsc.rawValue {
        didSet { defaults.set(sortOption, forKey: "sortOption") }
    }

    /// V5.17: 缩略图布局模式 (方格/按比例)
    var thumbnailLayoutMode: Int = ThumbnailLayoutMode.defaultValue.rawValue {
        didSet { defaults.set(thumbnailLayoutMode, forKey: "thumbnailLayoutMode") }
    }

    /// 侧栏列宽持久化
    var sidebarColumnWidth: Double = 220 {
        didSet { defaults.set(sidebarColumnWidth, forKey: "sidebarColumnWidth") }
    }

    // MARK: - V5.90: 导入/导出偏好 (平衡 LibrarySettingsView IA)

    /// V5.90: 导入时自动去重 (跳过已存在的图片, 跟导入流程 import 钩子用)
    var autoDeduplicate: Bool = true {
        didSet { defaults.set(autoDeduplicate, forKey: "autoDeduplicate") }
    }

    /// V5.90: 导入时生成缩略图
    var autoGenerateThumbnails: Bool = true {
        didSet { defaults.set(autoGenerateThumbnails, forKey: "autoGenerateThumbnails") }
    }

    /// V5.90: 默认导出格式 (jpg/png/heic)
    var defaultExportFormat: String = ExportFormat.defaultValue.rawValue {
        didSet { defaults.set(defaultExportFormat, forKey: "defaultExportFormat") }
    }

    /// V5.90: 默认导出质量 (0.5..1.0)
    var defaultExportQuality: Double = 0.9 {
        didSet { defaults.set(defaultExportQuality, forKey: "defaultExportQuality") }
    }

    // MARK: - V6.21.0 (Phase 1.1 UX polish): 用户偏好 — 是否显示过 marquee hint

    /// V6.21.0: 是否已显示过 marquee selection hint
    ///   true = 已显示 (用户看过或 dismiss 过), 永久隐藏
    ///   false = 第一次启动 + 库有内容 + selection 空 → 显示 floating hint
    var hasShownMarqueeHint: Bool = false {
        didSet { defaults.set(hasShownMarqueeHint, forKey: "hasShownMarqueeHint") }
    }

    // MARK: - V6.22.3 (P2 #10): 是否显示过 onboarding 3-card sheet
    ///   true = 已看过 (用户点 "开始使用" / "跳过" / 已 dismiss 过)
    ///   false = 首次启动 → 弹 OnboardingView
    ///   Settings reset() 也清零 (跟 hasShownMarqueeHint 同步)
    var hasSeenOnboarding: Bool = false {
        didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") }
    }

    /// 详情列宽持久化
    var detailColumnWidth: Double = 360 {
        didSet { defaults.set(detailColumnWidth, forKey: "detailColumnWidth") }
    }

    // MARK: - V5.55-2: P0 滚动位置保留
    // 存当前 ScrollView 顶部可见 photo 的 UUID——下次启动恢复
    // macOS Photos.app 标准行为:重新打开图库后保留滚动位置
    var scrollAnchorPhotoID: String? = nil {
        didSet { defaults.set(scrollAnchorPhotoID, forKey: "scrollAnchorPhotoID") }
    }

    // MARK: - V6.12.16: App 语言选项 (简体中文 / 繁體中文 / English)
    //   ImageGalleryApp 读 settings.language 调 .environment(\.locale, ...)
    //   所有 SwiftUI Text + Formatter + String(localized:) 自动跟随
    //   V6.12.17 迁移 Copy dict 到 NSLocalizedString 后, 所有 UI 文案会按 language 切换
    var language: String = Language.zhHans.rawValue {
        didSet { defaults.set(language, forKey: "language") }
    }

    // V6.12.16: computed language enum——typed access 比 rawValue 字符串好用
    var appLanguage: Language {
        get { Language(rawValue: language) ?? .zhHans }
        set { language = newValue.rawValue }
    }

    // MARK: - V5.58-1: init() 从 UserDefaults 读 13 字段
    //
    // V5.52-2 漏的 init-from-UserDefaults——之前 UserSettings 永远从硬编码默认开始,
    // 必须 ContentView L512-523 一次性 push @AppStorage → model.settings 才能拿到持久化值.
    //
    // 现在 init() 一次性读 UserDefaults, UserSettings 变成 in-memory source of truth.
    // didSet 在 init 内不触发 (Swift 语义), 所以 field declaration 默认值 + init 覆盖赋值是安全的.
    //
    // scrollAnchorPhotoID 是 String? —— 空字符串当 nil 处理避免脏数据
    //
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 12 个键值——用 object(forKey:) + 类型转换, 缺字段或类型不匹配 fallback 到 field 默认
        if let stored = defaults.string(forKey: "viewModeRaw") {
            self.viewModeRaw = stored
        }
        if defaults.object(forKey: "showSidebar") != nil {
            self.showSidebar = defaults.bool(forKey: "showSidebar")
        }
        if defaults.object(forKey: "showDetail") != nil {
            self.showDetail = defaults.bool(forKey: "showDetail")
        }
        if let stored = defaults.string(forKey: "accentColorID") {
            self.accentColorID = stored
        }
        if defaults.object(forKey: "trashRetentionDays") != nil {
            self.trashRetentionDays = defaults.integer(forKey: "trashRetentionDays")
        }
        if defaults.object(forKey: "appearanceMode") != nil {
            self.appearanceMode = defaults.integer(forKey: "appearanceMode")
        }
        if defaults.object(forKey: "thumbnailSize") != nil {
            self.thumbnailSize = defaults.double(forKey: "thumbnailSize")
        }
        if let stored = defaults.string(forKey: "sidebarSelection") {
            self.sidebarSelection = stored
        }
        if let stored = defaults.string(forKey: "sortOption") {
            self.sortOption = stored
        }
        if defaults.object(forKey: "thumbnailLayoutMode") != nil {
            self.thumbnailLayoutMode = defaults.integer(forKey: "thumbnailLayoutMode")
        }
        if defaults.object(forKey: "sidebarColumnWidth") != nil {
            self.sidebarColumnWidth = defaults.double(forKey: "sidebarColumnWidth")
        }
        if defaults.object(forKey: "detailColumnWidth") != nil {
            self.detailColumnWidth = defaults.double(forKey: "detailColumnWidth")
        }
        // V5.90: 4 个导入/导出偏好
        if defaults.object(forKey: "autoDeduplicate") != nil {
            self.autoDeduplicate = defaults.bool(forKey: "autoDeduplicate")
        }
        if defaults.object(forKey: "autoGenerateThumbnails") != nil {
            self.autoGenerateThumbnails = defaults.bool(forKey: "autoGenerateThumbnails")
        }
        if let stored = defaults.string(forKey: "defaultExportFormat") {
            self.defaultExportFormat = stored
        }
        if defaults.object(forKey: "defaultExportQuality") != nil {
            self.defaultExportQuality = defaults.double(forKey: "defaultExportQuality")
        }

        // V5.55-2 scrollAnchorPhotoID: 空字符串当 nil 处理
        if let stored = defaults.string(forKey: "scrollAnchorPhotoID"), !stored.isEmpty {
            self.scrollAnchorPhotoID = stored
        }

        // V6.12.16: language 从 UserDefaults 读——缺字段 fallback .zhHans
        if let stored = defaults.string(forKey: "language") {
            self.language = stored
        }
    }

    // MARK: - V5.58-2: reset() 恢复 12 字段到默认
    //
    // V5.57-1 inline UserDefaults 写代码迁到这里——单一真相源
    //   12 字段 (不重置 scrollAnchorPhotoID——per-window 状态, 不应被一键抹掉)
    //   复用 *.defaultValue (Models/{TrashRetentionDays,AppearanceMode,ThumbnailLayoutMode,AccentColor}.swift)
    //   inline literal 默认值与 ContentView.swift @AppStorage 声明对齐
    //   didSet 在 reset 内会触发 → 写回 UserDefaults (与 init 行为一致, didSet 不在 init 触发)
    //
    // V5.98: 删 V5.92 加的 4 个 per-section resetXxx() 方法——per-section reset UI 已删
    //   (SettingsSection 删 onReset 参数), 单一 reset() 由 toolbar "恢复全部为默认" 触发
    //
    func reset() {
        viewModeRaw = ViewMode.grid.rawValue
        showSidebar = true
        // V5.60-1: showDetail 默认改为 true, reset 也回到 true
        showDetail = true
        accentColorID = AccentColor.system.rawValue
        trashRetentionDays = TrashRetentionDays.defaultValue.rawValue
        appearanceMode = AppearanceMode.defaultValue.rawValue
        thumbnailSize = 200.0  // V5.30: 240 → 200
        sidebarSelection = "all"
        sortOption = SortOption.filenameAsc.rawValue  // V5.31 default
        thumbnailLayoutMode = ThumbnailLayoutMode.defaultValue.rawValue
        sidebarColumnWidth = 220.0
        detailColumnWidth = 360.0
        // V6.12.16: language 也 reset 到默认 (.zhHans)
        language = Language.zhHans.rawValue
        defaultExportQuality = 0.9
        // V6.21.4 (audit fix #3): hasShownMarqueeHint 也 reset — "恢复全部为默认" 应该包括 UX hint flag
        //   之前 reset 漏掉, 用户清空库后无法重新触发 MarqueeHintView (audit #5 related)
        hasShownMarqueeHint = false
        // V6.22.3 (P2 #10): hasSeenOnboarding 也 reset — 让用户重新看 onboarding (跟 marquee hint 同步)
        hasSeenOnboarding = false
        // scrollAnchorPhotoID 不在 reset 范围——是 per-window 状态
    }
}
