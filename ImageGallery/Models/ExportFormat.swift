//
//  ExportFormat.swift
//  ImageGallery
//
//  V5.90 NEW: 导出图片格式 enum——UserSettings.defaultExportFormat 镜像
//    3 选项: jpg (兼容性最好) / png (无损, 大文件) / heic (高效压缩, Apple 生态)
//
//  镜像模式同 SortOption / ThumbnailLayoutMode——rawValue 是 String 存 UserDefaults
//

import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Hashable {
    case jpg
    case png
    case heic

    var id: String { rawValue }

    /// V5.90: 默认 jpg——兼容性最好 (所有系统/应用/浏览器)
    static let defaultValue: ExportFormat = .jpg

    var displayName: String {
        switch self {
        case .jpg:  return "JPG"
        case .png:  return "PNG"
        case .heic: return "HEIC"
        }
    }

    /// V5.90: 文件扩展名 (无 dot)
    var fileExtension: String {
        switch self {
        case .jpg:  return "jpg"
        case .png:  return "png"
        case .heic: return "heic"
        }
    }
}
