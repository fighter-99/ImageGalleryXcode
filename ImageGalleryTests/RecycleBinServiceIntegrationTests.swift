//
//  RecycleBinServiceIntegrationTests.swift
//  ImageGalleryTests
//
//  V3.6 bug 调查：in-memory SwiftData 集成测试
//  验证 recycle 真的把 trashedAt 持久化 + fetch 能拿到
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

// V6.19.6 (P0 #18): 加 @Suite(.serialized) — 强制串行, 避免 ModelContainer 与其他 suite 并行创建冲突
@MainActor
@Suite(.serialized)
struct RecycleBinServiceIntegrationTests {

    /// 验证：recycle(photo) 后，立即 fetch 所有 photo ，
    /// 该 photo.trashedAt != nil 且在"过期候选"里
    @Test func recycleSetsTrashedAtAndIsFetchable() throws {
        // 1. 建 in-memory ModelContainer（与 ImageGalleryApp 同一 schema）
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext

        // 2. 插入一张 photo
        let photo = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RecycleBinTest_\(UUID().uuidString).jpg"),
            fileSize: 1000,
            width: 100,
            height: 100
        )
        context.insert(photo)
        try context.save()
        let photoID = photo.id

        // 3. recycle
        let service = RecycleBinService(storage: .shared, modelContext: context)
        service.recycle(photo)
        #expect(photo.trashedAt != nil, "recycle 后 photo.trashedAt 应非 nil")

        // 4. 重新 fetch（模拟 @Query 重新拉数据）
        let allPhotos = try context.fetch(FetchDescriptor<Photo>())
        let fetched = allPhotos.filter { $0.id == photoID }
        #expect(fetched.count == 1)
        #expect(fetched.first?.trashedAt != nil, "recycle 后 fetch 出来的 photo.trashedAt 应非 nil")

        // 5. 验证 cutoff 逻辑能找到
        let cutoff = Date().addingTimeInterval(86400)  // 未来 1 天 = 全都过期
        let eligible = RecycleBinService.itemsEligibleForPurge(among: fetched, cutoffDate: cutoff)
        #expect(eligible.count == 1, "应能找出回收站中的 photo")
    }

    /// 验证：restore 把 trashedAt 置 nil
    @Test func restoreClearsTrashedAt() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext

        let photo = Photo(
            filename: "t.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RecycleBinRestoreTest_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(photo)
        try context.save()

        let service = RecycleBinService(storage: .shared, modelContext: context)
        service.recycle(photo)
        #expect(photo.trashedAt != nil)

        service.restore(photo)
        #expect(photo.trashedAt == nil, "restore 后 trashedAt 应为 nil")
    }

    /// 验证：purge 真的删除 SwiftData 记录
    @Test func purgeRemovesPhotoFromContext() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext

        // V6.14.7: 真建临时文件 + defer cleanup — V6.08 设计 (跟 V6.13.1 permanentDelete 同根)
        //   purge 先删文件, 失败 → 保留 DB 记录让用户重试 (避免孤儿文件)
        //   之前用不存在的 /tmp 路径 → delete 失败 → DB 记录保留 → 测期待 "找不到" 失败
        //   production 不改, test 改跟 V6.13.1 一致
        let photoURL = URL(fileURLWithPath: "/tmp/RecycleBinPurgeTest_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: photoURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: photoURL) }

        let photo = Photo(
            filename: "p.jpg",
            fileURL: photoURL,
            fileSize: 0, width: 0, height: 0
        )
        context.insert(photo)
        try context.save()
        let photoID = photo.id

        let service = RecycleBinService(storage: .shared, modelContext: context)
        service.recycle(photo)
        service.purge(photo)

        let allPhotos = try context.fetch(FetchDescriptor<Photo>())
        let fetched = allPhotos.filter { $0.id == photoID }
        #expect(fetched.isEmpty, "purge 后 SwiftData 应找不到该 photo")
    }

    /// 验证：multiple photos 全部 recycle 后 fetch 都拿到 trashedAt
    @Test func recycleMultipleSetsAllTrashedAt() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext

        var photos: [Photo] = []
        for i in 0..<3 {
            let p = Photo(
                filename: "p\(i).jpg",
                fileURL: URL(fileURLWithPath: "/tmp/RB_\(i)_\(UUID().uuidString).jpg"),
                fileSize: 0, width: 0, height: 0
            )
            context.insert(p)
            photos.append(p)
        }
        try context.save()

        let service = RecycleBinService(storage: .shared, modelContext: context)
        for p in photos { service.recycle(p) }

        let allPhotos = try context.fetch(FetchDescriptor<Photo>())
        let trashed = allPhotos.filter { $0.trashedAt != nil }
        #expect(trashed.count == 3, "应有 3 张 trashed photo")
    }
}
