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
        case .importedAtDesc:  return Copy.sortImportedDesc
        case .importedAtAsc:   return Copy.sortImportedAsc
        case .filenameAsc:     return Copy.sortFilenameAsc
        case .filenameDesc:    return Copy.sortFilenameDesc
        case .fileSizeDesc:    return Copy.sortFileSizeDesc
        case .fileSizeAsc:     return Copy.sortFileSizeAsc
        case .customOrder:     return Copy.sortCustomOrder
        }
    }

    /// 工具栏按钮上显示的简短标签
    var shortLabel: String {
        switch self {
        case .importedAtDesc, .importedAtAsc: return Copy.sortCategoryImportTime
        case .filenameAsc, .filenameDesc:     return Copy.sortCategoryFilename
        case .fileSizeDesc, .fileSizeAsc:     return Copy.sortCategoryFileSize
        case .customOrder:                    return Copy.sortCategoryCustom
        }
    }

    /// 方向箭头（用于工具栏按钮上的小图标）
    var directionIcon: String {
        switch self {
        case .importedAtDesc, .fileSizeDesc, .filenameDesc: return "arrow.down"
        case .importedAtAsc, .fileSizeAsc, .filenameAsc:    return "arrow.up"
        // V5.87: line.3.horizontal (3 条细线) 视觉重量不足, 跟 clock/externaldrive 实心 icon 不一致
        //   改 arrow.up.arrow.down (有'上下排'语义, 跟 asc/desc 主题一致, 视觉重量跟其他 icon 相当)
        case .customOrder:                                  return "arrow.up.arrow.down"
        }
    }

    /// V5.39.3: 工具栏按钮 SF Symbol——按字段类型 + 方向合成
    ///   排序菜单按钮的 image 跟着当前 sortOption 走 (ContentView 推)
    ///   - importedAt*: clock 暗示时间
    ///   - filename*: textformat
    ///   - fileSize*: externaldrive
    ///   - custom: arrow.up.arrow.down (V5.87: line.3.horizontal 视觉重量不足, 改 arrow.up.arrow.down)
    ///   V5.60-2: filenameAsc/Desc 之前共用 textformat (无方向暗示)——改 size.larger/.smaller 区分
    ///   desc = 大先 (Z→A) → textformat.size.larger; asc = 小先 (A→Z) → textformat.size.smaller
    ///   其他 desc 加 .fill, asc 不加 (跟 Photos 工具栏 sort 按钮一致)
    var toolbarIcon: String {
        switch self {
        case .importedAtDesc:  return "clock.fill"
        case .importedAtAsc:   return "clock"
        case .filenameDesc:    return "textformat.size.larger"  // V5.60-2: 大写先 Z→A
        case .filenameAsc:     return "textformat.size.smaller"  // V5.60-2: 小写先 A→Z
        case .fileSizeDesc:    return "externaldrive.fill"
        case .fileSizeAsc:     return "externaldrive"
        case .customOrder:     return "arrow.up.arrow.down"  // V5.87: 视觉重量跟其他 icon 一致
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

    /// V4.37.1: 是否日期相关排序——驱动 PhotoGridView 是否显示日期分组表头
    ///   true:  importedAtDesc/Asc  → 显示 "今天/昨天/本周/..." 段头
    ///   false: filename/size/custom → 平铺一个 LazyVGrid，不分组
    /// 理由: 按字母/大小排序时，日期段头会切碎字母顺序/大小顺序的连续浏览节奏
    var isDateBased: Bool {
        switch self {
        case .importedAtDesc, .importedAtAsc:
            return true
        case .filenameAsc, .filenameDesc, .fileSizeDesc, .fileSizeAsc, .customOrder:
            return false
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
