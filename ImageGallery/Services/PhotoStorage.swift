//
//  PhotoStorage.swift
//  ImageGallery
//
//  V3.6 NEW: 应用自有图片存储服务
//  负责把外部图片复制到 Application Support/ImageGallery/Photos/，
//  替代之前散落在 ImageImporter.importSingleImage 里的硬编码路径。
//

import Foundation

/// V3.6 NEW: 应用自有图片存储服务
/// 负责把外部图片复制到 Application Support/ImageGallery/Photos/，
/// 替代之前散落在 ImageImporter.importSingleImage 里的硬编码路径。
///
/// 设计：不强制 @MainActor（FileManager 调用线程安全；调用方通常是 MainActor，
/// 但 struct ImageImporter 不是 actor-isolated，标 @MainActor 会逼着所有方法 await）。
final class PhotoStorage {
    static let shared = PhotoStorage()

    /// Application Support/ImageGallery/Photos/ 目录
    /// 首次访问时自动创建（含父目录）
    let photosDirectory: URL

    nonisolated private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        photosDirectory = appSupport
            .appendingPathComponent("ImageGallery", isDirectory: true)
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: photosDirectory, withIntermediateDirectories: true
        )
    }

    /// 把外部文件复制到应用 Photos 目录，返回新的 URL
    /// - 失败抛 PhotoStorageError（区别于 print + 吞错的旧行为）
    /// - 命名规则：`{UUID}_{原文件名}` 避免冲突
    @discardableResult
    func importFile(from sourceURL: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: photosDirectory, withIntermediateDirectories: true
        )
        let uniqueName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destURL = photosDirectory.appendingPathComponent(uniqueName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            throw PhotoStorageError.copyFailed(sourceURL, error)
        }
    }

    /// 永久删除应用 Photos 目录里的文件（回收站 expire / 永久删除时调用）
    func delete(photoURL: URL) throws {
        do {
            try FileManager.default.removeItem(at: photoURL)
        } catch {
            throw PhotoStorageError.deleteFailed(photoURL, error)
        }
    }

    /// 验证 Photos 目录可访问（启动时检查）
    func verifyStorage() -> Bool {
        FileManager.default.isWritableFile(atPath: photosDirectory.path)
    }
}

enum PhotoStorageError: Error {
    case sourceFileUnreadable(URL)
    case copyFailed(URL, Error)
    case deleteFailed(URL, Error)
}
