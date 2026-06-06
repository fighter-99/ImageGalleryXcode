//
//  SortOption.swift
//  ImageGallery
//
//  排序方式（Eagle 化工具栏引入）。
//  7 种排序 = 3 个字段 × 2 个方向 + 1 自定义顺序。Menu 下拉单选。
//

import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    // 导入时间
    case importedAtDesc   // ↓ 最新优先（默认）
    case importedAtAsc    // ↑ 最早优先

    // 文件名
    case filenameAsc      // A → Z
    case filenameDesc     // Z → A

    // 文件大小
    case fileSizeDesc     // ↓ 最大的优先
    case fileSizeAsc      // ↑ 最小的优先

    // V3.5.D: 手动拖拽排序（按 photo.sortOrder 升序）
    case customOrder

    var id: String { rawValue }

    /// 菜单中显示的标签（含方向箭头）
    var label: String {
        switch self {
        case .importedAtDesc:  return "导入时间 ↓"
        case .importedAtAsc:   return "导入时间 ↑"
        case .filenameAsc:     return "文件名 A → Z"
        case .filenameDesc:    return "文件名 Z → A"
        case .fileSizeDesc:    return "文件大小 ↓"
        case .fileSizeAsc:     return "文件大小 ↑"
        case .customOrder:     return "自定义顺序"
        }
    }

    /// 工具栏按钮上显示的简短标签
    var shortLabel: String {
        switch self {
        case .importedAtDesc, .importedAtAsc: return "导入时间"
        case .filenameAsc, .filenameDesc:     return "文件名"
        case .fileSizeDesc, .fileSizeAsc:     return "文件大小"
        case .customOrder:                    return "自定义"
        }
    }

    /// 方向箭头（用于工具栏按钮上的小图标）
    var directionIcon: String {
        switch self {
        case .importedAtDesc, .fileSizeDesc, .filenameDesc: return "arrow.down"
        case .importedAtAsc, .fileSizeAsc, .filenameAsc:    return "arrow.up"
        case .customOrder:                                  return "line.3.horizontal"
        }
    }

    /// 切换方向（同字段的 asc ↔ desc），用于 ⌘⇧S 快捷键
    var toggledDirection: SortOption {
        switch self {
        case .importedAtDesc: return .importedAtAsc
        case .importedAtAsc:  return .importedAtDesc
        case .filenameAsc:    return .filenameDesc
        case .filenameDesc:   return .filenameAsc
        case .fileSizeDesc:   return .fileSizeAsc
        case .fileSizeAsc:    return .fileSizeDesc
        case .customOrder:    return .customOrder
        }
    }

    /// 对 [Photo] 数组排序（直接 mutate in place 不符合函数式风格，但调用方会丢弃原数组）
    func apply(to photos: [Photo]) -> [Photo] {
        switch self {
        case .importedAtDesc:
            return photos.sorted { $0.importedAt > $1.importedAt }
        case .importedAtAsc:
            return photos.sorted { $0.importedAt < $1.importedAt }
        case .filenameAsc:
            return photos.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        case .filenameDesc:
            return photos.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedDescending }
        case .fileSizeDesc:
            return photos.sorted { $0.fileSize > $1.fileSize }
        case .fileSizeAsc:
            return photos.sorted { $0.fileSize < $1.fileSize }
        case .customOrder:
            return photos.sorted { $0.sortOrder < $1.sortOrder }
        }
    }
}
