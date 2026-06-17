//
//  ContentViewModelBatchTests.swift
//  ImageGalleryTests
//
//  V5.54-5: ContentViewModel 批量操作 tests
//  测 funcs: batchMove, batchAddTag, batchSetRating, batchDelete (recycled), batchExport
//
//  沿用 V5.54-3 inline ModelContainer 模式 (per test body, 不抽 helper)
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
@Suite(.serialized)  // V5.55: 强制串行——避免 Swift Testing runner 跟 ModelContainer 并行创建冲突
struct ContentViewModelBatchTests {

    // V6.12.20: 共享 suite + cleanup pattern (避开 UserDefaults.standard 跨 test 污染)
    //   跟 ContentViewModelStateTests.isolatedModel 同源——共享 1 个 suite, 每个 test cleanup
    //   避免每次 UUID 新 suite 给 cfprefsd 压力 (memory: swift-testing-userdefaults-parallel-crash)
    @MainActor
    private static let isolatedDefaults: UserDefaults = UserDefaults(suiteName: "ImageGalleryTests_Batch")!
    private static let userSettingsKeys: [String] = [
        "viewModeRaw", "showSidebar", "showDetail", "accentColorID",
        "trashRetentionDays", "appearanceMode", "thumbnailSize",
        "sidebarSelection", "sortOption", "thumbnailLayoutMode",
        "sidebarColumnWidth", "detailColumnWidth", "autoDeduplicate",
        "autoGenerateThumbnails", "defaultExportFormat",
        "defaultExportQuality", "scrollAnchorPhotoID"
    ]
    private static func isolatedModel() -> ContentViewModel {
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }

    @Test func batchMove_toFolder_setsFolderOnPhotos() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        // 1 folder + 2 photos
        let folder = Folder(name: "Vacation")
        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_1.jpg"), fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: "2.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_2.jpg"), fileSize: 100, width: 10, height: 10)
        context.insert(folder)
        context.insert(p1)
        context.insert(p2)
        try context.save()
        model.allPhotos = [p1, p2]
        model.selection = .empty.settingAll(in: [p1, p2])

        model.batchMove(to: folder)

        #expect(p1.folder?.id == folder.id, "p1 应被移到 Vacation folder")
        #expect(p2.folder?.id == folder.id, "p2 应被移到 Vacation folder")
        #expect(model.selection.isEmpty == true, "移动后应清空 selection")
    }

    @Test func batchMove_toNil_clearsFolderAssignment() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let folder = Folder(name: "Old")
        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"), fileSize: 100, width: 10, height: 10)
        p1.folder = folder
        context.insert(folder)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = model.selection.selectingSingle(p1.id)

        model.batchMove(to: nil)  // 移到 "未整理"

        #expect(p1.folder == nil, "移到 nil = 清除 folder 归属")
    }

    @Test func batchAddTag_addsTagToSelectedPhotos() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let tag = Tag(name: "favorite")
        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"), fileSize: 100, width: 10, height: 10)
        context.insert(tag)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = model.selection.selectingSingle(p1.id)

        model.batchAddTag(tag)

        #expect(p1.tags.contains(where: { $0.id == tag.id }), "p1 应含 tag")
    }

    @Test func batchAddTag_alreadyHasTag_doesNotDuplicate() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let tag = Tag(name: "favorite")
        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"), fileSize: 100, width: 10, height: 10)
        p1.tags.append(tag)
        context.insert(tag)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = model.selection.selectingSingle(p1.id)

        model.batchAddTag(tag)

        let count = p1.tags.filter { $0.id == tag.id }.count
        #expect(count == 1, "不应重复加 tag")
    }

    @Test func batchSetRating_appliesRatingToAll() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"), fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: "2.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString)_2.jpg"), fileSize: 100, width: 10, height: 10)
        context.insert(p1)
        context.insert(p2)
        try context.save()
        model.allPhotos = [p1, p2]
        model.selection = .empty.settingAll(in: [p1, p2])

        model.batchSetRating(4)

        #expect(p1.rating == 4)
        #expect(p2.rating == 4)
    }

    @Test func batchSetRating_zero_clearsRating() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"), fileSize: 100, width: 10, height: 10)
        p1.rating = 5
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = model.selection.selectingSingle(p1.id)

        model.batchSetRating(0)

        #expect(p1.rating == 0, "rating=0 应清除")
    }

    @Test func batchMove_noSelection_isNoOp() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let folder = Folder(name: "Vacation")
        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_\(UUID().uuidString).jpg"), fileSize: 100, width: 10, height: 10)
        context.insert(folder)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = .empty  // 没选

        model.batchMove(to: folder)
        // 没选时 batchMove 是 no-op
        #expect(p1.folder == nil, "无 selection 时不应被移")
    }
}
