//
//  ContentViewModel.swift
//  ImageGallery
//
//  V5.52: ContentView 的 @Observable 业务模型 (单一根)
//  V6.28: 大拆分 — Grid 业务迁 GridViewModel (memory P1 #30)
//    ContentViewModel 现在持 Core (settings / sidebarSelection / filterState / window / toastQueue / undoManager)
//    + Import 业务 (startImport / handleDrop / importPhotos)
//    + 子模型 GridViewModel (selection / searchText / visiblePhotos / batch ops / single-photo ops)
//
//  关键约束 (V5.52 起稳定):
//    - @MainActor + @Observable + final class (macOS 14+ 已是项目标准)
//    - modelContext init 注入 (不能 @Environment 因为非 View)
//    - @Query 不能进 class——由 view 通过 .onChange 推过来 (4 个 @ObservationIgnored 缓存全在 GridViewModel)
//    - 12 @AppStorage 不能进 class——由 view 推到 Settings 字段 (ContentViewModel + GridViewModel 共持 settings)
//    - ToolbarController.shared 12 个闭包原本 [self] capture struct value copy——现在 capture [model] (class stable ref)
//    - V6.28: Grid 业务 (selection/visiblePhotos/batch) 走 model.grid.X()——Core 业务仍 model.X()
//
//  拆分结构:
//    ContentViewModel (Core + Import) ~600 行
//      ├ settings / modelContext / sidebarSelection / filterState
//      ├ titlebarAccessory / toastQueue / toastTask / undoManager
//      ├ importProgress / importDuplicateCheck / pendingImportURLs
//      ├ viewMode / appearanceMode / accentColor / layoutMode (settings 镜像)
//      ├ sidebarColumnWidth / detailColumnWidth (settings 镜像)
//      ├ configureToolbar / checkStorage / createFolder / createSmartFolder
//      ├ toggleSortDirection / serializeSelection / restoreSelection
//      ├ enqueueToast / scheduleDismiss / scheduleDismissToast / showToast
//      ├ startImport / handleDropImport / runImportWithDuplicateCheck
//      ├ confirmSkipDuplicates / confirmImportAllDuplicates / cancelDuplicateImport / importPhotos
//      ├ supportedImageExtensions static / handleDrop / expandFolders static
//      └ grid: GridViewModel ← 子模型
//
//    GridViewModel (Grid 业务) ~900 行
//      ├ selection / searchText / sortOption / thumbnailSize
//      ├ showingBatchDeleteConfirm / showingBatchRenameSheet / sharingURLs
//      ├ lastShareRequestTime + shouldThrottleShareRequest
//      ├ showingNewSmartFolderSheet / pendingSmartFolderFilter / showingEmptyTrashConfirm
//      ├ showingNewFolderAlert / newFolderName / immersivePhoto / immersiveIndex / scrollAnchorPhotoID
//      ├ allPhotos / folders / allTags / smartFoldersCache (@Query 缓存)
//      ├ currentFolder / currentTag / currentSmartFolder / smartFolderFilter (sidebar 派生)
//      ├ filterUnfiled/Duplicates/Recent7Days/LargeFiles/InTrash/InDuplicates
//      ├ resolvedSingle / singleSelectedPhoto / currentIndex / canPrev / canNext / isMultiSelect
//      ├ trimmedSearch / visiblePhotos / totalSizeFormatted / selectedTotalSize
//      ├ trashedCount / trashedTotalSize / libraryStats / duplicateGroupCount/PurgeableCount/Size
//      ├ representativePhoto / currentViewTitle / currentViewSubtitle / searchFieldLeadingOffset
//      ├ batchDeleteTitle / duplicateDialogTitle
//      ├ copyToPasteboard / shareSelectedURLs / rotateSelected / speakSelection
//      ├ enterImmersive / enterImmersiveFromSelection / resetFilters / handleDelete / handleTap
//      ├ goPrev / goNext / zoomIn / zoomOut / resetThumbnailSize / showQuickLook
//      ├ clearSelectionOnFilterChange / deleteSinglePhoto
//      ├ batchDelete / batchMove / batchAddTag / batchRename / batchSetRating / batchExport
//      ├ performOnSelectedTrash / restoreSelectedFromTrash / permanentDeleteSelected
//      ├ emptyTrash / keepNewestPerDuplicateGroup
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os  // 启动清理 / Trash retention log (V6.22.5)
import ImageIO  // importPhotos 用 CGImageSource

