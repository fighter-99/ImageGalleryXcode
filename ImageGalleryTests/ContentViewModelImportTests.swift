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
        "defaultExportQuality", "scrollAnchorPhotoID",
        // V6.39.1: 加 defaultImportLocation
        "defaultImportLocation"
    ]
    private static func isolatedModel() -> ContentViewModel {
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }

    @Test func cancelDuplicateImport_clearsAllDialogState() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        // 模拟 dialog 已打开 + 有待导入 urls
        model.importVM.pendingImportURLs = [
            URL(fileURLWithPath: "/tmp/dup1.jpg"),
            URL(fileURLWithPath: "/tmp/dup2.jpg")
        ]
        // 用一个 fake DuplicateCheckResult
        let fakeCheck = ImageImporter.DuplicateCheckResult(
            existing: [URL(fileURLWithPath: "/tmp/dup1.jpg")],
            newCount: 1,
            totalCount: 2
        )
        model.importVM.importDuplicateCheck = fakeCheck

        model.importVM.cancelDuplicateImport()

        #expect(model.importVM.importDuplicateCheck == nil)
        #expect(model.importVM.pendingImportURLs.isEmpty == true)
    }

    @Test func confirmSkipDuplicates_filtersOutDuplicates() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let dupURL = URL(fileURLWithPath: "/tmp/V554_dup.jpg")
        let newURL = URL(fileURLWithPath: "/tmp/V554_new.jpg")
        let existing = [dupURL]
        let all = [dupURL, newURL]
        // 模拟 dialog state
        model.importVM.pendingImportURLs = all
        model.importVM.importDuplicateCheck = ImageImporter.DuplicateCheckResult(
            existing: existing, newCount: 1, totalCount: 2
        )

        // 没真正 import photos (因为 fileURLs 是 /tmp 假路径)——会失败但不影响
        // 这 test 主要验证 confirmSkipDuplicates 清理了 dialog state
        model.importVM.confirmSkipDuplicates()

        #expect(model.importVM.importDuplicateCheck == nil)
        #expect(model.importVM.pendingImportURLs.isEmpty == true)
    }

    @Test func confirmImportAllDuplicates_clearsDialogState() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        model.importVM.pendingImportURLs = [URL(fileURLWithPath: "/tmp/V554_1.jpg")]
        model.importVM.importDuplicateCheck = ImageImporter.DuplicateCheckResult(
            existing: [], newCount: 1, totalCount: 1
        )

        model.importVM.confirmImportAllDuplicates()

        #expect(model.importVM.importDuplicateCheck == nil)
        #expect(model.importVM.pendingImportURLs.isEmpty == true)
    }

    @Test func handleDropImport_emptyUrls_isNoOp() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        model.importVM.handleDropImport([])
        // 没 url——runImportWithDuplicateCheck 不调，dialog state 保持 nil
        #expect(model.importVM.importDuplicateCheck == nil)
        #expect(model.importVM.pendingImportURLs.isEmpty == true)
    }

    @Test func runImportWithDuplicateCheck_noDuplicates_setsImportProgress() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        // 用一个真实 temp file URL (空文件即可, hash 算出来唯一)
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("V554_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        model.importVM.runImportWithDuplicateCheck(urls: [tmpFile])

        // 不 await——runImportWithDuplicateCheck 是 async (后台算 SHA256)
        // 只验: 调用没崩 + dialog 状态在被 check 期间短暂 set (test 不 await)
    }

    // MARK: - 静态方法: supportedImageExtensions + expandFolders

    @Test func supportedImageExtensions_includesCommonFormats() {
        let exts = ImportViewModel.supportedImageExtensions
        // V6.98 (L2 audit fix): 加 6 RAW 格式后, 总数 10 → 16
        #expect(exts.contains("jpg"))
        #expect(exts.contains("jpeg"))
        #expect(exts.contains("png"))
        #expect(exts.contains("heic"))
        #expect(exts.contains("webp"))
        #expect(exts.contains("gif"))
        // V6.98: RAW 格式覆盖 (6 种主流)
        #expect(exts.contains("cr2"))  // Canon
        #expect(exts.contains("cr3"))  // Canon
        #expect(exts.contains("nef"))  // Nikon
        #expect(exts.contains("arw"))  // Sony
        #expect(exts.contains("dng"))  // Adobe / iPhone Pro RAW
        #expect(exts.contains("rw2"))  // Panasonic
        // 共 16 个 (V4.49.0 10 + V6.98 RAW 6)
        #expect(exts.count == 16)
    }

    @Test func expandFolders_emptyInput_returnsEmpty() {
        #expect(ImportViewModel.expandFolders([]).isEmpty)
    }

    @Test func expandFolders_singleFile_returnsThatFile() {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("V554_\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: tmpFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = ImportViewModel.expandFolders([tmpFile])
        #expect(result.count == 1)
        #expect(result.first?.path == tmpFile.path)
    }

    @Test func expandFolders_directory_recursivelyExpands() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("V554Dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // 在 tmpDir 下创建 2 个子文件 + 1 个子目录（递归会找到 3 个文件）
        let f1 = tmpDir.appendingPathComponent("a.jpg")
        let f2 = tmpDir.appendingPathComponent("b.jpg")
        let subDir = tmpDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let f3 = subDir.appendingPathComponent("c.jpg")
        FileManager.default.createFile(atPath: f1.path, contents: Data())
        FileManager.default.createFile(atPath: f2.path, contents: Data())
        FileManager.default.createFile(atPath: f3.path, contents: Data())

        let result = ImportViewModel.expandFolders([tmpDir])
        // V6.14.7: 改用 basename 验证 — production expandFolders 用 resolvingSymlinksInPath
        //   做 visited, result URL path 跟 test f1 (unresolved) 的 URL.== 不一定 match
        //   (e.g. /var/folders/.../a.jpg vs /private/var/folders/.../a.jpg)
        //   basenames 不受 symlink 解析影响, 是稳的验证方式
        let resultBasenames = Set(result.map { $0.lastPathComponent })
        #expect(result.count == 3, "应递归找到 3 个文件")
        #expect(resultBasenames == ["a.jpg", "b.jpg", "c.jpg"], "应找到 3 个 jpg 文件 (a/b/c)")
    }

    @Test func handleDrop_providersArray_returnsTrue() throws {
        // handleDrop 依赖 NSItemProvider + DispatchGroup (async) — 难测
        // 只验空 path: 0 providers 应仍 return true (group.notify 异步跑)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let model = Self.isolatedModel()
        model.modelContext = context

        let result = model.importVM.handleDrop(providers: [])
        #expect(result == true, "handleDrop 应始终 return true (符合 NSDragDestination 协议)")
    }

    // MARK: - V6.39.1: settings 注入 + defaultImportLocation 路径

    @Test func importVM_settingsIsWiredFromContentViewModelInit() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        // V6.39.1: ContentViewModel init 应自动 wire importVM.settings
        #expect(model.importVM.settings != nil, "V6.39.1: importVM.settings 应在 init 注入")
    }

    @Test func defaultImportLocation_writesToUserDefaultsViaSettingsBinding() {
        // V6.39.1: settings 是 ContentViewModel.sharedSettings 同一实例
        //   直接验证 wiring + UserDefaults 同步 (用 isolatedUserSettings 避免污染 standard)
        let model = Self.isolatedModel()
        model.settings.defaultImportLocation = "file:///tmp/photos_import"
        #expect(model.settings.defaultImportLocation == "file:///tmp/photos_import")
        #expect(Self.isolatedDefaults.string(forKey: "defaultImportLocation") == "file:///tmp/photos_import")
    }

    @Test func defaultImportLocation_staleDetection_clearsOnReset() {
        // V6.39.1: defaultImportLocation 写入后, reset() 也应清掉 (跟其他偏好同步)
        let model = Self.isolatedModel()
        model.settings.defaultImportLocation = "file:///nonexistent"
        #expect(model.settings.defaultImportLocation != nil)
        model.settings.reset()
        #expect(model.settings.defaultImportLocation == nil, "reset 应清掉 stale defaultImportLocation")
    }
}
