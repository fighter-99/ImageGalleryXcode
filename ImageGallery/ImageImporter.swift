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

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let photosDir = appSupport.appendingPathComponent("ImageGallery/Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let uniqueName = "\(UUID().uuidString)_\(url.lastPathComponent)"
        let destURL = photosDir.appendingPathComponent(uniqueName)

        do {
            try FileManager.default.copyItem(at: url, to: destURL)
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

// MARK: - 图片删除器

struct ImageDeleter {
    let modelContext: ModelContext

    /// 删除图片（包括磁盘上的文件）
    @discardableResult
    func delete(_ photo: Photo) -> UUID {
        let id = photo.id
        let fileURL = photo.fileURL.standardizedFileURL
        let path = fileURL.path

        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                // 兜底：用 unlink 系统调用
                _ = unlink(path)
            }
        }

        modelContext.delete(photo)
        try? modelContext.save()
        return id
    }
}
