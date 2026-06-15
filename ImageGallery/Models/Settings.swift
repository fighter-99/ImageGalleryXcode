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
    // MARK: - 12 个 @AppStorage 镜像 (key 跟 ContentView 对齐, 防止脱节)

    /// V3.6.13: viewMode 改用 @AppStorage 持久化 (SettingsView 可设默认)
    /// ContentView @AppStorage("viewModeRaw") = ViewMode.grid.rawValue
    var viewModeRaw: String = ViewMode.grid.rawValue {
        didSet { UserDefaults.standard.set(viewModeRaw, forKey: "viewModeRaw") }
    }

    /// V3.6.13: 侧栏可见性 (ImageGalleryApp 菜单 ⌃⌘S 写)
    var showSidebar: Bool = true {
        didSet { UserDefaults.standard.set(showSidebar, forKey: "showSidebar") }
    }

    /// V3.6.13: 详情面板可见性 (ImageGalleryApp 菜单 ⌃⌘D / ⌘I 写)
    var showDetail: Bool = false {
        didSet { UserDefaults.standard.set(showDetail, forKey: "showDetail") }
    }

    /// V3.6.13: 强调色 (SettingsView AccentSettingsView 写)
    var accentColorID: String = AccentColor.system.rawValue {
        didSet { UserDefaults.standard.set(accentColorID, forKey: "accentColorID") }
    }

    /// V3.6.13: 回收站保留天数 (SettingsView LibrarySettingsView 写)
    var trashRetentionDays: Int = TrashRetentionDays.defaultValue.rawValue {
        didSet { UserDefaults.standard.set(trashRetentionDays, forKey: "trashRetentionDays") }
    }

    /// V3.6.22: 外观模式 (SettingsView AppearanceSettingsView 写)
    var appearanceMode: Int = AppearanceMode.defaultValue.rawValue {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode") }
    }

    /// V5.30: 240 → 200 默认 (Photos 真版密度); SettingsView slider 写
    var thumbnailSize: Double = 200 {
        didSet { UserDefaults.standard.set(thumbnailSize, forKey: "thumbnailSize") }
    }

    /// V3.6.13: 侧栏选中项 (跟 sidebarSelection @AppStorage 同步)
    var sidebarSelection: String = "all" {
        didSet { UserDefaults.standard.set(sidebarSelection, forKey: "sidebarSelection") }
    }

    /// V5.31: importedAtDesc → filenameAsc 默认
    var sortOption: String = SortOption.filenameAsc.rawValue {
        didSet { UserDefaults.standard.set(sortOption, forKey: "sortOption") }
    }

    /// V5.17: 缩略图布局模式 (方格/按比例)
    var thumbnailLayoutMode: Int = ThumbnailLayoutMode.defaultValue.rawValue {
        didSet { UserDefaults.standard.set(thumbnailLayoutMode, forKey: "thumbnailLayoutMode") }
    }

    /// 侧栏列宽持久化
    var sidebarColumnWidth: Double = 220 {
        didSet { UserDefaults.standard.set(sidebarColumnWidth, forKey: "sidebarColumnWidth") }
    }

    /// 详情列宽持久化
    var detailColumnWidth: Double = 360 {
        didSet { UserDefaults.standard.set(detailColumnWidth, forKey: "detailColumnWidth") }
    }

    // MARK: - V5.55-2: P0 滚动位置保留
    // 存当前 ScrollView 顶部可见 photo 的 UUID——下次启动恢复
    // macOS Photos.app 标准行为:重新打开图库后保留滚动位置
    var scrollAnchorPhotoID: String? = nil {
        didSet { UserDefaults.standard.set(scrollAnchorPhotoID, forKey: "scrollAnchorPhotoID") }
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
    init() {
        let defaults = UserDefaults.standard

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

        // V5.55-2 scrollAnchorPhotoID: 空字符串当 nil 处理
        if let stored = defaults.string(forKey: "scrollAnchorPhotoID"), !stored.isEmpty {
            self.scrollAnchorPhotoID = stored
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
    func reset() {
        viewModeRaw = ViewMode.grid.rawValue
        showSidebar = true
        showDetail = false
        accentColorID = AccentColor.system.rawValue
        trashRetentionDays = TrashRetentionDays.defaultValue.rawValue
        appearanceMode = AppearanceMode.defaultValue.rawValue
        thumbnailSize = 200.0  // V5.30: 240 → 200
        sidebarSelection = "all"
        sortOption = SortOption.filenameAsc.rawValue  // V5.31 default
        thumbnailLayoutMode = ThumbnailLayoutMode.defaultValue.rawValue
        sidebarColumnWidth = 220.0
        detailColumnWidth = 360.0
        // scrollAnchorPhotoID 不在 reset 范围——是 per-window 状态
    }
}
