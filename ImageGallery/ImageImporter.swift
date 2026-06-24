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
import os  // V6.22.5: 替 8 个 print, 用 Logger.importer

// 导入进度信息
// V5.15: 加 inserted + failureCount 字段——UI 显示"X/Y · N 失败"更准确
//   inserted: 成功导入数（不含 unsupported format skip）
//   failureCount: 失败数（importSingleImage 返回 Error 的）
struct ImportProgress: Equatable {
    var current: Int = 0
    var total: Int = 0
    var inserted: Int = 0
    var failureCount: Int = 0
    var isImporting: Bool = false

    var fraction: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }

    /// V6.37.10: 状态条显示用——"导入中 8/15 · 1 失败"
    var displayText: String {
        guard total > 0 else { return Copy.importProgressIdle }
        var s = Copy.importProgressActive(inserted, total: total)
        if failureCount > 0 { s += Copy.importProgressFailures(failureCount) }
        return s
    }

    /// V5.15 之前用的 percentText——保留向后兼容
    var percentText: String {
        guard total > 0 else { return Copy.importPreparing }
        let percent = Int(fraction * 100)
        return "\(current)/\(total) · \(percent)%"
    }
}

struct ImageImporter {
    let modelContext: ModelContext
    /// 导入时自动归入的目标文件夹（nil = 不归类）
    let folder: Folder?
    /// V5.15: 进度回调签名 (current, total, inserted, failureCount)
    ///   current/total 跟踪文件索引（incl. unsupported skip）
    ///   inserted/failureCount 跟踪结果数——UI 显示更准
    var onProgress: ((Int, Int, Int, Int) -> Void)? = nil

