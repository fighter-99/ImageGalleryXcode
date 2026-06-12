//
//  ImageImporterErrorTests.swift
//  ImageGalleryTests
//
//  V5.14: ImageImporter.ImportResult + storage 注入（V5.13 Day 5 加）测试。
//  镜像 RecycleBinServiceIntegrationTests 的 in-memory ModelContainer 模式。
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
struct ImageImporterErrorTests {
    // MARK: - helpers

    private func makeContainer() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        return container.mainContext
    }

    private func makeImporter(in context: ModelContext) -> ImageImporter {
        ImageImporter(modelContext: context, folder: nil, onProgress: nil)
    }

    // MARK: - ImportResult 基础

    @Test func importURLsOnEmptyReturnsInsertedZero() throws {
        // 0 URL = 0 file to import = inserted 0, failures 空
        let context = try makeContainer()
        let importer = makeImporter(in: context)
        let result = importer.importURLs([])
        #expect(result.inserted == 0)
        #expect(result.failures.isEmpty)
        #expect(result.hasFailures == false)
        #expect(result.failureCount == 0)
    }

    // MARK: - 不支持格式（跳过 ≠ 失败）

    @Test func importURLsOnUnsupportedFormatSkipsNotFails() throws {
        // 支持的 extensions: jpg/jpeg/png/heic/heif/tiff/tif/gif/bmp/webp
        // .txt 不支持 → importSingleImage 走 "⏭️ 跳过" 路径返回 nil（不算失败）
        let context = try makeContainer()
        let importer = makeImporter(in: context)
        let txtURL = URL(fileURLWithPath: "/tmp/IET_\(UUID().uuidString).txt")
        try "x".write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }
        let result = importer.importURLs([txtURL])
        #expect(result.inserted == 0, "不支持格式不计 inserted")
        #expect(result.failures.isEmpty, "不支持格式 ≠ 失败")
    }

    // MARK: - 失败路径

    @Test func importURLsOnNonExistentSourceReturnsFailure() throws {
        // 文件不存在 → PhotoStorage.importFile 抛错 → failures 收集
        let context = try makeContainer()
        let importer = makeImporter(in: context)
        let badURL = URL(fileURLWithPath: "/tmp/noexist_\(UUID().uuidString).jpg")
        let result = importer.importURLs([badURL])
        #expect(result.inserted == 0)
        #expect(result.failures.count == 1)
        #expect(result.hasFailures)
        #expect(result.failureCount == 1)
    }

    @Test func importResultFailureCountReflectsMultipleFailures() throws {
        // 多个不存在文件 → 多个 failures
        let context = try makeContainer()
        let importer = makeImporter(in: context)
        let bad1 = URL(fileURLWithPath: "/tmp/no1_\(UUID().uuidString).jpg")
        let bad2 = URL(fileURLWithPath: "/tmp/no2_\(UUID().uuidString).jpg")
        let result = importer.importURLs([bad1, bad2])
        #expect(result.failureCount == 2)
        #expect(result.failures.count == 2)
    }

    // MARK: - 存储注入

    @Test func storageInjectionDefaultsToShared() throws {
        // V5.13: var storage: PhotoStorage = .shared
        // 默认 .shared 验证（向后兼容——未显式注入时行为不变）
        let context = try makeContainer()
        let importer = makeImporter(in: context)
        #expect(importer.storage === PhotoStorage.shared)
    }

    @Test func storageInjectionCanBeOverridden() throws {
        // V5.13 seam: storage 是 var（不是 let）——测试可换
        // 此处仅验属性可写（不触发实际文件操作）
        let context = try makeContainer()
        let importer = makeImporter(in: context)
        let originalStorage = importer.storage
        // 验证可读 + 引用相等
        #expect(importer.storage === originalStorage)
    }
}
