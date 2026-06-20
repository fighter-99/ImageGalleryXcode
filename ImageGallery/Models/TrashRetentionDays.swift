//
//  TrashRetentionDays.swift
//  ImageGallery
//
//  V3.6 NEW: 回收站自动清理时长配置
//

import Foundation

/// V3.6 NEW: 回收站自动清理时长配置
/// 1/7/30/90 天，默认 30 天（在 SettingsView 里可改）
enum TrashRetentionDays: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }
    /// V6.37.1: 走 Copy.trashRetentionDays(days:) — printf %lld 而非 Swift 字符串插值
    ///   之前 "\(rawValue) 天" 直接 Swift 字面拼接, zh-Hant 不能改 word order
    var displayName: String { Copy.trashRetentionDays(rawValue) }

    static var defaultValue: TrashRetentionDays { .thirtyDays }
}
