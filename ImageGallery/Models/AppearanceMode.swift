//
//  AppearanceMode.swift
//  ImageGallery
//
//  V3.6.22 NEW: 应用外观模式（macOS 标准三选）
//  - .system: 跟随系统设置
//  - .light:  强制浅色
//  - .dark:   强制深色
//
//  跟 SwiftUI .preferredColorScheme() 集成：
//  - .system → 传 nil（不覆盖系统）
//  - .light / .dark → 传对应 ColorScheme
//

import SwiftUI

enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// 映射到 SwiftUI ColorScheme（.system → nil，让系统决定）
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 持久化默认值（首次安装：跟随系统）
    static var defaultValue: AppearanceMode { .system }
}
