//
//  ContentViewModelRecycleBinTests.swift
//  ImageGalleryTests
//
//  V5.54-3: ContentViewModel 回收站路径 tests
//  V5.54-1 教训: ContentViewModel test + ModelContainer 在 helper 函数里一起构造会触发
//  Swift Testing 0.000s 失败（actor isolation + ModelContainer registry 冲突）
//  本文件遵循 RecycleBinServiceIntegrationTests 模式——inline ModelContainer per test
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

// V6.19.6 (P0 #18): 加 @Suite(.serialized) — 强制串行, 避免 ModelContainer 与其他 suite 并行创建冲突
@MainActor
@Suite(.serialized)
struct ContentViewModelRecycleBinTests {

    // V6.12.20: 共享 suite + cleanup pattern (避开 UserDefaults.standard 跨 test 污染)
    //   跟 ContentViewModelStateTests.isolatedModel 同源——共享 1 个 suite, 每个 test cleanup
    //   避免每次 UUID 新 suite 给 cfprefsd 压力 (memory: swift-testing-userdefaults-parallel-crash)
    @MainActor
    private static let isolatedDefaults: UserDefaults = FakeUserDefaults()
    private static let userSettingsKeys: [String] = [
        "viewModeRaw", "showSidebar", "accentColorID",
        "trashRetentionDays", "appearanceMode", "thumbnailSize",
        "sidebarSelection", "sortOption", "thumbnailLayoutMode",
        "sidebarColumnWidth", "autoDeduplicate",
        "autoGenerateThumbnails", "defaultExportFormat",
        "defaultExportQuality", "scrollAnchorPhotoID"
    ]
    private static func isolatedModel() -> ContentViewModel {
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }

    @Test func deleteSinglePhoto_setsTrashedAt() throws {
        // Inline ModelContainer（不抽 helper——见文件头注释）
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context
        let photo = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"),
            fileSize: 1000, width: 100, height: 100
        )
        context.insert(photo)
        try context.save()
        model.grid.allPhotos = [photo]
        model.grid.selection = model.grid.selection.selectingSingle(photo.id)

        model.grid.deleteSinglePhoto()

        #expect(photo.trashedAt != nil, "recycle 后 trashedAt 应非 nil")
        #expect(photo.isInTrash == true)
        #expect(model.grid.selection.isEmpty == true, "selection 应被清空")
    }

    @Test func deleteSinglePhoto_noSelection_isNoOp() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context
        let photo = Photo(
            filename: "noop.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"),
            fileSize: 100, width: 10, height: 10
        )
        context.insert(photo)
        try context.save()
        model.grid.allPhotos = [photo]
        model.grid.selection = .empty  // 没选

        model.grid.deleteSinglePhoto()
        // 没 selection 时 no-op
        #expect(photo.trashedAt == nil, "无 selection 时不应被删")
    }

    @Test func batchDelete_movesAllSelectedToTrash() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_1.jpg"), fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: "2.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_2.jpg"), fileSize: 100, width: 10, height: 10)
        let p3 = Photo(filename: "3.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_3.jpg"), fileSize: 100, width: 10, height: 10)
        context.insert(p1)
        context.insert(p2)
        context.insert(p3)
        try context.save()
        model.grid.allPhotos = [p1, p2, p3]
        model.grid.selection = .empty.settingAll(in: [p1, p2, p3])

        model.grid.batchDelete()

        #expect(p1.trashedAt != nil)
        #expect(p2.trashedAt != nil)
        #expect(p3.trashedAt != nil)
        #expect(model.grid.selection.isEmpty == true)
    }

    @Test func emptyTrash_purgesExpiredTrashedPhotos() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let trashURL = URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_trash.jpg")
        let normalURL = URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_normal.jpg")
        // V6.13.1: 真正建临时文件——RecycleBinService.purge 调 FileManager.removeItem
        //   文件不存在会 throw → purge 早 return → photo 没被删
        //   之前 test 漏了这一步, fail 是 stale test 缺陷不是 production bug
        FileManager.default.createFile(atPath: trashURL.path, contents: Data())
        FileManager.default.createFile(atPath: normalURL.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: trashURL)
            try? FileManager.default.removeItem(at: normalURL)
        }
        let trashPhoto = Photo(filename: "trash.jpg", fileURL: trashURL, fileSize: 100, width: 10, height: 10)
        let normalPhoto = Photo(filename: "normal.jpg", fileURL: normalURL, fileSize: 100, width: 10, height: 10)
        context.insert(trashPhoto)
        context.insert(normalPhoto)
        try context.save()
        // 标记 trashPhoto 为 60 天前（远超 30 天 default）
        trashPhoto.trashedAt = Date().addingTimeInterval(-86400 * 60)
        try context.save()
        model.grid.allPhotos = [trashPhoto, normalPhoto]

        model.grid.emptyTrash()

        // trashPhoto 应被 hard delete，normalPhoto 保留
        let remaining = try context.fetch(FetchDescriptor<Photo>())
        #expect(remaining.count == 1, "应只剩 normalPhoto")
        #expect(remaining.first?.id == normalPhoto.id)
    }

    @Test func keepNewestPerDuplicateGroup_withNonDuplicates_isNoOp() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context
        let photo = Photo(
            filename: "unique.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"),
            fileSize: 100, width: 10, height: 10
        )
        context.insert(photo)
        try context.save()
        model.grid.allPhotos = [photo]

        // 单张 unique photo, 不是 duplicate group
        let trashedBefore = photo.trashedAt
        model.grid.keepNewestPerDuplicateGroup()
        #expect(photo.trashedAt == trashedBefore, "无 duplicate 时不应被 recycle")
    }

    @Test func restoreSelectedFromTrash_clearsTrashedAt() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context
        let photo = Photo(
            filename: "restored.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"),
            fileSize: 100, width: 10, height: 10
        )
        context.insert(photo)
        try context.save()
        model.grid.allPhotos = [photo]

        // recycle + 切 sidebar 到 trash 视图
        model.grid.selection = model.grid.selection.selectingSingle(photo.id)
        model.grid.deleteSinglePhoto()
        #expect(photo.trashedAt != nil)
        model.sidebarSelection = .recentlyDeleted
        model.grid.selection = model.grid.selection.selectingSingle(photo.id)

        model.grid.restoreSelectedFromTrash()
        #expect(photo.trashedAt == nil, "restore 后 trashedAt 应清空")
    }

    @Test func permanentDeleteSelected_removesFromContext() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context
        let photoURL = URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg")
        // V6.13.1: 真正建临时文件——同 emptyTrash test 根因 (FileManager.removeItem throw)
        FileManager.default.createFile(atPath: photoURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: photoURL) }
        let photo = Photo(
            filename: "purge.jpg",
            fileURL: photoURL,
            fileSize: 100, width: 10, height: 10
        )
        context.insert(photo)
        try context.save()
        let photoID = photo.id
        model.grid.allPhotos = [photo]

        // recycle + 切到 trash + 选
        model.grid.selection = model.grid.selection.selectingSingle(photo.id)
        model.grid.deleteSinglePhoto()
        model.sidebarSelection = .recentlyDeleted
        model.grid.selection = model.grid.selection.selectingSingle(photo.id)

        model.grid.permanentDeleteSelected()

        // photo 应从 context 中 hard delete
        let allPhotos = try context.fetch(FetchDescriptor<Photo>())
        let remaining = allPhotos.filter { $0.id == photoID }
        #expect(remaining.isEmpty, "permanentDeleteSelected 应硬删 photo")
    }
}
