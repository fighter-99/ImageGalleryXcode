//
//  Settings.swift
//  ImageGallery
//
//  V5.52-2: 12 个 @AppStorage 镜像到 @Observable class
//  原因: @AppStorage 是 SwiftUI DynamicProperty, 不能放在非 View 类里
//  View 保留 @AppStorage 作为 source of truth (兼容外部写: ImageGalleryApp menu / SettingsView)
//  Model 通过 Binding 同步到 Settings 字段, didSet 写回 UserDefaults
//
//  V5.52-1: 骨架 (空类); V5.52-2 填 12 个 var
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
    // V5.52-2 填充——12 个 @AppStorage 镜像
}