    // V6.98 (L2 audit fix): 加 RAW 格式支持 — 之前 10 种只覆盖普通图像, RAW (专业摄影常用) NSOpenPanel 直接禁用
    //   6 种主流 RAW: Canon CR2/CR3, Nikon NEF, Sony ARW, Adobe DNG, Panasonic RW2
    //   之前: 摄影师拖入 RAW → NSOpenPanel 不允许选 → 必须先转 JPG 才能入库, 体验差
    //   现在: NSOpenPanel [.image, .rawImage] + supportedExtensions 包含 6 RAW → 拖入直入
    //   副作用: importSingleImage 读 CGImageSource 属性 (width/height), RAW 也能解 (Mac OS 内置 RAW codec)
    private let supportedExtensions: Set<String> = [
        // 普通图像 (V3.6 起)
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        // V6.98: RAW 格式 (6 种主流)
        "cr2", "cr3",  // Canon
        "nef",         // Nikon
        "arw",         // Sony
        "dng",         // Adobe (iPhone Pro RAW 也存 DNG)
        "rw2"          // Panasonic
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

    /// V3.6.27 NEW: 异步版本（在后台 actor 跑 SHA256，不阻塞 main thread）
    /// - 进度回调 onProgress(current, total) — 算完一张调一次
    /// - onProgress 在 @MainActor 上下文调用（content view 用 await + 闭包自动 MainActor 跳）
    /// V6.62 (P4.4): 删 V3.6.27 同步版本 (37 LOC dead code) — 0 caller since V3.6.27 async 引入
    static func checkDuplicatesAsync(
        newURLs: [URL],
        in modelContext: ModelContext,
        onProgress: @MainActor @Sendable @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> DuplicateCheckResult {
        // 1. 先在主线程拉现有 photo（SwiftData 限制）
        // V6.59 (audit P2.3): 跟 sync 版本同 predicate `fileHash != nil` — 50x+ 提速
        let existingHashes = (try? modelContext.fetch(
            FetchDescriptor<Photo>(predicate: #Predicate { $0.fileHash != nil })
        )) ?? []
        let existingByHash = Dictionary(
            grouping: existingHashes.compactMap { photo -> (String, Photo)? in
                guard let hash = photo.fileHash else { return nil }
                return (hash, photo)
            },
            by: { $0.0 }
        )

        // 2. 后台 actor 算新 urls 的 fileHash（V3.6.27 关键：不阻塞主线程）
        let total = newURLs.count
        var existing: [URL] = []
        var newCount = 0

        await withTaskGroup(of: (Int, URL?, String?).self) { group in
            // 2a. 并发派发所有 hash 任务（actor 隔离 + 并行）
            for (index, url) in newURLs.enumerated() {
                group.addTask(priority: .userInitiated) {
                    let hash = Self.computeFileHashSync(at: url)
                    return (index, url, hash)
                }
            }
            // 2b. 串行收集结果 + 报告进度
            for await (index, url, hash) in group {
                guard let url = url else { continue }
                if let hash = hash, existingByHash[hash] != nil {
                    existing.append(url)
                } else {
                    newCount += 1
                }
                // 报告进度（MainActor）
                await onProgress(index + 1, total)
            }
        }

        return DuplicateCheckResult(
            existing: existing,
            newCount: newCount,
            totalCount: total
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

    /// V5.13: 注入 PhotoStorage 便于测试（默认 .shared 向后兼容）
    var storage: PhotoStorage = .shared

    /// 导入一组 URL，自动处理文件和文件夹
    /// V5.13: 返回 ImportResult——inserted 数 + failures [(URL, Error)]，调用方接 toast
    /// V6.97.5 (H2 audit fix): 改 async + Task.detached 跑后台 thread, 避免 1.3GB import 阻塞主线程
    ///   之前: 同步 importURLs 在主线程跑 2666 张: collectFiles 递归 + importSingleImage 串行 (复制 + SHA256 + CGImageSource)
    ///         100 张大图实测 25-90s 主线程冻结 (V6.26 audit 报), 2666 张 13min+ 完全卡死
    ///   现在: 整段 importURLs 跑 Task.detached, onProgress closure 内部 dispatch 回 MainActor
    ///         调用方 await, 进度回调自动到 main thread, UI 不冻结
    ///   跟 V6.26 audit 修法一致: actor / Task 后台化, progress dispatch 回 main
    @discardableResult
    func importURLs(_ urls: [URL]) async -> ImportResult {
        // V6.22.5: 替 print → Logger.importer (8 个 print 全替换)
        //   .debug 级 (默认不显示, 只有 Console.app 启用 Info 才出)
        Logger.importer.debug("importURLs 收到 \(urls.count, privacy: .public) 个 URL")
        for url in urls {
            Logger.importer.debug("  - \(url.path, privacy: .public)")
        }

        // V6.97.5: 整段逻辑放 Task.detached (后台 thread), 避免阻塞主线程
        return await Task.detached(priority: .userInitiated) { [self] in
            // 1. 先收集所有要导入的文件（递归文件夹）
            var allFiles: [URL] = []
            for url in urls {
                collectFiles(at: url, into: &allFiles)
            }

            Logger.importer.debug("展开后共 \(allFiles.count, privacy: .public) 个文件")

            let total = allFiles.count
            // onProgress 是调用方传的 closure, 可能更新 UI, 必须 MainActor dispatch
            await MainActor.run { onProgress?(0, total, 0, 0) }

            // 2. 逐个导入——V5.13: 收集 failures 给调用方
            var inserted = 0
            var failures: [(url: URL, error: Error)] = []
            for (index, url) in allFiles.enumerated() {
                if let error = importSingleImage(at: url) {
                    failures.append((url, error))
                } else {
                    inserted += 1
                }
                // V5.15: 传 4 参数 (current, total, inserted, failureCount)
                // 同样 MainActor dispatch (2666 张 × 60Hz 进度 = 大量 UI 更新)
                let currentProgress = index + 1
                let currentInserted = inserted
                let currentFailures = failures.count
                await MainActor.run {
                    onProgress?(currentProgress, total, currentInserted, currentFailures)
                }
            }

            // V4.36.x: 记录到最近导入——File > Open Recent 菜单显示
            await MainActor.run {
                RecentPhotosStore.shared.recordImports(allFiles)
            }

            return ImportResult(inserted: inserted, failures: failures)
        }.value
    }

    // MARK: - 私有方法

    /// 递归收集所有图片文件
    private func collectFiles(at url: URL, into collection: inout [URL]) {
        // V6.09: 防 symlink 循环——FileManager.enumerator 默认递归 + 本函数又递归,
        //   拖入含 symlink 自身环的文件夹会无限递归栈溢出。用 visited Set 跟踪已访问的
        //   规范化路径 (resolvingSymlinksInPath 解析 symlink), 命中即跳过
        var visited = Set<URL>()
        collectFiles(at: url, into: &collection, visited: &visited)
    }

    private func collectFiles(at url: URL, into collection: inout [URL], visited: inout Set<URL>) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if visited.contains(canonical) { return }
        visited.insert(canonical)

        var isDir: ObjCBool = false
        let isDirectory = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue

        if isDirectory {
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    // V6.98 (L1 audit fix): file+dir 混选 — folder 递归时按扩展名过滤
                    //   之前: 把所有文件 push, 包含 .DS_Store / .txt / Thumb.db 等无关文件
                    //         然后 importSingleImage 一个个看 supportedExtensions 跳过, 3666 次 IO read attribute
                    //   现在: 递归时直接 filter 扩展名, 无关文件不 push, 收集阶段就过滤
                    //   跟 collectImageURLs (V6.22.10 launch arg) 行为一致
                    if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                        collectFiles(at: fileURL, into: &collection, visited: &visited)
                    }
                }
            }
        } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
            collection.append(url)
        }
    }

