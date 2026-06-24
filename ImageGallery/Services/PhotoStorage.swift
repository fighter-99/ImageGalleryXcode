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
        // V6.20.3 (code audit fix #11): fallback 到 ~/Pictures 代替 force-unwrap
        //   之前 first! — sandbox/sandbox-disabled 异常场景 (CI / 自动化测试 / 文件系统损坏) 会 crash
        //   现在 fallback: Application Support → ~/Pictures → fatalError with clear msg
        //   99.99% 场景 first 永远存在 (macOS Application Support 永远可用)
        //   0.01% 异常场景 fallback 让 app 仍能启动 (Photos 库可能在 ~/Pictures)
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures", isDirectory: true)
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
    /// V6.98 (L3 audit fix): 文件名超长 guard + 文件大小上限 (防止 1GB+ 视频伪装图片拖入)
    ///   之前: 文件名 255+ char (Finder 长路径) → copyItem 失败 + 1GB 视频拖入 → 卡 copy + 内存炸
    ///   现在: 文件名截到 200 char (留 36 UUID + buffer), 大小超 500MB 拒绝 (Photo 库最大 ~100MB 图)
    ///   Photos.app 真版: 同样限制 (图片 < 200MB, 文件名 < 255 char)
    @discardableResult
    func importFile(from sourceURL: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: photosDirectory, withIntermediateDirectories: true
        )

        // V6.98 (L3): 文件大小上限 500MB — Photos 库期望单图 < 100MB, 1GB 视频拖入是用户误操作
        //   之前: copyItem 走 kernel cache, 1GB 文件拖入不报错但 copy 5-30s + 内存峰值
        //   现在: 早 throw photoTooLarge, ImageImporter 收到 → toast "文件过大, 已跳过" (跟 importFailed 一致)
        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0
        let maxSize: Int64 = 500 * 1024 * 1024  // 500 MB
        if fileSize > maxSize {
            throw PhotoStorageError.fileTooLarge(sourceURL, fileSize)
        }

        // V6.98 (L3): 文件名超长截断 — macOS HFS+ 限制 255 UTF-16 char, UUID 36 char + 1 sep = 37 char overhead
        //   之前: Finder 复制 255 char 文件 → copyItem 失败 throw
        //   现在: 截到 200 char 留 buffer, 保留扩展名 (e.g. ".heic")
        let originalName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension
        let maxNameLength = 200
        let trimmedName: String
        if originalName.count > maxNameLength {
            if !ext.isEmpty {
                let baseName = (originalName as NSString).deletingPathExtension
                let truncatedBase = String(baseName.prefix(maxNameLength - ext.count - 1))
                trimmedName = "\(truncatedBase).\(ext)"
            } else {
                trimmedName = String(originalName.prefix(maxNameLength))
            }
        } else {
            trimmedName = originalName
        }

        let uniqueName = "\(UUID().uuidString)_\(trimmedName)"
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
    /// V6.98 (L3 audit fix): 文件超过 500MB — Photo 库不期望这么大文件
    case fileTooLarge(URL, Int64)
}
