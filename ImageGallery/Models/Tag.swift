//
//  Tag.swift
//  ImageGallery
//
//  标签数据模型。标签可以附加到任意图片上，用于多维度分类。
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String               // 标签名
    var colorHex: String           // 颜色（hex 格式，如 #FF6B6B）
    var createdAt: Date

    // 与 Photo 的反向关系：删除标签时，图片中的 tags 数组会自动移除该标签
    @Relationship(inverse: \Photo.tags)
    var photos: [Photo] = []

    init(name: String, colorHex: String = "#5B8FF9") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}

// ─── Color 扩展：从 hex 字符串创建颜色 ───
extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&rgb)

        let r, g, b, a: Double
        switch trimmed.count {
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255
            g = Double((rgb & 0x00FF0000) >> 16) / 255
            b = Double((rgb & 0x0000FF00) >> 8) / 255
            a = Double(rgb & 0x000000FF) / 255
        default:
            r = 0.4; g = 0.4; b = 0.9; a = 1  // 兜底蓝色
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

// 预设的标签颜色（用户新建标签时随机选一个）
enum TagColors {
    static let presets = [
        "#5B8FF9", "#5AD8A6", "#5D7092", "#F6BD16",
        "#E86452", "#6DC8EC", "#945FB9", "#FF9D4D",
        "#269A99", "#FF99C3"
    ]
}
