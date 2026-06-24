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

    /// V6.39.1: UserSettings back-ref — startImport 读 defaultImportLocation
    ///   跟 core 同样 weak pattern (避免 retain cycle)
    ///   ContentViewModel wire (跟 modelContext / undoManager 注入同一位置)
    @ObservationIgnored weak var settings: UserSettings?

    /// V6.28.1: toast callback — Core 的 enqueueToast (避免重复 toast queue 实现)
    /// V6.29.1: 加 undoAction 参数 (破坏性操作 Photos.app 撤销范式, 跟 GridViewModel 一致)
    @ObservationIgnored var enqueueToastHandler: (String, ToastView.ToastType, ToastInfo.Duration, _ undoAction: (() -> Void)?) -> Void = { _, _, _, _ in }

    // MARK: - Import 状态字段

    /// V3.6 导入进度 (V5.53 搬过来——startImport/importPhotos 都需要)
    var importProgress: ImportProgress? = nil
    var importDuplicateCheck: ImageImporter.DuplicateCheckResult? = nil
    var pendingImportURLs: [URL] = []

    /// V6.97.6 (M2 audit fix): 导入开始时间 — 用于 stuck 检测 fallback
    ///   场景: SwiftData save fail × N 隐式失败但 importProgress 没清, 用户看到进度条卡住
    ///   修法: 超过 30min 自动清 importProgress + warning toast 提示
    ///   Photos.app 真版行为: import 中途出错会停在错误处, 不自动 reset (用户能手动 cancel)
    ///   ImageGallery 简化方案: 30min 超时自动 reset (避免进度条永久 stuck)
    @ObservationIgnored private var importStartedAt: Date? = nil

    // MARK: - Init

    /// V6.28.1: ImportViewModel init — Core (ContentViewModel) 反向注入 weak ref
    init() {
        startStuckCheckTimer()
    }

    /// V6.97.6 (M2 audit fix): stuck 检测 timer — 每 60s 扫一次 importProgress
    ///   如果 importProgress.isImporting == true && Date().timeIntervalSince(importStartedAt) > 30min
    ///   → 自动 reset importProgress + warning toast 提示
    ///   30min 是经验值: 2666 张 4.6GB 实测 13min, 30min 给 2.3× buffer
    ///   Photos.app 真版用 manual cancel, 我们用 auto timeout (简化 UX, 适合 macOS background app)
    private func startStuckCheckTimer() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)  // 60s
                guard let self else { return }
                guard let startedAt = self.importStartedAt,
                      let progress = self.importProgress,
                      progress.isImporting else {
                    continue
                }
                let elapsed = Date().timeIntervalSince(startedAt)
                if elapsed > 30 * 60 {  // 30 min
                    self.importProgress = nil
                    self.importStartedAt = nil
                    self.enqueueToastHandler(
                        Copy.importStuckTimeoutMessage,
                        .warning,
                        .long,
                        nil
                    )
                }
            }
        }
    }

    // MARK: - 启动导入

    /// ─── 启动导入 ───
    /// V6.39.1: 优先用 settings.defaultImportLocation (LibrarySettingsView 选过的文件夹)
    ///   如果有值且目录仍存在 → 直接 collect + 导入 (跳过 NSOpenPanel)
    ///   如果目录已被移动/删除 → fallback NSOpenPanel + toast 提示用户重新选
    func startImport() {
        // V6.97.5 (C7 audit fix): 重入 guard — lifecycle auto-trigger + toolbar 手动 trigger 不会双 import
        //   之前: ContentView .task 解析 -uitest-import-dir 自动 import, 同时 toolbar 按钮也调 startImport
        //         没有 isImporting 守门, 双 trigger 跑两次 importPhotos (进度混乱, 文件重复)
        //   现在: 如果 importProgress.isImporting == true → 第二次 trigger 早返, 不发第二次 NSOpenPanel
        //   跟 Photos.app 行为一致: 已经在 import 时按 import 按钮 no-op
        guard importProgress?.isImporting != true else { return }

        // V6.22.10 (XCUITest): launch arg bypass NSOpenPanel
        if let dir = uitestImportDirectory {
            let urls = collectImageURLs(in: dir)
            if !urls.isEmpty {
                importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
                importStartedAt = Date()  // V6.97.6: stuck 检测时间戳
                runImportWithDuplicateCheck(urls: urls)
            }
            return
        }

        // V6.39.1: 优先用 settings.defaultImportLocation
        if let urlString = settings?.defaultImportLocation,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            let urls = collectImageURLs(in: url.path)
            if !urls.isEmpty {
                importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
                importStartedAt = Date()  // V6.97.6: stuck 检测时间戳
                runImportWithDuplicateCheck(urls: urls)
                return
            }
            // 目录存在但无图片 — 也走 NSOpenPanel 让用户选别的
        } else if settings?.defaultImportLocation != nil {
            // V6.97.6 (H1 audit fix): 默认位置 stale — 清掉 + toast 提示 + 延迟 0.5s 弹 NSOpenPanel
            //   之前 (V6.39.1): toast + NSOpenPanel 同时弹 — 视觉竞争, 用户不知道 toast 在说什么
            //   现在: 延迟 0.5s 弹 NSOpenPanel, 让 toast 先消化再弹 (用户先看到原因再选目录)
            //   跟 macOS Finder 行为一致: stale path → 静默 fallback (用 toast 替代静默)
            settings?.defaultImportLocation = nil
            enqueueToastHandler(
                Copy.importLocationMissingMessage,
                .warning,
                .normal,
                nil
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showImportPanel()
            }
            return
        }

        showImportPanel()
    }

    /// V6.97.6 (H1 refactor): 抽 showImportPanel — 默认位置 stale 路径 + 普通路径共用
    ///   避免重复 24 行 NSOpenPanel 配置
    private func showImportPanel() {

        let panel = NSOpenPanel()
        panel.title = Copy.importPanelTitle
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        // V6.98 (L2 audit fix): 加 .rawImage — 之前 [.image] 是 umbrella UTI 不含 RAW
        //   现在 [.image, .rawImage] 让 NSOpenPanel 显示 RAW 文件可选
        //   摄影师常用 CR2/CR3/NEF/ARW/DNG/RW2 直入图库, 之前必须先转 JPG
        panel.allowedContentTypes = [.image, .rawImage]

        guard panel.runModal() == .OK else { return }
        importStartedAt = Date()  // V6.97.6: 启动时间戳用于 stuck 检测

        // V6.97.5 (C8 audit fix): 用户 OK 但 panel.urls 空 (0 张图) — 早返 + toast 提示
        //   之前: 0 张图走 runImportWithDuplicateCheck → importProgress 设了又清, 用户 0 反馈
        //   现在: 直接 toast "未选择任何图片", 不进 import flow
        //   跟 Photos.app 行为一致: 0 选择 = 0 反馈
        guard !panel.urls.isEmpty else {
            enqueueToastHandler(
                Copy.importNoFilesSelected,
                .info,
                .normal,
                nil
            )
            return
        }

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
                await importPhotos(urls: urls)
            }
        }
    }

    func confirmSkipDuplicates() {
        let existing = Set(importDuplicateCheck?.existing ?? [])
        let newURLs = pendingImportURLs.filter { !existing.contains($0) }
        importDuplicateCheck = nil
        pendingImportURLs = []
        if !newURLs.isEmpty {
            // V6.97.5: importPhotos 是 async, 父函数 confirmSkipDuplicates 调在 SwiftUI button action (sync 上下文)
            //   用 Task { @MainActor } 包装 await, 跟 runImportWithDuplicateCheck 同 pattern
            Task { @MainActor in
                await importPhotos(urls: newURLs)
            }
        }
    }

    func confirmImportAllDuplicates() {
        let allURLs = pendingImportURLs
        importDuplicateCheck = nil
        pendingImportURLs = []
        // V6.97.5: importPhotos 是 async, 同样 Task 包装
        Task { @MainActor in
            await importPhotos(urls: allURLs)
        }
    }

    func cancelDuplicateImport() {
        importDuplicateCheck = nil
        pendingImportURLs = []
    }

    /// V3.6.24: 实际跑导入
    /// V5.15: 接 4 参数 onProgress + 合并 summary toast
    /// V6.10: [self] → [weak self]
    /// V6.28.1: currentFolder 走 core?.grid.currentFolder (Core 不再持该字段)
    func importPhotos(urls: [URL]) async {
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
        let result = await importer.importURLs(urls)
        importStartedAt = nil  // V6.97.6: 导入完成清 stuck 检测时间戳 (timer 不再 reset importProgress)
        if result.inserted > 0 && result.hasFailures {
            enqueueToastHandler(Copy.importedPartial(inserted: result.inserted, failed: result.failureCount), .info, .normal, nil)
        } else if result.inserted > 0 {
            enqueueToastHandler(Copy.imported(result.inserted), .success, .normal, nil)
        }
        // V6.98 (L3 audit fix): 区分 fileTooLarge 跟 importFailed, 不同 toast 文案
        //   之前: 所有失败都是 importFailed (用户感到 import 出错)
        //   现在: tooLarge 是用户拖了视频伪装图片, 文案 "文件过大已跳过" 比 "导入失败" 更准确
        for (url, error) in result.failures where result.inserted == 0 {
            if case ImportError.tooLarge(let filename, _) = error {
                enqueueToastHandler(Copy.importFileTooLarge(filename), .warning, .long, nil)
            } else {
                enqueueToastHandler(Copy.importFailed(url.lastPathComponent), .error, .long, nil)
            }
        }
    }

    /// V4.49.0: 拖入时支持的图像扩展名
    /// V6.98 (L2 audit fix): 加 RAW 格式 — 跟 ImageImporter.supportedExtensions 一致 (避免 V6.20.0 拆 Import 业务时漏)
    ///   6 RAW: cr2/cr3 (Canon), nef (Nikon), arw (Sony), dng (Adobe/iPhone Pro), rw2 (Panasonic)
    static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        "cr2", "cr3", "nef", "arw", "dng", "rw2"
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
