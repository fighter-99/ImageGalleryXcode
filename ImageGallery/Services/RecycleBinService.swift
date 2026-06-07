//
//  RecycleBinService.swift
//  ImageGallery
//
//  V3.6 NEW: 回收站服务
//  把"删除"改为"移到回收站"（软删），由用户或自动清理决定何时永久删除。
//
//  设计：
//  - recycle/restore/purge/purgeAll/purgeExpired 都标 @MainActor（SwiftData ModelContext 限制）
//  - itemsEligibleForPurge 是 static 纯函数（非 actor-isolated），方便测试 seam
//

import Foundation
import SwiftData

/// V3.6 NEW: 回收站服务
@MainActor
final class RecycleBinService {
    private let storage: PhotoStorage
    private let modelContext: ModelContext

    init(storage: PhotoStorage = .shared, modelContext: ModelContext) {
        self.storage = storage
        self.modelContext = modelContext
    }

    /// 把 photo 移到回收站
    /// - 设置 trashedAt = Date()（文件保留在 Photos/ 目录原位，避免额外 IO）
    /// - 立即持久化到 SwiftData
    func recycle(_ photo: Photo) {
        photo.trashedAt = Date()
        try? modelContext.save()
    }

    /// 从回收站恢复
    func restore(_ photo: Photo) {
        photo.trashedAt = nil
        try? modelContext.save()
    }

    /// 永久删除一个 photo（文件 + SwiftData 记录）
    func purge(_ photo: Photo) {
        // 先删文件（可能不存在，吞错）
        try? storage.delete(photoURL: photo.fileURL)
        // 再删 SwiftData 记录
        modelContext.delete(photo)
        try? modelContext.save()
    }

    /// 永久删除多个 photo
    func purgeAll(_ photos: [Photo]) {
        for photo in photos { purge(photo) }
    }

    /// 找出所有已过期的 photo（trashedAt < cutoffDate）
    /// 纯函数（非 actor-isolated），便于单元测试
    nonisolated static func itemsEligibleForPurge(
        among photos: [Photo], cutoffDate: Date
    ) -> [Photo] {
        photos.filter { photo in
            guard let trashedAt = photo.trashedAt else { return false }
            return trashedAt < cutoffDate
        }
    }

    /// app 启动时调用：删除所有超过 retentionDays 天的项
    func purgeExpired(retentionDays: Int) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        let eligible = Self.itemsEligibleForPurge(
            among: allTrashedPhotos(), cutoffDate: cutoff
        )
        for photo in eligible { purge(photo) }
    }

    private func allTrashedPhotos() -> [Photo] {
        let descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.trashedAt != nil })
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