    /// V5.13: 返回 Optional<Error>——nil = 成功（或不支持格式跳过），非 nil = 失败
    private func importSingleImage(at url: URL) -> Error? {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            Logger.importer.debug("跳过不支持的格式: \(url.lastPathComponent, privacy: .public)")
            return nil  // 不支持格式 = 跳过而非失败
        }

        // V3.6: 用 PhotoStorage 服务复制文件（替代原硬编码路径）
        // V5.13: 用注入的 storage（默认 .shared）便于测试
        // V6.98 (L3 audit fix): 区分 fileTooLarge 跟 copyFailed, 不同错误不同处理
        //   之前: 所有 storage 错误都是 error, ImportViewModel 显示 importFailed
        //   现在: fileTooLarge 是用户拖了视频伪装图片, 单独标 .tooLarge 让 caller 用 importFileTooLarge 文案
        let destURL: URL
        do {
            destURL = try storage.importFile(from: url)
        } catch let PhotoStorageError.fileTooLarge(_, size) {
            Logger.importer.warning("文件过大已跳过: \(url.lastPathComponent, privacy: .public) (\(size) bytes)")
            return ImportError.tooLarge(url.lastPathComponent, size)
        } catch {
            Logger.importer.error("复制失败: \(url.lastPathComponent, privacy: .public) - \(error.localizedDescription, privacy: .public)")
            return error
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
            Logger.importer.info("已导入: \(url.lastPathComponent, privacy: .public)")
            return nil
        } catch {
            Logger.importer.error("保存失败: \(error.localizedDescription, privacy: .public)")
            return error
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

// MARK: - V5.13: ImportResult

/// V5.13: 导入结果——inserted 数 + 失败列表
/// - inserted: 成功导入数（含跳过的不支持格式——不算失败）
/// - failures: (URL, Error) 对——调用方接 toast
struct ImportResult {
    let inserted: Int
    let failures: [(url: URL, error: Error)]

    var hasFailures: Bool { !failures.isEmpty }
    var failureCount: Int { failures.count }
}

/// V6.98 (L3 audit fix): 特定导入错误 — 让 caller (ImportViewModel) 区分错误类型给不同 toast 文案
enum ImportError: Error {
    /// 文件 > 500MB — Photo 库不期望这么大 (典型是用户拖了视频伪装图片)
    case tooLarge(String, Int64)  // (filename, bytes)
}
