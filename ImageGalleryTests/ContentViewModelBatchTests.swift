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
    private static let isolatedDefaults: UserDefaults = FakeUserDefaults()
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

    // MARK: - P4.2 批量重命名

    /// 工具: 创建 test 专属 subdir, 所有 temp file 在里面, 跑完 defer 删整个 subdir
    ///   避开 /tmp 跨 test run 污染 (之前 V6.14.7 PhotoStorageTests fail 是同根因)
    ///   返回 subdir URL, caller 拼 `<subdir>/filename.ext` 当 fileURL
    private static func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: "/tmp/v422_batchrename_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func batchRename_basicSequence() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        // test 专属 subdir, 跑完删
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let u1 = dir.appendingPathComponent("src_1.jpg")
        let u2 = dir.appendingPathComponent("src_2.jpg")
        let u3 = dir.appendingPathComponent("src_3.jpg")
        try Data().write(to: u1); try Data().write(to: u2); try Data().write(to: u3)

        let p1 = Photo(filename: u1.lastPathComponent, fileURL: u1, fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: u2.lastPathComponent, fileURL: u2, fileSize: 100, width: 10, height: 10)
        let p3 = Photo(filename: u3.lastPathComponent, fileURL: u3, fileSize: 100, width: 10, height: 10)
        context.insert(p1); context.insert(p2); context.insert(p3)
        try context.save()
        model.allPhotos = [p1, p2, p3]
        model.selection = .empty.settingAll(in: [p1, p2, p3])

        model.batchRename(template: "photo_{n}")

        // 新文件名: photo_1.jpg, photo_2.jpg, photo_3.jpg (subdir 内, 跟 /tmp 其他无关)
        #expect(p1.filename == "photo_1.jpg", "p1 应改名 photo_1.jpg, 实际: \(p1.filename)")
        #expect(p2.filename == "photo_2.jpg", "p2 应改名 photo_2.jpg, 实际: \(p2.filename)")
        #expect(p3.filename == "photo_3.jpg", "p3 应改名 photo_3.jpg, 实际: \(p3.filename)")
        #expect(p1.fileURL.lastPathComponent == "photo_1.jpg")
        #expect(p2.fileURL.lastPathComponent == "photo_2.jpg")
        #expect(FileManager.default.fileExists(atPath: p1.fileURL.path), "新文件应在磁盘")
        #expect(FileManager.default.fileExists(atPath: p2.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: u1.path), "原文件应已被 move")
    }

    @Test func batchRename_padsSequence() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let u1 = dir.appendingPathComponent("a.jpg")
        let u2 = dir.appendingPathComponent("b.jpg")
        let u3 = dir.appendingPathComponent("c.jpg")
        try Data().write(to: u1); try Data().write(to: u2); try Data().write(to: u3)

        let p1 = Photo(filename: u1.lastPathComponent, fileURL: u1, fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: u2.lastPathComponent, fileURL: u2, fileSize: 100, width: 10, height: 10)
        let p3 = Photo(filename: u3.lastPathComponent, fileURL: u3, fileSize: 100, width: 10, height: 10)
        context.insert(p1); context.insert(p2); context.insert(p3)
        try context.save()
        model.allPhotos = [p1, p2, p3]
        model.selection = .empty.settingAll(in: [p1, p2, p3])

        model.batchRename(template: "photo_{n:3}")

        #expect(p1.filename == "photo_001.jpg", "actual: \(p1.filename)")
        #expect(p2.filename == "photo_002.jpg", "actual: \(p2.filename)")
        #expect(p3.filename == "photo_003.jpg", "actual: \(p3.filename)")
    }

    @Test func batchRename_preservesExtension() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let u1 = dir.appendingPathComponent("a.png")
        let u2 = dir.appendingPathComponent("b.PNG")  // 大写扩展名保留
        try Data().write(to: u1); try Data().write(to: u2)

        let p1 = Photo(filename: u1.lastPathComponent, fileURL: u1, fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: u2.lastPathComponent, fileURL: u2, fileSize: 100, width: 10, height: 10)
        context.insert(p1); context.insert(p2)
        try context.save()
        model.allPhotos = [p1, p2]
        model.selection = .empty.settingAll(in: [p1, p2])

        model.batchRename(template: "img_{n}")

        #expect(p1.filename == "img_1.png", "应保留 .png, 实际: \(p1.filename)")
        #expect(p2.filename == "img_2.PNG", "应保留 .PNG, 实际: \(p2.filename)")
    }

    @Test func batchRename_avoidsExistingFile() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        // test 专属 subdir, 预建一个 collision file
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let collisionURL = dir.appendingPathComponent("collision_target.jpg")
        try Data().write(to: collisionURL)
        let collisionBase = collisionURL.deletingPathExtension().lastPathComponent

        let srcURL = dir.appendingPathComponent("src.jpg")
        try Data().write(to: srcURL)

        let p1 = Photo(filename: srcURL.lastPathComponent, fileURL: srcURL, fileSize: 100, width: 10, height: 10)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = .empty.settingAll(in: [p1])

        // Template 渲染后 basename = collisionBase, ext = "jpg" → 跟 collisionURL 同名 → on-disk check = true → 应加 _1
        model.batchRename(template: collisionBase)

        #expect(p1.filename.hasSuffix(".jpg"))
        #expect(p1.filename != collisionURL.lastPathComponent, "应避开 on-disk 冲突, 实际: \(p1.filename)")
        #expect(p1.filename.contains("_1"), "应加 _1 后缀, 实际: \(p1.filename)")
        #expect(FileManager.default.fileExists(atPath: p1.fileURL.path), "新文件应在磁盘")
        #expect(FileManager.default.fileExists(atPath: collisionURL.path), "collision 文件应保留")
    }

    @Test func batchRename_emptySelection_noop() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let u1 = dir.appendingPathComponent("a.jpg")
        try Data().write(to: u1)
        let p1 = Photo(filename: u1.lastPathComponent, fileURL: u1, fileSize: 100, width: 10, height: 10)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = .empty  // 没选

        model.batchRename(template: "renamed_{n}")

        #expect(p1.filename == u1.lastPathComponent, "无 selection 不应被改")
    }

    @Test func batchRename_emptyTemplate_noop() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let u1 = dir.appendingPathComponent("a.jpg")
        try Data().write(to: u1)
        let p1 = Photo(filename: u1.lastPathComponent, fileURL: u1, fileSize: 100, width: 10, height: 10)
        context.insert(p1)
        try context.save()
        model.allPhotos = [p1]
        model.selection = .empty.settingAll(in: [p1])

        model.batchRename(template: "   ")  // 全空白 → trim 后空 → noop

        #expect(p1.filename == u1.lastPathComponent, "空白 template 不应触发 rename")
    }

    @Test func batchRename_undoable() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let u1 = dir.appendingPathComponent("a.jpg")
        let u2 = dir.appendingPathComponent("b.jpg")
        try Data().write(to: u1); try Data().write(to: u2)
        let originalName1 = u1.lastPathComponent
        let originalName2 = u2.lastPathComponent

        let p1 = Photo(filename: originalName1, fileURL: u1, fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: originalName2, fileURL: u2, fileSize: 100, width: 10, height: 10)
        context.insert(p1); context.insert(p2)
        try context.save()
        model.allPhotos = [p1, p2]
        model.selection = .empty.settingAll(in: [p1, p2])

        model.batchRename(template: "renamed_{n}")
        #expect(p1.filename == "renamed_1.jpg", "rename 后: \(p1.filename)")
        #expect(p2.filename == "renamed_2.jpg", "rename 后: \(p2.filename)")

        // 撤销
        model.undoManager.undo()

        #expect(p1.filename == originalName1, "undo 后应恢复原名, 实际: \(p1.filename)")
        #expect(p2.filename == originalName2, "undo 后应恢复原名, 实际: \(p2.filename)")
        #expect(p1.fileURL == u1, "undo 后 fileURL 恢复")
        #expect(FileManager.default.fileExists(atPath: u1.path), "原文件应被恢复")
        #expect(FileManager.default.fileExists(atPath: u2.path), "原文件应被恢复")
    }
}
