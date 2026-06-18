//
//  RecycleBinErrorPropagationTests.swift
//  ImageGalleryTests
//
//  V5.14: RecycleBinService.onError (V5.13 Day 5 加) 集成测试。
//  镜像 RecycleBinServiceIntegrationTests 的 in-memory ModelContainer 模式
//  + V5.13 Day 5 新增的 onError 错误传播路径。
//
//  V5.14 关键发现：Swift Testing + @MainActor struct 内 helper 方法（包括 static）
//  触发现有 test bundle 测试失败（V5.14 调试：inline 版同逻辑全过，helper 版全挂）。
//  治本：全 inline，不用 helper。DebugTest 验证此模式稳定。
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

// V6.19.6 (P0 #18): 加 @Suite(.serialized) — 强制串行, 避免 ModelContainer 与其他 suite 并行创建冲突
@MainActor
@Suite(.serialized)
struct RecycleBinErrorPropagationTests {
    // MARK: - purge 失败路径

    @Test func onErrorFiresOnPurgeWhenFileDeleteFails() throws {
        // 文件不存在 → PhotoStorage.delete 抛 PhotoStorageError.deleteFailed → onError
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RBE1_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var capturedError: Error?
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { capturedError = $0 }
        )
        service.purge(p)
        #expect(capturedError != nil, "删不存在文件应触发 onError")
    }

    @Test func onErrorCapturesPhotoStorageErrorType() throws {
        // 验 error 是 PhotoStorageError 类型——能 downcast
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RBE2_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var captured: PhotoStorageError?
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { error in captured = error as? PhotoStorageError }
        )
        service.purge(p)
        #expect(captured != nil, "onError 应捕获 PhotoStorageError")
    }

    // MARK: - 成功路径

    @Test func onErrorNotFiredOnSuccessfulRecycle() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RBE3_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var fired = false
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { _ in fired = true }
        )
        service.recycle(p)
        #expect(fired == false, "recycle 成功不应触发 onError")
        #expect(p.trashedAt != nil, "recycle 成功应设 trashedAt")
    }

    @Test func onErrorNotFiredOnSuccessfulRestore() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RBE4_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var fired = false
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { _ in fired = true }
        )
        service.recycle(p)
        service.restore(p)
        #expect(fired == false, "recycle + restore 都成功不应触发 onError")
        #expect(p.trashedAt == nil, "restore 应清 trashedAt")
    }

    // MARK: - 向后兼容

    @Test func onErrorNilDefaultsToNoOp() throws {
        // V5.13 Day 5 设计：onError nil = 默认不挂 closure
        // 8 处旧 call site 都靠这个默认 nil 编译通过
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RBE5_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: nil
        )
        service.recycle(p)
        #expect(p.trashedAt != nil, "onError=nil 时 recycle 仍正常")
    }

    // MARK: - 错误计数

    @Test func onErrorFiresForEachPhotoInPurgeAll() throws {
        // purgeAll 循环调 purge——每个 photo 都触发 onError 一次（如果文件都不存在）
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
                fileURL: URL(fileURLWithPath: "/tmp/RBE_p\(i)_\(UUID().uuidString).jpg"),
                fileSize: 0, width: 0, height: 0
            )
            context.insert(p)
            photos.append(p)
        }
        try context.save()
        var errorCount = 0
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { _ in errorCount += 1 }
        )
        service.purgeAll(photos)
        #expect(errorCount == 3, "3 个 photo 各触发 1 次 onError")
    }

    @Test func onErrorCapturesNonNilError() throws {
        // 验证 captured error 是非 nil Error 且 description 非空
        // V5.14: 不强校验关键词（macOS NSError 文案可能不包含 "delete"）
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/RBE6_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var captured: Error?
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { captured = $0 }
        )
        service.purge(p)
        #expect(captured != nil, "captured 应非 nil")
        let desc = captured?.localizedDescription ?? ""
        #expect(!desc.isEmpty, "error 描述应非空：\(desc)")
    }

    @Test func onErrorNotFiredForEmptyPurgeAll() throws {
        // 空数组 purgeAll = 不循环 = 不触发 onError
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        var fired = false
        let service = RecycleBinService(
            storage: .shared,
            modelContext: context,
            onError: { _ in fired = true }
        )
        service.purgeAll([])
        #expect(fired == false)
    }
}
