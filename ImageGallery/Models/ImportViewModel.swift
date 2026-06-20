//
//  ImportViewModel.swift
//  ImageGallery
//
//  V6.28.1 NEW: 从 ContentViewModel 拆出的 Import 业务模型
//    Import 业务 — 启动导入 / 拖入导入 / 重复检测 / 批量导入 / 进度跟踪
//    持 Core back-ref (weak) 用于 modelContext + Grid.currentFolder
//    + enqueueToastHandler closure 注入 — Core toast queue 不重复实现
//
//  拆分依据 (memory V6.28 follow-up):
//    ContentViewModel V6.28 后 642 行 → 拆 ImportViewModel (~200 行)
//    Import 业务独立 .onChange 追踪 progress → 不污染 Core observation graph
//    测试隔离: ImportViewModel 单测更聚焦 (progress callback / duplicate check / handleDrop)
//
//  关键约束:
//    - @MainActor + @Observable + final class (同 ContentViewModel / GridViewModel)
//    - weak var core (避免 retain cycle — ContentViewModel 持 importVM strong, importVM 持 core weak)
//    - Grid.currentFolder 经 core?.grid.currentFolder 访问 (避免持 grid 引用导致 chain)
//    - enqueueToastHandler closure 注入 — Core 的 toast 系统不重复实现
//
//  不在 ImportViewModel (仍 ContentViewModel):
//    - sidebarSelection / filterState / viewMode / window (Core)
//    - selection / visiblePhotos / batch ops / smartFolder (GridViewModel)
//    - toastQueue / undoManager / enqueueToast (Core services)
//
//  阶段:
//    - V6.28.1-1: skeleton + Import 业务抽取 ✓
//    - V6.28.1-2: caller files file-by-file 迁移 model.X → model.importVM.X
//    - V6.28.1-3: tests 迁移 + 验证 0 regression
//

import Foundation
import SwiftUI
import SwiftData
import ImageIO  // importPhotos 用 CGImageSource
import UniformTypeIdentifiers  // handleDrop fileURL promise

/// V6.28.1: Import 业务模型 — 启动 / 拖入 / 重复检测 / 批量导入 / 进度
@MainActor
@Observable
final class ImportViewModel {
    /// V6.28.1: Core back-ref (weak 避免 retain cycle)
    ///   用途: modelContext + enqueueToast + grid.currentFolder
    @ObservationIgnored weak var core: ContentViewModel?

    /// V6.28.1: toast callback — Core 的 enqueueToast (避免重复 toast queue 实现)
    /// V6.29.1: 加 undoAction 参数 (破坏性操作 Photos.app 撤销范式, 跟 GridViewModel 一致)
    @ObservationIgnored var enqueueToastHandler: (String, ToastView.ToastType, ToastInfo.Duration, _ undoAction: (() -> Void)?) -> Void = { _, _, _, _ in }

    // MARK: - Import 状态字段

    /// V3.6 导入进度 (V5.53 搬过来——startImport/importPhotos 都需要)
    var importProgress: ImportProgress? = nil
    var importDuplicateCheck: ImageImporter.DuplicateCheckResult? = nil
    var pendingImportURLs: [URL] = []

    // MARK: - Init

    /// V6.28.1: ImportViewModel init — Core (ContentViewModel) 反向注入 weak ref
    init() {}

    // MARK: - 启动导入

