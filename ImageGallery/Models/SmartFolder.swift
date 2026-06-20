//
//  SmartFolder.swift
//  ImageGallery
//
//  P4.1 NEW: 用户自定义智能文件夹 (Photos.app Smart Album 范式)
//  - 用户在 sidebar 创建, 命名 + 选 filter 组合
//  - sidebar 列出所有 SmartFolder, 点击激活 (sidebarSelection = .smartFolder(uuid))
//  - filter 存 JSON (FilterState 编码), 跟现有 filter UI 复用
//
//  设计要点:
//  - @Model SwiftData 持久化 (跟 Folder / Tag 同层)
//  - 简单字段: id / name / iconName / filterData / order / createdAt
//  - 不用 @Relationship (filter 是值, 不引用其他 @Model)
//  - 排序: order 升序, 同 order 按 createdAt
//

import Foundation
import SwiftData

@Model
final class SmartFolder: Identifiable {
    /// V1 强制 UUID, 别用 UUID() 兜底 (存 .persistentIdentifier 也可以, 但 UUID 更显式)
    @Attribute(.unique) var id: UUID

    /// 用户起的名字 (e.g. "Family 2024", "Best Landscapes")
    var name: String

    /// SF Symbol name (e.g. "star.fill", "heart.fill", "photo.stack")
    ///  V1 限定 SF Symbol, 不让用户传任意字符串 (避免拼错)
    var iconName: String

    /// filter criteria JSON 编码 (FilterState Codable)
    ///  V1 存完整 FilterState, 跟现有 filter UI 1:1 — 复用 FilterState.filtered() 逻辑
    ///  未来 V2 可以加 SmartFolder 专属 filter (如 "在 folder X 中" 等更细的)
    var filterData: Data

    /// sidebar 显示顺序 (越小越前)
    var order: Int

    /// 创建时间 (排序 tiebreaker)
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "star.fill",
        filterState: FilterState = .empty,
        order: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        // V1: 用 JSONEncoder 编码 FilterState — Codable 自动实现 (Equatable + 各字段 Codable)
        self.filterData = (try? JSONEncoder().encode(filterState)) ?? Data()
        self.order = order
        self.createdAt = createdAt
    }

    /// 解码 filterData → FilterState (失败返 .empty, 不 crash)
    var decodedFilter: FilterState {
        guard !filterData.isEmpty,
              let state = try? JSONDecoder().decode(FilterState.self, from: filterData) else {
            return .empty
        }
        return state
    }

    /// 更新 filter (写回 JSON)
    func updateFilter(_ newFilter: FilterState) {
        self.filterData = (try? JSONEncoder().encode(newFilter)) ?? Data()
    }
}

// MARK: - V1 SF Symbol 限定 (P4.1 起步)

/// V1 允许用户选的 SF Symbol (避免拼错)
enum SmartFolderIcon: String, CaseIterable, Identifiable {
    case star = "star.fill"
    case heart = "heart.fill"
    case flame = "flame.fill"
    case leaf = "leaf.fill"
    case starCircle = "star.circle.fill"
    case heartCircle = "heart.circle.fill"
    case bookmark = "bookmark.fill"
    case tag = "tag.fill"
    case folder = "folder.fill"
    case photoStack = "photo.stack.fill"
    case sun = "sun.max.fill"
    case moon = "moon.fill"
    case sparkle = "sparkles"

    var id: String { rawValue }

    /// 显示名 (UI 提示用, V6.37.4 走 Copy)
    var displayName: String {
        switch self {
        case .star: return Copy.smartFolderIconStar
        case .heart: return Copy.smartFolderIconHeart
        case .flame: return Copy.smartFolderIconFlame
        case .leaf: return Copy.smartFolderIconLeaf
        case .starCircle: return Copy.smartFolderIconStarCircle
        case .heartCircle: return Copy.smartFolderIconHeartCircle
        case .bookmark: return Copy.smartFolderIconBookmark
        case .tag: return Copy.smartFolderIconTag
        case .folder: return Copy.smartFolderIconFolder
        case .photoStack: return Copy.smartFolderIconPhotoStack
        case .sun: return Copy.smartFolderIconSun
        case .moon: return Copy.smartFolderIconMoon
        case .sparkle: return Copy.smartFolderIconSparkle
        }
    }
}
