//
//  ImageImporter.swift
//  ImageGallery
//
//  图片导入器。把导入逻辑独立出来，支持进度回调。
//

import Foundation
import ImageIO
import CryptoKit
import SwiftData

// 导入进度信息
struct ImportProgress: Equatable {
    var current: Int = 0
    var total: Int = 0
    var isImporting: Bool = false

    var fraction: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }

    var percentText: String {
        guard total > 0 else { return "准备中..." }
        let percent = Int(fraction * 100)
        return "\(current)/\(total) · \(percent)%"
    }
}

struct ImageImporter {
    let modelContext: ModelContext
    /// 导入时自动归入的目标文件夹（nil = 不归类）
    let folder: Folder?
    /// 进度回调：(current, total)
    var onProgress: ((Int, Int) -> Void)? = nil

    private let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"
    ]

    // MARK: - V3.6.24 NEW: 重复检测

    /// 重复检测结果（V3.6.24）
    /// 导入前扫现有 photo 的 fileHash + 算新 urls 的 fileHash，返回已存在的 URL
    struct DuplicateCheckResult {
        let existing: [URL]   // 已存在（fileHash 匹配）的源 URL
        let newCount: Int      // 真正新文件的数量
        let totalCount: Int    // 总数

        var hasDuplicates: Bool { !existing.isEmpty }
    }

    /// 扫现有 photo 的 fileHash + 算新 urls 的 fileHash，找出已存在的
    /// 性能：fileHash 算 SHA256（小文件几十 ms），50 张图 ~2s
    /// 异步：不在 main thread 跑算 hash（V3.6.24 简单版同步跑）
    static func checkDuplicates(
        newURLs: [URL],
        in modelContext: ModelContext
    ) -> DuplicateCheckResult {
        // 1. 收集所有现有 photo 的 fileHash → URL 映射
        let existingHashes = (try? modelContext.fetch(
            FetchDescriptor<Photo>()
        )) ?? []
        let existingByHash = Dictionary(
            grouping: existingHashes.compactMap { photo -> (String, Photo)? in
                guard let hash = photo.fileHash else { return nil }
                return (hash, photo)
            },
            by: { $0.0 }
        )

        // 2. 算新 urls 的 fileHash
        var existing: [URL] = []
        var newCount = 0
        for url in newURLs {
            guard let hash = computeFileHashSync(at: url) else {
                newCount += 1  // 算不了 hash 当成新文件
                continue
            }
            if existingByHash[hash] != nil {
                existing.append(url)
            } else {
                newCount += 1
            }
        }
        return DuplicateCheckResult(
            existing: existing,
            newCount: newCount,
            totalCount: newURLs.count
        )
    }

    /// 同步算 SHA256（V3.6.24 简单版，不做 actor 隔离）
    /// 复用现有 computeFileHash 逻辑但不需要 Photo context
    private static func computeFileHashSync(at url: URL) -> String? {
        var hasher = SHA256()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 1024 * 1024
        while true {
            let chunk: Data?
            if #available(macOS 10.15.4, *) {
                chunk = try? handle.read(upToCount: chunkSize)
            } else {
                chunk = handle.readData(ofLength: chunkSize)
            }
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 导入一组 URL，自动处理文件和文件夹
    func importURLs(_ urls: [URL]) {
        print("📥 importURLs 收到 \(urls.count) 个 URL")
        for url in urls {
            print("   - \(url.path)")
        }

        // 1. 先收集所有要导入的文件（递归文件夹）
        var allFiles: [URL] = []
        for url in urls {
            collectFiles(at: url, into: &allFiles)
        }

        print("📂 展开后共 \(allFiles.count) 个文件")
        for (i, file) in allFiles.enumerated() {
            print("   [\(i+1)/\(allFiles.count)] \(file.lastPathComponent)")
        }

        let total = allFiles.count
        onProgress?(0, total)

        // 2. 逐个导入
        for (index, url) in allFiles.enumerated() {
            importSingleImage(at: url)
            onProgress?(index + 1, total)
        }
    }

    // MARK: - 私有方法

    /// 递归收集所有图片文件
    private func collectFiles(at url: URL, into collection: inout [URL]) {
        var isDir: ObjCBool = false
        let isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue

        if isDirectory {
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    collectFiles(at: fileURL, into: &collection)
                }
            }
        } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
            collection.append(url)
        }
    }

    private func importSingleImage(at url: URL) {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            print("⏭️ 跳过不支持的格式: \(url.lastPathComponent)")
            return
        }

        // V3.6: 用 PhotoStorage 服务复制文件（替代原硬编码路径）
        let destURL: URL
        do {
            destURL = try PhotoStorage.shared.importFile(from: url)
        } catch {
            print("❌ 复制失败: \(url.lastPathComponent) - \(error.localizedDescription)")
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
        var width = 0, height = 0

        if let imageSource = CGImageSourceCreateWithURL(destURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        }

        let fileHash = computeFileHash(at: destURL)

        let photo = Photo(
            filename: url.lastPathComponent,
            fileURL: destURL,
            fileSize: fileSize,
            width: width,
            height: height
        )
        photo.folder = folder
        photo.fileHash = fileHash
        modelContext.insert(photo)
        do {
            try modelContext.save()
            print("✅ 已导入: \(url.lastPathComponent)")
        } catch {
            print("❌ 保存失败: \(error.localizedDescription)")
        }
    }

    private func computeFileHash(at url: URL) -> String? {
        var hasher = SHA256()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 1024 * 1024
        while true {
            let chunk: Data?
            if #available(macOS 10.15.4, *) {
                chunk = try? handle.read(upToCount: chunkSize)
            } else {
                chunk = handle.readData(ofLength: chunkSize)
            }
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
