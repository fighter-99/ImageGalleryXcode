//
//  PhotoStats.swift
//  ImageGallery
//
//  V3.6.1：Photo 集合的统计纯函数。
//  设计为 enum + static func 而非 class/init：
//  - 无状态、无依赖 → 单元测试零成本
//  - 调用方 `PhotoStats.trashed(allPhotos)` 比 `PhotoStats().trashed(allPhotos)` 更轻
//  - 避免 `extension Collection where Element == Photo` 的链式 filter 多次中间数组分配
//

import Foundation

/// V3.6.1：Photo 集合的统计纯函数集合。
/// 所有方法都是 nonisolated static func，可在任何 actor 上调（包括测试）。
enum PhotoStats {

    // MARK: - 过滤

    /// 回收站中的照片（trashedAt != nil）
    static func trashed(_ photos: [Photo]) -> [Photo] {
        photos.filter(\.isInTrash)
    }

    /// 图库中的照片（trashedAt == nil）
    static func inLibrary(_ photos: [Photo]) -> [Photo] {
        photos.filter { !$0.isInTrash }
    }

    /// 收藏的图库照片（在图库 + isFavorite）
    static func favorites(_ photos: [Photo]) -> [Photo] {
        photos.filter(\.isFavorite)
    }

    /// 待整理照片（在图库 + folder == nil）
    static func unfiled(_ photos: [Photo]) -> [Photo] {
        photos.filter { $0.folder == nil && !$0.isInTrash }
    }

    // MARK: - 聚合

    /// 所有照片总占用字节数
    static func totalSize(_ photos: [Photo]) -> Int64 {
        photos.reduce(0) { $0 + $1.fileSize }
    }

    /// 回收站照片总占用字节数
    static func trashedSize(_ photos: [Photo]) -> Int64 {
        trashed(photos).reduce(0) { $0 + $1.fileSize }
    }
}
