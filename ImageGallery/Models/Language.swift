//
//  Language.swift
//  ImageGallery
//
//  V6.12.16 NEW: App 支持语言选项——简体中文 / 繁體中文 / English
//
//  设计: UserSettings.language 持久化到 UserDefaults, ImageGalleryApp root view 用
//    .environment(\.locale, ...) 切 app locale, 所有 Text + Formatter + String(localized:)
//    自动跟随.
//

import Foundation

/// V6.12.16: 用户可选的 app 语言
///
/// Locale identifier 跟 Apple 标准 BCP 47 一致:
/// - .zhHans: zh-Hans (简体中文)
/// - .zhHant: zh-Hant (繁體中文)
/// - .en:    en       (English)
///
/// 加新语言: 加 case + displayName + localeId + String Catalog 翻译列即可
enum Language: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en    = "en"

    var id: String { rawValue }

    /// V6.12.16: Locale identifier (BCP 47)——给 .environment(\.locale, Locale(identifier:)) 用
    var localeId: String { rawValue }

    /// V6.12.16: Settings picker 显示名——本语言用本地化字符串, 别的语言用本语言的 displayName
    ///   .zhHans picker label = "简体中文"
    ///   .zhHant picker label = "繁體中文"
    ///   .en    picker label = "English"
    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:    return "English"
        }
    }
}
