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
    var displayName: String { "\(rawValue) 天" }

    static var defaultValue: TrashRetentionDays { .thirtyDays }
}
