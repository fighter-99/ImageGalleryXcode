//
//  FilterState.swift
//  ImageGallery
//
//  V4.36.x: 工具栏筛选按钮的 4 维筛选配置
//  - folders / tags / shapes（多选 Set）
//  - minRating（单值 0-5；0 = 无筛选，1-5 = ≥N 星）
//
//  筛选语义：
//  - 维度内 OR（如 folder=[A,B] → A 或 B）
//  - 维度间 AND（folder A + tag #x + 横图 + ≥4 星 → 必须全部满足）
//
//  持久化：session-only，不写 UserDefaults / SwiftData
//  关闭 app 后清空——本次会话内保留
//
//  设计：struct + 值类型（与 SelectionState 同款模式）
//

import Foundation

struct FilterState: Equatable, Hashable {
    var folders: Set<UUID> = []
    var tags: Set<UUID> = []
    var shapes: Set<PhotoShape> = []
    /// 0 = 无评分筛选；1-5 = ≥N 星
    var minRating: Int = 0

    static let empty = FilterState()

    /// 任一维度非空
    var isActive: Bool {
        !folders.isEmpty || !tags.isEmpty || !shapes.isEmpty || minRating > 0
    }

    /// chip 数 = 工具栏角标数
    /// rating 是单值所以 +0 或 +1
    var activeCount: Int {
        folders.count + tags.count + shapes.count + (minRating > 0 ? 1 : 0)
    }

    /// 单 chip 维度枚举（用于 ActiveFiltersBar × 删除）
    enum Dimension: Equatable, Hashable {
        case folder(UUID)
        case tag(UUID)
        case shape(PhotoShape)
        case rating  // 单值；× 直接清 0
    }

    /// 反向删除单 chip
    mutating func remove(_ dim: Dimension) {
        switch dim {
        case .folder(let id): folders.remove(id)
        case .tag(let id): tags.remove(id)
        case .shape(let s): shapes.remove(s)
        case .rating: minRating = 0
        }
    }

    /// 清空全部
    mutating func removeAll() {
        self = .empty
    }
}
