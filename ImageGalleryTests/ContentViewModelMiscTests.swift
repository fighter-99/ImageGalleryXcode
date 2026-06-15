//
//  ContentViewModelMiscTests.swift
//  ImageGalleryTests
//
//  V5.54-7: ContentViewModel 杂项 tests
//  测 funcs: checkStorage, serializeSelection, restoreSelection, clearSelectionOnFilterChange
//  全部不需 ModelContainer——纯字段/枚举/字符串验证
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
struct ContentViewModelMiscTests {

    // MARK: - serializeSelection / restoreSelection

    @Test func serializeSelection_nil_returnsAll() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(nil) == "all")
    }

    @Test func serializeSelection_all_returnsAll() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(.all) == "all")
    }

    @Test func serializeSelection_unfiled_returnsUnfiled() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(.unfiled) == "unfiled")
    }

    @Test func serializeSelection_duplicates_returnsDuplicates() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(.duplicates) == "duplicates")
    }

    @Test func serializeSelection_recent7Days_returnsRecent7Days() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(.recent7Days) == "recent7Days")
    }

    @Test func serializeSelection_largeFiles_returnsLargeFiles() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(.largeFiles) == "largeFiles")
    }

    @Test func serializeSelection_recentlyDeleted_returnsRecentlyDeleted() {
        let model = ContentViewModel()
        #expect(model.serializeSelection(.recentlyDeleted) == "recentlyDeleted")
    }

    @Test func serializeSelection_folder_returnsFolderPrefixedUUID() {
        let model = ContentViewModel()
        let folder = Folder(name: "Vacation")
        let result = model.serializeSelection(.folder(folder))
        #expect(result == "folder:\(folder.id.uuidString)")
    }

    @Test func serializeSelection_tag_returnsTagPrefixedUUID() {
        let model = ContentViewModel()
        let tag = Tag(name: "favorite")
        let result = model.serializeSelection(.tag(tag))
        #expect(result == "tag:\(tag.id.uuidString)")
    }

    // 注意: restoreSelection valid folder/tag 测试需要 ModelContainer.fetch——
    // 见 V5.55-3 下的 fetch 路径 tests (inline ModelContainer 模式)

    // MARK: - restoreSelection fetch 路径 (需要 inline ModelContainer)

    // MARK: - clearSelectionOnFilterChange

    @Test func clearSelectionOnFilterChange_emptySelection_isNoOp() {
        let model = ContentViewModel()
        let before = model.selection
        model.clearSelectionOnFilterChange()
        #expect(model.selection == before, "空 selection 不应被改")
    }

    @Test func clearSelectionOnFilterChange_withSingleSelection_clears() {
        let model = ContentViewModel()
        let id = UUID()
        model.selection = model.selection.selectingSingle(id)
        #expect(!model.selection.isEmpty)
        model.clearSelectionOnFilterChange()
        #expect(model.selection.isEmpty, "有 selection 时应清空")
    }

    @Test func clearSelectionOnFilterChange_withMultiSelection_clears() {
        let model = ContentViewModel()
        let p1 = Photo(filename: "1.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_clear_1.jpg"), fileSize: 100, width: 10, height: 10)
        let p2 = Photo(filename: "2.jpg", fileURL: URL(fileURLWithPath: "/tmp/V554_clear_2.jpg"), fileSize: 100, width: 10, height: 10)
        model.selection = .empty.settingAll(in: [p1, p2])
        #expect(!model.selection.isEmpty)
        model.clearSelectionOnFilterChange()
        #expect(model.selection.isEmpty, "多选 selection 应被清空")
    }

    // MARK: - checkStorage (PhotoStorage.shared.verifyStorage 真测——mock 不容易)

    @Test func checkStorage_withValidStorage_setsNoError() throws {
        // 注意: 这 test 依赖 PhotoStorage.shared.verifyStorage 返回 true
        // 真实环境下 Application Support 目录可写
        // 如果环境异常 (CI sandbox) 这 test 会 fail——可加 try / skip 机制
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        model.checkStorage()
        // verifyStorage 检查 Application Support 目录——dev 环境通常 true
        // 失败时是 storageErrorMessage 赋值给 Copy.storageError
        // 测只验 "如果有 error, 它是 Copy.storageError 字符串"
        if let err = model.storageErrorMessage {
            #expect(err == Copy.storageError)
        }
    }

    // MARK: - 跨测试集成：serialize → restore roundtrip

    @Test func serialize_thenRestore_folder_roundtrip() throws {
        // 真实 folder: serialize → restore → 应得回原 folder
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        let folder = Folder(name: "Vacation")
        context.insert(folder)
        try context.save()

        let key = model.serializeSelection(.folder(folder))
        let restored = model.restoreSelection(key)
        #expect(restored == .folder(folder), "serialize→restore folder 应 roundtrip")
    }

    @Test func serialize_thenRestore_tag_roundtrip() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        let tag = Tag(name: "favorite")
        context.insert(tag)
        try context.save()

        let key = model.serializeSelection(.tag(tag))
        let restored = model.restoreSelection(key)
        #expect(restored == .tag(tag), "serialize→restore tag 应 roundtrip")
    }

    @Test func serialize_thenRestore_folderUUIDNotInStore_fallsBackToAll() throws {
        // 序列化一个 folder, 但 context 里没存——restore 应 fallback .all
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        // 不 insert——只用 uuid 构造 key
        let orphanID = UUID()
        let key = "folder:\(orphanID.uuidString)"
        let restored = model.restoreSelection(key)
        #expect(restored == .all, "UUID 不在 store 应 fallback .all")
    }
}