/// V6.28: ContentView 的业务模型 — Core + Import, Grid 拆到 GridViewModel
@MainActor
@Observable
final class ContentViewModel {
    /// V5.52-2: 13 keys UserDefaults 镜像 (V5.58-1 init 从 UserDefaults 读)
    /// V5.59-1: var → let + 接受外部注入 (默认 UserSettings() 兼容现有测试)
    ///   ImageGalleryApp.sharedSettings 传同一引用进来, ContentViewModel + GridViewModel 与 menu/SettingsView 共享
    let settings: UserSettings

    /// V5.52-3: modelContext 由 .task 注入
    /// V6.28: GridViewModel 经 core?.modelContext 读取 (避免双 .onChange 同步)
    @ObservationIgnored var modelContext: ModelContext? = nil

    // MARK: - V6.28: Grid 子模型

    /// V6.28: Grid 业务 — 选择 / 可见照片 / 单张操作 / 批量操作 / 缩放 / 排序
    ///   caller 走 model.grid.selection / model.grid.visiblePhotos / model.grid.handleDelete() 等
    let grid: GridViewModel

    // MARK: - Core 字段

    /// V5.59-2: init 时从 settings.sidebarSelection 反序列化
    var sidebarSelection: SidebarSelection? = nil
    var filterState = FilterState()
    /// V3.6 导入进度 (V5.53 搬过来——startImport/importPhotos 都需要)
    var importProgress: ImportProgress? = nil
    var titlebarAccessory: TitlebarAccessoryController? = nil
    var toastQueue: [ToastInfo] = []
    var toastTask: Task<Void, Never>? = nil
    var storageErrorMessage: String? = nil

    /// V5.55-2: P0 滚动位置保留
    /// 绑 SwiftUI .scrollPosition(id:)——滚动时自动更新
    /// .onChange 同步到 settings.scrollAnchorPhotoID (持久化)
    /// 启动时 .task 读 settings.scrollAnchorPhotoID 恢复
    /// 字符串 (UUID) 而非 UUID?——SwiftUI Binding<String?> 兼容
    var scrollAnchorPhotoID: String? = nil

    var undoManager = ImageGalleryUndoManager()

    /// V5.59-2: sidebarColumnWidth/detailColumnWidth 改为 computed 绑 settings
    ///   dragStartWidth 是临时态, 保留 stored
    var sidebarColumnWidth: CGFloat {
        get { CGFloat(settings.sidebarColumnWidth) }
        set { settings.sidebarColumnWidth = Double(newValue) }
    }
    var detailColumnWidth: CGFloat {
        get { CGFloat(settings.detailColumnWidth) }
        set { settings.detailColumnWidth = Double(newValue) }
    }
    var sidebarDragStartWidth: CGFloat = 220
    var detailDragStartWidth: CGFloat = 360

    // MARK: - V6.28: Import 字段

    var importDuplicateCheck: ImageImporter.DuplicateCheckResult? = nil
    var pendingImportURLs: [URL] = []

    // MARK: - Settings 镜像 wrapper

    /// V3.6.13: viewMode 包装 (从 viewModeRaw 字符串解析)
    var viewMode: ViewMode {
        get { ViewMode(rawValue: settings.viewModeRaw) ?? .grid }
        set {
            settings.viewModeRaw = newValue.rawValue
            // V6.22.6 (Bug 1): 反向同步 layoutMode — 修 "工具栏模式跟实际视图不同步" bug
            switch newValue {
            case .list:     self.layoutMode = .list
            case .grid:     self.layoutMode = .squareFit
            case .timeline: break  // timeline 不动 layoutMode
            }
        }
    }

