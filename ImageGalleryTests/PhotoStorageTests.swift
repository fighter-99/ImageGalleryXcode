//
//  PhotoStorageTests.swift
//  ImageGalleryTests
//
//  V3.6: PhotoStorage 单元测试
//  验证:
//  - photosDirectory 路径正确（Application Support/ImageGallery/Photos）
//  - importFile 复制成功 + 命名规则（UUID_原文件名）
//  - importFile 对不存在的源文件抛错
//  - delete 真正删除文件
//  - verifyStorage 反映写入权限
//
//  设计：测试用例自己管理临时文件 + 清理，避免污染真实 Photos 目录。
//

import Testing
import Foundation
@testable import ImageGallery

struct PhotoStorageTests {

    // MARK: - 路径契约

    @Test func photosDirectoryEndsWithImageGalleryPhotos() {
        let storage = PhotoStorage.shared
        #expect(storage.photosDirectory.lastPathComponent == "Photos")
        #expect(storage.photosDirectory.path.contains("ImageGallery/Photos"))
    }

    @Test func photosDirectoryExists() {
        let storage = PhotoStorage.shared
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: storage.photosDirectory.path, isDirectory: &isDir
        )
        #expect(exists)
        #expect(isDir.boolValue)
    }

    // MARK: - importFile 成功路径

    @Test func importFileCopiesToPhotosDirectory() throws {
        let storage = PhotoStorage.shared
        // 准备临时源文件
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStorageTest_\(UUID().uuidString).bin")
        try Data("hello".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 执行
        let dest = try storage.importFile(from: tmp)
        defer { try? FileManager.default.removeItem(at: dest) }

        // 验证
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(dest.path.contains(storage.photosDirectory.path))
        let content = try Data(contentsOf: dest)
        #expect(content == Data("hello".utf8))
    }

    @Test func importFilePrependsUUIDToOriginalName() throws {
        let storage = PhotoStorage.shared
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("myphoto.jpg")
        try Data("x".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dest = try storage.importFile(from: tmp)
        defer { try? FileManager.default.removeItem(at: dest) }

        // 命名规则：{UUID}_{原文件名}
        let name = dest.lastPathComponent
        #expect(name.hasSuffix("_myphoto.jpg"))
        #expect(name.count > "_myphoto.jpg".count)  // 有 UUID 前缀
    }

    // MARK: - importFile 失败路径

    @Test func importFileThrowsForNonExistentSource() {
        let storage = PhotoStorage.shared
        let nonexistent = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely_not_here_\(UUID().uuidString).jpg")

        #expect(throws: PhotoStorageError.self) {
            _ = try storage.importFile(from: nonexistent)
        }
    }

    // MARK: - delete

    @Test func deleteRemovesFile() throws {
        let storage = PhotoStorage.shared
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStorageDeleteTest_\(UUID().uuidString).bin")
        try Data("delete me".utf8).write(to: tmp)

        // 把文件搬进 photosDirectory 以模拟"应用自有文件"
        let moved = try storage.importFile(from: tmp)
        try? FileManager.default.removeItem(at: tmp)
        #expect(FileManager.default.fileExists(atPath: moved.path))

        try storage.delete(photoURL: moved)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
    }

    // MARK: - verifyStorage

    @Test func verifyStorageReturnsTrueForWritableDir() {
        let storage = PhotoStorage.shared
        #expect(storage.verifyStorage())
    }
}