    /// ─── 启动导入 ───
    func startImport() {
        // V6.22.10 (XCUITest): launch arg bypass NSOpenPanel
        if let dir = uitestImportDirectory {
            let urls = collectImageURLs(in: dir)
            if !urls.isEmpty {
                importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
                runImportWithDuplicateCheck(urls: urls)
            }
            return
        }

        let panel = NSOpenPanel()
        panel.title = "选择图片或文件夹"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }

        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        runImportWithDuplicateCheck(urls: panel.urls)
    }

    // V6.22.10 (XCUITest): launch arg 解析 helper
    private var uitestImportDirectory: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-uitest-import-dir"),
              idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    // V6.22.10 (XCUITest): 读目录里所有图片 URL
    private func collectImageURLs(in dirPath: String) -> [URL] {
        let dir = URL(fileURLWithPath: dirPath)
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents.filter { imageExts.contains($0.pathExtension.lowercased()) }
    }

    /// Finder 拖入导入
    func handleDropImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        runImportWithDuplicateCheck(urls: urls)
    }

    /// V3.6.24: 扫现有 photo + 算新 url fileHash
    /// V3.6.27: 改用 async 版本
    /// V6.11: [weak self] + guard let self——V6.10 C4 修了 importPhotos, runImportWithDuplicateCheck 同 pattern 漏
    func runImportWithDuplicateCheck(urls: [URL]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let modelContext = core?.modelContext else { return }
            let check = await ImageImporter.checkDuplicatesAsync(
                newURLs: urls,
                in: modelContext
            ) { [weak self] current, total in
                self?.importProgress = ImportProgress(current: current, total: total, isImporting: true)
            }
            importProgress = nil
            if check.hasDuplicates {
                pendingImportURLs = urls
                importDuplicateCheck = check
            } else {
                importPhotos(urls: urls)
            }
        }
    }

    func confirmSkipDuplicates() {
        let existing = Set(importDuplicateCheck?.existing ?? [])
        let newURLs = pendingImportURLs.filter { !existing.contains($0) }
        importDuplicateCheck = nil
        pendingImportURLs = []
        if !newURLs.isEmpty { importPhotos(urls: newURLs) }
    }

    func confirmImportAllDuplicates() {
        let allURLs = pendingImportURLs
        importDuplicateCheck = nil
        pendingImportURLs = []
        importPhotos(urls: allURLs)
    }

    func cancelDuplicateImport() {
        importDuplicateCheck = nil
        pendingImportURLs = []
    }

    /// V3.6.24: 实际跑导入
    /// V5.15: 接 4 参数 onProgress + 合并 summary toast
    /// V6.10: [self] → [weak self]
    /// V6.28.1: currentFolder 走 core?.grid.currentFolder (Core 不再持该字段)
    func importPhotos(urls: [URL]) {
        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        guard let modelContext = core?.modelContext else { return }
        let importer = ImageImporter(
            modelContext: modelContext,
            folder: core?.grid.currentFolder
        ) { [weak self] current, total, inserted, failureCount in
            Task { @MainActor in
                guard let self else { return }
                self.importProgress = ImportProgress(
                    current: current, total: total,
                    inserted: inserted, failureCount: failureCount,
                    isImporting: true
                )
                if current >= total && total > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let p = self.importProgress, p.current >= p.total {
                        self.importProgress = nil
                    }
                }
            }
        }
        let result = importer.importURLs(urls)
        if result.inserted > 0 && result.hasFailures {
            enqueueToastHandler("已导入 \(result.inserted) 张，\(result.failureCount) 张失败", .info, .normal, nil)
        } else if result.inserted > 0 {
            enqueueToastHandler("已导入 \(result.inserted) 张图片", .success, .normal, nil)
        }
        for (url, _) in result.failures where result.inserted == 0 {
            enqueueToastHandler("导入失败：\(url.lastPathComponent)", .error, .long, nil)
        }
    }

    /// V4.49.0: 拖入时支持的图像扩展名
    static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"
    ]

    /// Finder 拖拽导入
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                defer { group.leave() }
                guard let data = data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let expanded = Self.expandFolders([url])
                lock.lock()
                urls.append(contentsOf: expanded)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let imageURLs = urls.filter { Self.supportedImageExtensions.contains($0.pathExtension.lowercased()) }
            guard !imageURLs.isEmpty else { return }
            self.runImportWithDuplicateCheck(urls: imageURLs)
        }

        return true
    }

    /// V4.49.0: 递归展开文件夹
    static func expandFolders(_ urls: [URL]) -> [URL] {
        // V6.09: 防 symlink 循环——contentsOfDirectory + 递归无 cycle 检测
        var visited = Set<URL>()
        var result: [URL] = []
        expandFolders(urls, into: &result, visited: &visited)
        return result
    }

    private static func expandFolders(_ urls: [URL], into result: inout [URL], visited: inout Set<URL>) {
        let fileManager = FileManager.default
        for url in urls {
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            if visited.contains(canonical) { continue }
            visited.insert(canonical)

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let contents = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    expandFolders(contents, into: &result, visited: &visited)
                }
            } else {
                result.append(url)
            }
        }
    }
}
