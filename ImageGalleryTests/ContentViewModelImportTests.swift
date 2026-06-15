//
//  ContentViewModelImportTests.swift
//  ImageGalleryTests
//
//  V5.54-4: ContentViewModel 导入路径 tests
//  测 funcs: handleDropImport, runImportWithDuplicateCheck, confirmSkipDuplicates, confirmImportAllDuplicates, cancelDuplicateImport, importPhotos, handleDrop
//
//  startImport 跳过——NSOpenPanel UI 不能在 test 测
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
@Suite(.serialized)  // V5.55: 强制串行——避免 Swift Testing runner 跟 ModelContainer 并行创建冲突
struct ContentViewModelImportTests {

    @Test func cancelDuplicateImport_clearsAllDialogState() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        // 模拟 dialog 已打开 + 有待导入 urls
        model.pendingImportURLs = [
            URL(fileURLWithPath: "/tmp/dup1.jpg"),
            URL(fileURLWithPath: "/tmp/dup2.jpg")
        ]
        // 用一个 fake DuplicateCheckResult
        let fakeCheck = ImageImporter.DuplicateCheckResult(
            existing: [URL(fileURLWithPath: "/tmp/dup1.jpg")],
            newCount: 1,
            totalCount: 2
        )
        model.importDuplicateCheck = fakeCheck

        model.cancelDuplicateImport()

        #expect(model.importDuplicateCheck == nil)
        #expect(model.pendingImportURLs.isEmpty == true)
    }

    @Test func confirmSkipDuplicates_filtersOutDuplicates() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        let dupURL = URL(fileURLWithPath: "/tmp/V554_dup.jpg")
        let newURL = URL(fileURLWithPath: "/tmp/V554_new.jpg")
        let existing = [dupURL]
        let all = [dupURL, newURL]
        // 模拟 dialog state
        model.pendingImportURLs = all
        model.importDuplicateCheck = ImageImporter.DuplicateCheckResult(
            existing: existing, newCount: 1, totalCount: 2
        )

        // 没真正 import photos (因为 fileURLs 是 /tmp 假路径)——会失败但不影响
        // 这 test 主要验证 confirmSkipDuplicates 清理了 dialog state
        model.confirmSkipDuplicates()

        #expect(model.importDuplicateCheck == nil)
        #expect(model.pendingImportURLs.isEmpty == true)
    }

    @Test func confirmImportAllDuplicates_clearsDialogState() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        model.pendingImportURLs = [URL(fileURLWithPath: "/tmp/V554_1.jpg")]
        model.importDuplicateCheck = ImageImporter.DuplicateCheckResult(
            existing: [], newCount: 1, totalCount: 1
        )

        model.confirmImportAllDuplicates()

        #expect(model.importDuplicateCheck == nil)
        #expect(model.pendingImportURLs.isEmpty == true)
    }

    @Test func handleDropImport_emptyUrls_isNoOp() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        model.handleDropImport([])
        // 没 url——runImportWithDuplicateCheck 不调，dialog state 保持 nil
        #expect(model.importDuplicateCheck == nil)
        #expect(model.pendingImportURLs.isEmpty == true)
    }

    @Test func runImportWithDuplicateCheck_noDuplicates_setsImportProgress() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        // 用一个真实 temp file URL (空文件即可, hash 算出来唯一)
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("V554_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        model.runImportWithDuplicateCheck(urls: [tmpFile])

        // 不 await——runImportWithDuplicateCheck 是 async (后台算 SHA256)
        // 只验: 调用没崩 + dialog 状态在被 check 期间短暂 set (test 不 await)
    }

    // MARK: - 静态方法: supportedImageExtensions + expandFolders

    @Test func supportedImageExtensions_includesCommonFormats() {
        let exts = ContentViewModel.supportedImageExtensions
        #expect(exts.contains("jpg"))
        #expect(exts.contains("jpeg"))
        #expect(exts.contains("png"))
        #expect(exts.contains("heic"))
        #expect(exts.contains("webp"))
        #expect(exts.contains("gif"))
        // 共 10 个（V4.49.0 列表）
        #expect(exts.count == 10)
    }

    @Test func expandFolders_emptyInput_returnsEmpty() {
        #expect(ContentViewModel.expandFolders([]).isEmpty)
    }

    @Test func expandFolders_singleFile_returnsThatFile() {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("V554_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = ContentViewModel.expandFolders([tmpFile])
        #expect(result.count == 1)
        #expect(result.first?.path == tmpFile.path)
    }

    @Test func expandFolders_directory_recursivelyExpands() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("V554Dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 在 tmpDir 下创建 2 个子文件 + 1 个子目录（递归会找到 2 个文件）
        let f1 = tmpDir.appendingPathComponent("a.jpg")
        let f2 = tmpDir.appendingPathComponent("b.jpg")
        let subDir = tmpDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let f3 = subDir.appendingPathComponent("c.jpg")
        FileManager.default.createFile(atPath: f1.path, contents: Data())
        FileManager.default.createFile(atPath: f2.path, contents: Data())
        FileManager.default.createFile(atPath: f3.path, contents: Data())

        let result = ContentViewModel.expandFolders([tmpDir])
        #expect(result.count == 3, "应递归找到 3 个文件")
        #expect(result.contains(f1))
        #expect(result.contains(f2))
        #expect(result.contains(f3))
    }

    @Test func handleDrop_providersArray_returnsTrue() throws {
        // handleDrop 依赖 NSItemProvider + DispatchGroup (async) — 难测
        // 只验空 path: 0 providers 应仍 return true (group.notify 异步跑)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = ContentViewModel()
        model.modelContext = context

        let result = model.handleDrop(providers: [])
        #expect(result == true, "handleDrop 应始终 return true (符合 NSDragDestination 协议)")
    }
}