    /// V3.6.22: 外观模式
    var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: settings.appearanceMode) ?? .system
    }

    /// V4.13.0: 强调色 (从 accentColorID 解析)
    var accentColor: AccentColor {
        AccentColor(rawValue: settings.accentColorID) ?? .system
    }

    /// V5.17: 缩略图布局模式 (从 storedLayoutModeRaw 解析)
    var layoutMode: ThumbnailLayoutMode {
        get { ThumbnailLayoutMode(rawValue: settings.thumbnailLayoutMode) ?? .defaultValue }
        set { settings.thumbnailLayoutMode = newValue.rawValue }
    }

    // MARK: - 列宽 (columnLayout 内部用——MainSplitView 接收 ColumnLayoutState)

    /// V3.5.12: 列宽约束常量
    let sidebarMinWidth: CGFloat = 160
    let sidebarMaxWidth: CGFloat = 320
    let detailMinWidth: CGFloat = 340
    let detailMaxWidth: CGFloat = 480
    let contentMinWidth: CGFloat = 400

    // MARK: - V5.52-6: configureToolbar 搬过来——12 个 ToolbarController 闭包

    /// V4.8.0: NSToolbar 配置（WindowAccessor 触发）
    /// V6.28: Grid 业务闭包走 model.grid.X() (Core 业务仍 model.X())
    func configureToolbar(window: NSWindow) {
        // 只在第一次设置
        guard window.toolbar == nil else { return }

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        toolbar.delegate = ToolbarController.shared
        toolbar.displayMode = .iconOnly
        // V4.8.3: centeredItemIdentifiers = [.search] 让搜索框居中
        toolbar.centeredItemIdentifiers = [ToolbarController.Identifier.search.nsIdentifier]
        toolbar.allowsUserCustomization = true   // 用户可自定义 toolbar items
        toolbar.autosavesConfiguration = true   // 自定义状态自动保存
        toolbar.showsBaselineSeparator = false  // 不显示底部分隔线
        if #available(macOS 14.0, *) {
            toolbar.allowsDisplayModeCustomization = true
        }

        // 绑 action closures
        let controller = ToolbarController.shared
        controller.onToggleSidebar = { [model = self] in
            withAnimation(Animations.medium) { model.settings.showSidebar.toggle() }
        }
        // V5.7: 砍 onToggleFavorite——工具栏 ❤ 收藏按钮已移除
        controller.onBatchExport = { [model = self] in
            model.grid.batchExport()
        }
        controller.onDelete = { [model = self] in
            model.grid.handleDelete()
        }
        controller.onImport = { [model = self] in
            model.startImport()
        }
        // V4.37.1: ⌘Y Quick Look——复用 showQuickLook()（与空格键同路径）
        controller.onQuickLook = { [model = self] in
            model.grid.showQuickLook()
        }
        // V4.37.2: ⌘[ / ⌘] 上下张切换（macOS Quick Look 标准）
        controller.onPrev = { [model = self] in
            model.grid.goPrev()
        }
        controller.onNext = { [model = self] in
            model.grid.goNext()
        }
        // V5.24: 布局模式 + 密度 toolbar 集成桥接
        // V6.12.14: ThumbnailLayoutMode 加 .list 后——选 .list 切 viewMode = .list
        controller.onLayoutModeChange = { [model = self] mode in
            model.layoutMode = mode
            switch mode {
            case .list:
                model.viewMode = .list
            case .squareFit:
                model.viewMode = .grid
            }
        }
        controller.onDensityChange = { [model = self] density in
            model.grid.thumbnailSize = density
            // 同步 storedThumbnailSize 以便重启后恢复（V4.15.0 ⌘0 行为一致）
            model.settings.thumbnailSize = Double(density)
        }
        // V5.39.3: 排序 toolbar 桥接
        controller.onSortOptionChange = { [model = self] newSort in
            model.grid.sortOption = newSort
        }
        // V4.90.0: filterContentProvider 改 filterCoordinatorFactory
        //   folders/allTags 是 Q-bucket (view-owned), 由 GridViewModel 缓存
        controller.filterCoordinatorFactory = { [model = self] onStateChange in
            return FilterPopoverCoordinator(
                folders: model.grid.folders,
                tags: model.grid.allTags,
                onStateChange: { newState in
                    model.filterState = newState
                    onStateChange(newState)
                }
            )
        }
        // V4.36.x: 首次同步角标
        controller.filterActiveCount = filterState.activeCount
        // V4.8.1: search field 改用 NSSearchField
        controller.onSearchTextChanged = { [model = self] newText in
            if model.grid.searchText != newText {
                model.grid.searchText = newText
            }
        }

        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden

        // V4.37.4: titlebar 右上角小按钮（Photos.app ⓘ 风格）
        let accessory = TitlebarAccessoryController(
            inactiveSymbol: "info.circle",
            activeSymbol: "info.circle.fill",
            accessibilityLabel: Copy.titlebarInfoLabel,
            tooltip: titlebarAccessoryTooltip(isActive: settings.showDetail),
            onAction: { [model = self] in
                withAnimation(Animations.medium) { model.settings.showDetail.toggle() }
            }
        )
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
        titlebarAccessory = accessory
        accessory.setActive(settings.showDetail)

        // 初始 enabled 状态同步
        controller.updateAllStates(
            hasSelection: grid.selection.hasSelection,
            hasMultipleSelection: grid.selection.isMultiSelect
        )
    }

    /// V4.37.4: titlebar ⓘ 按钮 tooltip
    func titlebarAccessoryTooltip(isActive: Bool) -> String {
        isActive ? Copy.titlebarInfoTooltipHide : Copy.titlebarInfoTooltipShow
    }

    // MARK: - V5.53: Core + Import funcs

    /// V4.11.0: 检查 Application Support/ImageGallery/Photos/ 目录可写性
    func checkStorage() {
        if PhotoStorage.shared.verifyStorage() {
            storageErrorMessage = nil
        } else {
            storageErrorMessage = Copy.storageError
        }
    }

    /// ⌘N 触发的创建文件夹
    func createFolderFromAlert() {
        let trimmed = grid.newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let modelContext else { return }
        let folder = Folder(name: trimmed)
        modelContext.insert(folder)
        modelContext.saveWithLog()
        // V6.08: 存 UUID 而非 @Model 引用
        sidebarSelection = .folder(folder.id)
    }

    /// P4.1.1: 创建智能文件夹 — V1 简化: 不走 undo (跟 Folder create 一致)
    ///   auto-select 跟 Photos.app Smart Album 范式一致
    func createSmartFolder(name: String, iconName: String, filterState: FilterState) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let modelContext else { return }
        let nextOrder = (grid.smartFoldersCache.map(\.order).max() ?? -1) + 1
        let sf = SmartFolder(
            name: trimmed,
            iconName: iconName,
            filterState: filterState,
            order: nextOrder
        )
        modelContext.insert(sf)
        modelContext.saveWithLog()
        // P4.1.1: auto-select 刚创建的 smart folder
        sidebarSelection = .smartFolder(sf.id)
    }

    /// 切换当前排序方向
    func toggleSortDirection() {
        grid.sortOption = grid.sortOption.toggledDirection
    }

    /// V5.13: Toast 队列
    func enqueueToast(_ message: String, type: ToastView.ToastType = .info, duration: ToastInfo.Duration = .normal) {
        let info = ToastInfo(message: message, type: type, duration: duration)
        toastQueue.append(info)
        if toastQueue.count == 1 {
            scheduleDismiss(after: info.duration.seconds)
        }
    }

    /// V5.13: dismiss task 单点维护
    func scheduleDismiss(after seconds: TimeInterval) {
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, !toastQueue.isEmpty else { return }
            toastQueue.removeFirst()
            if let next = toastQueue.first {
                scheduleDismiss(after: next.duration.seconds)
            }
        }
    }

    /// V6.21.1 (Phase 1.2 UX polish): 用户主动 dismiss toast (close button)
    func scheduleDismissToast() {
        toastTask?.cancel()
        toastTask = nil
        guard !toastQueue.isEmpty else { return }
        toastQueue.removeFirst()
        if let next = toastQueue.first {
            scheduleDismiss(after: next.duration.seconds)
        }
    }

    /// 兼容旧 showToast 调用
    func showToast(_ message: String, type: ToastView.ToastType = .info) {
        enqueueToast(message, type: type, duration: .normal)
    }

    /// ─── 启动时清理过期回收站项（V3.6 NEW）───
    func purgeExpiredTrashOnStartup() {
        let days = TrashRetentionDays(rawValue: settings.trashRetentionDays) ?? .defaultValue
        guard let modelContext else { return }
        let service = RecycleBinService(storage: .shared, modelContext: modelContext)
        service.purgeExpired(retentionDays: days.rawValue)
    }

    // MARK: - 导入业务 (V6.28 仍 ContentViewModel——phase 2 拆 ImportViewModel)

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
            guard let modelContext else { return }
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
    /// V6.28: currentFolder 走 grid.currentFolder (Core 不再持该字段)
    func importPhotos(urls: [URL]) {
        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        guard let modelContext else { return }
        let importer = ImageImporter(modelContext: modelContext, folder: grid.currentFolder) { [weak self] current, total, inserted, failureCount in
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
            enqueueToast("已导入 \(result.inserted) 张，\(result.failureCount) 张失败", type: .info)
        } else if result.inserted > 0 {
            enqueueToast("已导入 \(result.inserted) 张图片", type: .success)
        }
        for (url, _) in result.failures where result.inserted == 0 {
            enqueueToast("导入失败：\(url.lastPathComponent)", type: .error, duration: .long)
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

    // MARK: - SidebarSelection 序列化 (V3.6 启动恢复)

    /// 序列化 SidebarSelection
    func serializeSelection(_ selection: SidebarSelection?) -> String {
        guard let selection = selection else { return "all" }
        switch selection {
        case .all: return "all"
        case .unfiled: return "unfiled"
        case .duplicates: return "duplicates"
        case .recent7Days: return "recent7Days"
        case .largeFiles: return "largeFiles"
        // V6.08: UUID 字符串 (之前 .folder(Folder) 序列化为 f.id.uuidString)
        case .folder(let id): return "folder:\(id.uuidString)"
        case .tag(let id): return "tag:\(id.uuidString)"
        case .recentlyDeleted: return "recentlyDeleted"
        // P4.1: 智能文件夹 UUID 字符串 (跟 folder/tag 一样模式, "smartFolder:" 前缀)
        case .smartFolder(let id): return "smartFolder:\(id.uuidString)"
        }
    }

    /// 恢复 SidebarSelection
    func restoreSelection(_ key: String) -> SidebarSelection? {
        guard let modelContext else { return nil }
        switch key {
        case "all": return .all
        case "unfiled": return .unfiled
        case "duplicates": return .duplicates
        case "recent7Days": return .recent7Days
        case "largeFiles": return .largeFiles
        case "recentlyDeleted": return .recentlyDeleted
        default:
            if key.hasPrefix("folder:") {
                let uuidStr = String(key.dropFirst(7))
                if let uuid = UUID(uuidString: uuidStr) {
                    // V6.08: 存 UUID 而非 @Model 引用——folder 不存在时 sidebarSelection 失效
                    return .folder(uuid)
                }
            }
            if key.hasPrefix("tag:") {
                let uuidStr = String(key.dropFirst(4))
                if let uuid = UUID(uuidString: uuidStr) {
                    return .tag(uuid)
                }
            }
            // P4.1: 智能文件夹恢复 (跟 folder/tag 同样 UUID 模式)
            if key.hasPrefix("smartFolder:") {
                let uuidStr = String(key.dropFirst(12))
                if let uuid = UUID(uuidString: uuidStr) {
                    return .smartFolder(uuid)
                }
            }
            return .all
        }
    }

    // MARK: - Init

    /// V5.52-1 起步: 无参 init——modelContext 由 .task 注入
    /// V5.59-1: 接受 settings 参数 (默认 nil, body 内 fallback 新实例——避免 default expr 不能调 @MainActor init)
    ///   ImageGalleryApp 传 sharedSettings 引用进来, 实现 ContentView/menu/SettingsView 共享
    /// V6.28: 创建 GridViewModel (共享 settings/undoManager) + 设 weak core back-ref
    init(settings: UserSettings? = nil) {
        let s = settings ?? UserSettings()
        let um = ImageGalleryUndoManager()
        self.settings = s
        self.undoManager = um
        // GridViewModel 共享 settings + undoManager (同实例)——用本地 um 而非 self.undoManager
        // 避免 init order trap (self.grid 赋值时 self 未完整初始化)
        self.grid = GridViewModel(settings: s, undoManager: um)
        // weak back-ref (避免 retain cycle — ContentViewModel 持 grid strong, grid 持 core weak)
        self.grid.core = self
        // wire toast callback (GridViewModel 的 toast 走 Core 的 enqueueToast)
        self.grid.enqueueToastHandler = { [weak self] message, type, duration in
            self?.enqueueToast(message, type: type, duration: duration)
        }
    }
}
