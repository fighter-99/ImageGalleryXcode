//
//  AccentColor.swift
//  ImageGallery
//
//  V3.5.D：用户可配置的应用强调色枚举。
//
//  设计意图：
//  - 1 个 "跟随系统" + 8 个预设色 = 9 个 case
//  - rawValue 是 UserDefaults 持久化键（@AppStorage("accentColorID")），
//    绝对不能改，否则老用户设置会丢失
//  - color 用 NSColor.systemXxx 然后转 Color，跟随系统明暗自适应
//
//  ⚠️ rawValue 和 case 顺序由 AccentColorTests 锁定为契约。
//  任何重命名/重排都必须同步修改测试。
//

import SwiftUI
import AppKit

enum AccentColor: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite

    var id: String { rawValue }

    /// 用户可见的中文名（SettingsView 中显示）
    var displayName: String {
        switch self {
        case .system:   return "跟随系统"
        case .blue:     return "蓝色"
        case .purple:   return "紫色"
        case .pink:     return "粉色"
        case .red:      return "红色"
        case .orange:   return "橙色"
        case .yellow:   return "黄色"
        case .green:    return "绿色"
        case .graphite: return "石墨色"
        }
    }

    /// SwiftUI Color。.system 跟随系统设置；其余用 NSColor 系统色（自动适配明暗自适应）
    var color: Color {
        let nsColor: NSColor
        switch self {
        case .system:   return Color.accentColor
        case .blue:     nsColor = .systemBlue
        case .purple:   nsColor = .systemPurple
        case .pink:     nsColor = .systemPink
        case .red:      nsColor = .systemRed
        case .orange:   nsColor = .systemOrange
        case .yellow:   nsColor = .systemYellow
        case .green:    nsColor = .systemGreen
        case .graphite: nsColor = .systemGray
        }
        return Color(nsColor)
    }
}
