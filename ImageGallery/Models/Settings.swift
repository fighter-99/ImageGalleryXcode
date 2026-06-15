//
//  Settings.swift
//  ImageGallery
//
//  V5.52-2: 12 个 @AppStorage 镜像到 @Observable class
//  原因: @AppStorage 是 SwiftUI DynamicProperty, 不能放在非 View 类里
//  View 保留 @AppStorage 作为 source of truth (兼容外部写: ImageGalleryApp menu / SettingsView)
//  Model 通过 Binding 同步到 Settings 字段, didSet 写回 UserDefaults
//
//  命名: SwiftUI 自带 Settings scene (ImageGalleryApp.swift:92 用作 `Settings { SettingsView() }`),
//  所以本类改名 UserSettings, 但 ContentViewModel 里 `var settings = UserSettings()` 字段仍叫 settings (调用点短)
//
//  注意: @Observable macro 只支持 class 不支持 struct, 所以 UserSettings 是 final class
//  (而不是 @Observable struct 拷贝值语义——我们需要引用语义让 view 订阅变化)
//

import Foundation
import SwiftUI

/// V5.52: 12 个 UserDefaults 键的 @Observable 镜像
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
}
