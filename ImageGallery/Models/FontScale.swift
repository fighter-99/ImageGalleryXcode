//
//  FontScale.swift
//  ImageGallery
//
//  V6.33.1: Dynamic Type / 字体大小用户偏好
//    macOS 14+ SwiftUI Dynamic Type — 用户可调 4 档 (紧凑/默认/舒适/超大)
//    应用方式: ContentView body 顶层加 .environment(\.dynamicTypeSize, fontScale.toDynamicTypeSize())
//    只有用 semantic font (.body/.caption/.title 等) 的 Text 才会响应
//    当前 Typography token 多数 Font.system(size: X) — 不响应 (V6.34 慢慢迁)
//
//  设计理由:
//    macOS 没 iOS 那样的系统级 Dynamic Type UI 设置, 用户对 "系统默认太小/太大" 没直接反馈入口
//    加 in-app 字体大小偏好: 4 档可视化 (紧凑/默认/舒适/超大) + 对应 DynamicTypeSize
//    配合 .dynamicTypeSize 环境值, 已有 semantic font 的 view 立即响应
//

import SwiftUI

/// V6.33.1: 字体大小 4 档 — 对应 SwiftUI DynamicTypeSize
enum FontScale: String, CaseIterable, Identifiable, Hashable {
    /// 紧凑 (0.85x) — 信息密度高, 适合小窗口
    case compact
    /// 默认 (1.0x) — 系统默认大小
    case `default`
    /// 舒适 (1.15x) — 文字偏大, 阅读舒适
    case relaxed
    /// 超大 (1.3x) — 视障/老年用户
    case large

    var id: String { rawValue }

    /// 默认值 — 切换 settings 时用
    static var defaultValue: FontScale { .default }

    /// UI 显示名 (i18n, V6.37.1 走 Copy)
    var displayName: String {
        switch self {
        case .compact: return Copy.fontScaleCompact
        case .default: return Copy.fontScaleDefault
        case .relaxed: return Copy.fontScaleRelaxed
        case .large:   return Copy.fontScaleLarge
        }
    }

    /// SwiftUI DynamicTypeSize — 用于 .environment(\.dynamicTypeSize, ...)
    ///   4 档映射到 DynamicTypeSize 5 档中的 4 个 (medium 是默认)
    ///   compact → .small (小 1 档)
    ///   default → .medium (系统默认)
    ///   relaxed → .large (大 1 档)
    ///   large → .xLarge (大 2 档)
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact: return .small
        case .default: return .medium
        case .relaxed: return .large
        case .large:   return .xLarge
        }
    }
}
