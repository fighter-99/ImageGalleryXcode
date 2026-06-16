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
    private let onError: (Error) -> Void

    init(
        storage: PhotoStorage = .shared,
        modelContext: ModelContext,
        onError: ((Error) -> Void)? = nil
    ) {
        self.storage = storage
        self.modelContext = modelContext
        self.onError = onError ?? { _ in }
    }

    /// 把 photo 移到回收站
    /// - 设置 trashedAt = Date()（文件保留在 Photos/ 目录原位，避免额外 IO）
    /// - 立即持久化到 SwiftData
    /// V5.13: 失败通过 onError 上抛（默认 no-op = 向后兼容 8 处旧 call site）
    func recycle(_ photo: Photo) {
        photo.trashedAt = Date()
        modelContext.saveWithLog(onError: onError)
    }

    /// 从回收站恢复
    /// V5.13: 失败通过 onError 上抛
    func restore(_ photo: Photo) {
        photo.trashedAt = nil
        modelContext.saveWithLog(onError: onError)
    }

    /// 永久删除一个 photo（文件 + SwiftData 记录）
    /// V5.13: 文件删失败 → onError；SwiftData save 失败 → onError
    ///   （之前 try? + silent saveWithLog——数据丢失风险）
    /// V6.08: 文件删失败后提前 return——不删 SwiftData 记录, 保留 photo 让用户能重试
    ///   之前 catch 后继续 delete(photo) → 文件还在盘上但 DB 记录没了 = 孤儿文件
    ///   重试也找不到这条 photo (UI 看不到), 永久占空间
    func purge(_ photo: Photo) {
        do {
            try storage.delete(photoURL: photo.fileURL)
        } catch {
            onError(error)
            return  // V6.08: 文件没删成, 保留 DB 记录等下次重试
        }
        modelContext.delete(photo)
        modelContext.saveWithLog(onError: onError)
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
