//
//  GridViewModel.swift
//  ImageGallery
//
//  V6.28 NEW: 从 ContentViewModel 拆出的 Grid 业务模型
//    Grid 业务 — 选择 / 可见照片 / 单张操作 / 批量操作 / 缩放 / 排序 / 搜索 / 沉浸式
//    持 Core back-ref (weak) + 共享 settings/undoManager + toast callback
//
//  拆分依据 (memory P1 #30):
//    ContentViewModel 1456 行 → 拆 Core (~500) + Import (~250) + Grid (~900)
//    GridViewModel 单独 .onChange 追踪 photo/folder/tag/smartFolder → 不污染 Core observation graph
//    batch ops (delete/move/rename/rating/export) 集中一处 → 测试覆盖更聚焦
//
//  关键约束:
//    - @MainActor + @Observable + final class (同 ContentViewModel)
//    - weak var core (避免 retain cycle — ContentViewModel 持 grid strong)
//    - settings/undoManager 由 init 注入 (同实例,Core + Grid 共享)
//    - enqueueToastHandler closure 注入 — Core 的 toast 系统不重复实现
//    - toolbar 闭包走 model.grid.X() (跟 ContentViewModel 同 pattern)
//
//  不在 GridViewModel (留在 ContentViewModel):
//    - sidebarSelection / filterState (Core — 决定"显示什么 scope")
//    - viewMode / layoutMode / appearanceMode / accentColor (Core — settings 镜像)
//    - configureToolbar / checkStorage / createFolder / serializeSelection (Core — window + lifecycle)
//    - 导入业务 startImport / handleDrop / importPhotos (Import — 单独 phase 2 拆 ImportViewModel)
//
//  阶段:
//    - V6.28-1: skeleton + Grid 业务抽取 ✓
//    - V6.28-2: caller files file-by-file 迁移 model.X → model.grid.X
//    - V6.28-3: tests 迁移 + 验证 0 regression
//

import Foundation
import SwiftUI
import SwiftData
import AVFoundation  // speakSelection() AVSpeechSynthesizer
import os  // batch rename catch 加 Logger.imageIO (V6.22.5)
import ImageIO  // rotateSelected EXIF read/write (V6.22.1)
import UniformTypeIdentifiers  // copyToPasteboard NSPasteboard UTI

/// V6.28: Grid 业务模型 — 选择 / 可见照片 / 批量操作 / 单张操作
/// 持 weak ref 回 ContentViewModel (Core) 用于跨域字段 (sidebarSelection/filterState)
@MainActor
@Observable
final class GridViewModel {
    /// V6.28: Core back-ref (weak 避免 retain cycle — ContentViewModel 持 grid strong)
    ///   用法: core?.sidebarSelection = .all (resetFilters)
    @ObservationIgnored weak var core: ContentViewModel?

    /// V6.28: shared settings (Core 同实例, init 注入)
    ///   sortOption / thumbnailSize / accentColor 等 settings-bound computed 都从这里读
    @ObservationIgnored let settings: UserSettings

    /// V6.28: shared undoManager (Core 同实例, init 注入)
    ///   batchMove / batchRename 等可撤销操作走 core.undoManager
    @ObservationIgnored let undoManager: ImageGalleryUndoManager

    /// V6.28: toast callback — Core 的 enqueueToast (避免重复 toast queue 实现)
    /// V6.29.1: 加 undoAction 参数 (破坏性操作 Photos.app 撤销范式)
    ///   Swift 限制: 函数/闭包类型不能有 argument labels, 用 `_ undoAction:` 标记 (跟函数参数一样)
    @ObservationIgnored var enqueueToastHandler: (String, ToastView.ToastType, ToastInfo.Duration, _ undoAction: (() -> Void)?) -> Void = { _, _, _, _ in }

    // MARK: - Grid 业务字段

    var selection = SelectionState()
    var searchText = ""
    /// V6.14.8: 拆 "stored default" (settings.thumbnailSize) + "live zoom" (liveThumbnailSize)
    ///   - settings.thumbnailSize = 用户偏好 (UserDefaults 持久化), SettingsView 改这里
    ///   - liveThumbnailSize = 当前显示 (内存, 不持久化), zoom in/out 改这里
    ///   - thumbnailSize getter: live 优先, fallback stored
    ///   - thumbnailSize setter: 只改 live, 不动 stored (zoom 临时态)
    ///   - resetThumbnailSize() (⌘0): 清 live → 回到 stored
    /// Photos.app 范式: 用户设的 default 不被临时 zoom 污染, ⌘0 一定回得到
    @ObservationIgnored private var liveThumbnailSize: CGFloat? = nil
    var thumbnailSize: CGFloat {
        get { liveThumbnailSize ?? CGFloat(settings.thumbnailSize) }
        set { liveThumbnailSize = newValue }
    }
    /// V5.59-2: sortOption 改为 computed 绑 settings.sortOption
    var sortOption: SortOption {
        get { SortOption(rawValue: settings.sortOption) ?? .filenameAsc }
        set { settings.sortOption = newValue.rawValue }
    }
    var showingBatchDeleteConfirm = false
    /// P4.2: 批量重命名 sheet — mini toolbar "重命名" 按钮 / File 菜单 ⌘⇧R 触发
    var showingBatchRenameSheet = false
    /// V6.19.0 (P0 #1): 分享 picker — File 菜单 ⌘⇧S / NSSharingServicePicker host
    ///   nil = picker hidden, 非空 = sheet 显示并弹 NSSharingServicePicker (AirDrop/Messages/Mail)
    var sharingURLs: [URL]?

    // V6.20.3 (code audit fix #15): share request throttle — 0.3s 内重复 ⌘⇧S 忽略
    @ObservationIgnored private var lastShareRequestTime: Date?
    func shouldThrottleShareRequest() -> Bool {
        let now = Date()
        if let last = lastShareRequestTime, now.timeIntervalSince(last) < 0.3 {
            return true  // throttle
        }
        lastShareRequestTime = now
        return false
    }
    /// P4.1.1: 智能文件夹创建 sheet — sidebar Library section header "+" 触发
    var showingNewSmartFolderSheet = false
    /// P4.1.1: sheet 打开时快照当前 filter — 避免 sheet 打开后用户改 toolbar filter 干扰预览
    var pendingSmartFolderFilter: FilterState? = nil
    var showingEmptyTrashConfirm = false
    var showingNewFolderAlert = false
    var newFolderName = ""
    var immersivePhoto: Photo? = nil
    var immersiveIndex: Int = 0
    var scrollAnchorPhotoID: String? = nil

    // MARK: - V5.52-7: @Query 缓存 (view 通过 .onChange 推过来)

    @ObservationIgnored var allPhotos: [Photo] = []
    @ObservationIgnored var folders: [Folder] = []
    @ObservationIgnored var allTags: [Tag] = []
    /// P4.1.1: smartFolders cache — 跟 allPhotos/folders/allTags 同 pattern
    ///   ContentView .onChange(of: smartFolders) 推送; createSmartFolder 用 max+1 算 order
    @ObservationIgnored var smartFoldersCache: [SmartFolder] = []

    // MARK: - Sidebar 派生 flag (读 core.sidebarSelection)

    /// V6.08: 当前侧栏选中的 folder——从 modelContext 按 UUID fetch
    var currentFolder: Folder? {
        guard case .folder(let id) = core?.sidebarSelection, let modelContext = core?.modelContext else { return nil }
        return (try? modelContext.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// V6.08: 当前侧栏选中的 tag——同 currentFolder 模式
    var currentTag: Tag? {
        guard case .tag(let id) = core?.sidebarSelection, let modelContext = core?.modelContext else { return nil }
        return (try? modelContext.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// P4.1.1: 当前侧栏选中的 smartFolder——跟 currentFolder/currentTag 同 UUID fetch 模式
    var currentSmartFolder: SmartFolder? {
        guard case .smartFolder(let id) = core?.sidebarSelection, let modelContext = core?.modelContext else { return nil }
        return (try? modelContext.fetch(FetchDescriptor<SmartFolder>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// P4.1.1: 当前 smartFolder 的 filter (decoded)
    ///   nil = no smart folder active; .empty (isActive=false) = 激活但无 constraint, 走 no-op
    var smartFolderFilter: FilterState? {
        currentSmartFolder?.decodedFilter
    }

    var filterUnfiled: Bool {
        if case .unfiled = core?.sidebarSelection { return true }
        return false
    }

    var filterDuplicates: Bool {
        if case .duplicates = core?.sidebarSelection { return true }
        return false
    }

    var filterRecent7Days: Bool {
        if case .recent7Days = core?.sidebarSelection { return true }
        return false
    }

    var filterLargeFiles: Bool {
        if case .largeFiles = core?.sidebarSelection { return true }
        return false
    }

    var filterInTrash: Bool {
        if case .recentlyDeleted = core?.sidebarSelection { return true }
        return false
    }

    var filterInDuplicates: Bool {
        if case .duplicates = core?.sidebarSelection { return true }
        return false
    }

    // MARK: - 选中派生

    /// V3.6.52: 3 个 O(n) lookup 合并——photo + index 一次扫描
    var resolvedSingle: (photo: Photo, visibleIndex: Int)? {
        guard let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return (visiblePhotos[idx], idx)
    }

    var singleSelectedPhoto: Photo? { resolvedSingle?.photo }
    var currentIndex: Int { (resolvedSingle?.visibleIndex ?? -1) + 1 }
    var canPrev: Bool { currentIndex > 1 }
    var canNext: Bool { currentIndex > 0 && currentIndex < visiblePhotos.count }
    var isMultiSelect: Bool { selection.isMultiSelect }
    var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    // MARK: - 可见照片 (核心: 筛选 + 排序后)

    /// V4.36.6: 共享 helper——3 视图 (grid/list/timeline) 共用
    ///   V4.36.x: 加 4 参 (工具栏筛选 4 维)
    ///   V5.8: 砍 filterFavorites
    var visiblePhotos: [Photo] {
        PhotoStats.filtered(
            allPhotos,
            folder: currentFolder,
            tag: currentTag,
            searchText: searchText,
            sortOption: sortOption,
            filterUnfiled: filterUnfiled,
            filterDuplicates: filterDuplicates,
            filterRecent7Days: filterRecent7Days,
            filterLargeFiles: filterLargeFiles,
            filterInTrash: filterInTrash,
            selectedFolderIDs: core?.filterState.folders ?? [],
            selectedTagIDs: core?.filterState.tags ?? [],
            selectedShapes: core?.filterState.shapes ?? [],
            minRating: core?.filterState.minRating ?? 0,
            // P4.1.1: smart folder filter 跟 toolbar filter 独立 AND 应用
            smartFolderFilter: smartFolderFilter
        )
    }

    // MARK: - 状态栏 / 详情面板数据

    /// V3.5.6 Finder 化: 总占用空间格式化
    var totalSizeFormatted: String {
        let bytes = PhotoStats.totalSize(allPhotos)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// V3.5.19: 当前选中图片总大小
    var selectedTotalSize: Int64 {
        selection.selectedPhotos(in: visiblePhotos)
            .reduce(0) { $0 + $1.fileSize }
    }

    /// V3.6: 回收站视图 count + size
    var trashedCount: Int { PhotoStats.trashed(allPhotos).count }
    var trashedTotalSize: Int64 { PhotoStats.trashedSize(allPhotos) }

    // V6.20.0 (code audit fix #6): libraryStats 缓存 — PhotoStatsSnapshot.compute 每次 body 重渲都重算
    //   @Query allPhotos 任何 SwiftData write (import/delete/tag/rating/drag-drop) 都触发 SidebarView body 重渲染
    //   之前 7-8 遍 O(n) (V6.19.2 P0 #11 优化前) 改 2 遍 (snapshot) 仍 per-render 重算 — 大库 + 频繁写入场景下卡顿
    //   修: 缓存 snapshot + allPhotos.count 比较 (O(1) invalidation key)
    @ObservationIgnored private var cachedLibraryStats: PhotoStatsSnapshot?
    @ObservationIgnored private var libraryStatsCacheCount: Int = -1
    var libraryStats: PhotoStatsSnapshot {
        if let cached = cachedLibraryStats, libraryStatsCacheCount == allPhotos.count {
            return cached
        }
        let snapshot = PhotoStatsSnapshot.compute(allPhotos)
        cachedLibraryStats = snapshot
        libraryStatsCacheCount = allPhotos.count
        return snapshot
    }

    /// V3.6.15: 重复图 group / purgeable count / size
    /// V6.12: 用 allPhotos 替 visiblePhotos——sidebar 数字 (DuplicateCount 用 allPhotos)
    ///   跟 detail panel 数字 保持一致 (trashedCount 用 allPhotos 同 precedent)
    ///   之前 visiblePhotos 在 folder/search 激活时算, 跟 sidebar 对不上
    var duplicateGroupCount: Int { PhotoStats.duplicateGroups(in: allPhotos).count }
    var duplicatePurgeableCount: Int { PhotoStats.duplicatesToPurge(in: allPhotos).count }
    var duplicatePurgeableSize: Int64 {
        PhotoStats.duplicatesToPurge(in: allPhotos).reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - V5.56 Key Photo——每日期组代表图

    /// V5.56: DateGroup 代表图 (每组 1 张)——sidebar 折叠 / DateSectionHeader 用
    /// 优先级 (从高到低):
    ///   1. group.photos.first 排除 trashed (避免代表图指向已删)
    ///   2. fallback 到 group.photos.first (即使全 trashed 也返回某张)
    ///   3. group.photos 为空 → nil
    /// 时间复杂度 O(n) (group 内 photos 数量, 实际 n ≤ 几十)
    /// group.photos 已按 importedAt 降序 (PhotoStats.groupByDate 实现)
    /// V6.11: 全 trashed 时返 nil——之前 fallback group.photos.first 返 trashed photo
    ///   DateSectionHeader 会显示灰缩略图, UX 差。返 nil 让 DateSectionHeader 走 text-only 分支
    func representativePhoto(for group: DateGroup) -> Photo? {
        return group.photos.first(where: { !$0.isInTrash })
    }

    // MARK: - navigation title / subtitle

    /// V4.2.0 P0❸: navigationTitle——给 Dock / ⌘⇥ / Mission Control / VoiceOver 用
    /// V6.08: .folder/.tag 改 UUID 存储, 名字从 modelContext fetch
    var currentViewTitle: String {
        switch core?.sidebarSelection {
        case .all, .none:           return "全部照片"
        case .unfiled:              return "待整理"
        case .duplicates:           return "重复图"
        case .recent7Days:          return "最近 7 天"
        case .largeFiles:           return "大图（>5MB）"
        case .recentlyDeleted:      return Term.recycleBin
        case .folder:               return currentFolder?.name ?? "全部照片"
        case .tag:                  return currentTag.map { "#\($0.name)" } ?? "全部照片"
        // P4.1.1: 智能文件夹标题 — 名字来自 decoded entity, 删除时 fallback "智能文件夹"
        case .smartFolder:          return currentSmartFolder?.name ?? Copy.smartFolderFallback
        }
    }

    /// V4.2.0 P0❸: subtitle——"N 张 · X MB"
    ///   V4.36.x: 工具栏筛选激活时追加 "· 已筛选 (N)"
    var currentViewSubtitle: String {
        let count = visiblePhotos.count
        let bytes = visiblePhotos.reduce(Int64(0)) { $0 + $1.fileSize }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        var s = "\(count) 张 · \(size)"
        if let activeCount = core?.filterState.activeCount, core?.filterState.isActive == true {
            s += " · 已筛选 (\(activeCount))"
        }
        return s
    }

    /// V4.4.8: toolbar 搜索框左 padding——跟 grid 左缘对齐
    var searchFieldLeadingOffset: CGFloat {
        guard settings.showSidebar else { return 12 }
        let togglePlusSpacing: CGFloat = 64
        return max(12, core?.sidebarColumnWidth ?? 220 - togglePlusSpacing)
    }

    // MARK: - 派生 string

    /// V4.0.0: dialog 标题——批量删除 (复用 showingDuplicateCheck binding 模式)
    var batchDeleteTitle: String {
        let n = selection.selectedIDs.count
        return n == 0 ? Copy.deleteConfirmTitle : "\(n) 张图片"
    }

    /// V4.0.0: 重复检测 dialog title
    /// V6.28.1: importDuplicateCheck 迁 ImportViewModel — 走 core?.importVM.importDuplicateCheck
    var duplicateDialogTitle: String {
        guard let check = core?.importVM.importDuplicateCheck else { return "" }
        return "发现 \(check.existing.count) 张已存在 / \(check.newCount) 张新文件"
    }

    // MARK: - Init

    /// V6.28: GridViewModel init — Core (ContentViewModel) 反向注入 weak ref
    ///   settings/undoManager 共享实例 (Core 同对象)
    init(settings: UserSettings, undoManager: ImageGalleryUndoManager) {
        self.settings = settings
        self.undoManager = undoManager
    }

    // MARK: - 单张操作

    /// 复制到剪贴板（支持多选）
    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let urls: [URL]
        if !selection.selectedIDs.isEmpty {
            urls = selection.selectedPhotos(in: visiblePhotos).map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            urls = [photo.fileURL]
        } else {
            return
        }
        // V6.20.3 (code audit fix #8): 用 NSPasteboardItem + 多 type representation
        //   之前 `writeObjects(urls as [NSURL])` 只声明 fileURL promise — Photoshop/Pixelmator
        //   等专业 app 找不到 image bytes (kUTTypeImage), copy → paste 失败
        //   现在每个 URL 一个 NSPasteboardItem, 声明 .fileURL (Finder 接) + auto-detect image type (专业 app 接)
        //   writeObjects([NSPasteboardItem]) 自动 handle 多 item
        let items: [NSPasteboardItem] = urls.map { url in
            let item = NSPasteboardItem()
            // fileURL promise — Finder / Messages 接
            item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType.fileURL)
            // 自动检测 image type — Photoshop / Pixelmator / Preview 接
            if let uti = UTType(filenameExtension: url.pathExtension.lowercased()),
               uti.conforms(to: .image) {
                item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType(uti.identifier))
            }
            return item
        }
        pasteboard.writeObjects(items)
        enqueueToastHandler(urls.count == 1 ? "已复制 1 张图片" : "已复制 \(urls.count) 张图片", .success, .normal, nil)
    }

    /// V6.19.0 (P0 #1): 多图分享 — NSSharingServicePicker (Photos.app 范式)
    ///   返回 URL 数组给 caller 显示 picker (SwiftUI .popover, 跟 ShareLink 单图互补)
    ///   selection 空 / 单图时退化为 ShareLink 单图 cell 菜单 (CellContextMenuModifier)
    ///   无 selection 时给提示 toast, 不报错
    func shareSelectedURLs() -> [URL] {
        let urls: [URL]
        if !selection.selectedIDs.isEmpty {
            urls = selection.selectedPhotos(in: visiblePhotos).map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            urls = [photo.fileURL]
        } else {
            enqueueToastHandler("请先选择要分享的图片", .info, .normal, nil)
            return []
        }
        return urls
    }

    /// V6.22.1 (P2 #2): 旋转选中照片 (顺时针 / 逆时针 90°)
    ///   - 写 EXIF orientation 到原文件 (lossy 重编码, JPEG/HEIC 通常不可察觉)
    ///   - 失效 ThumbnailCache (旧 thumbnail 是旧方向)
    ///   - Toast 提示成功数
    ///   - selection 空时 toast 提示用户先选图 (跟 shareSelected 一致 UX)
    ///   - Photos.app 范式: 旋转是 in-place file 修改, 无 undo (用户可 export 原图 + 重新 import 复原)
    func rotateSelected(clockwise: Bool) {
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty else {
            enqueueToastHandler("请先选择要旋转的图片", .info, .normal, nil)
            return
        }
        // V6.35.3: capture 旋转前 orientation (每张图) — undo 还原用
        struct Snapshot { let photo: Photo; let original: PhotoOrientation? }
        let snapshots: [Snapshot] = photos.map { photo in
            Snapshot(photo: photo, original: readOrientation(url: photo.fileURL))
        }
        var successCount = 0
        for photo in photos {
            // 读取当前 EXIF orientation (V6.22.1: 用 CGImageSource 读 metadata)
            let current = readOrientation(url: photo.fileURL) ?? .up
            let new = clockwise ? current.rotated90Clockwise() : current.rotated90CounterClockwise()
            // 写新 orientation 到文件 + 失效 cache
            if PhotoRotationService.applyOrientation(new, to: photo.fileURL) {
                PhotoRotationService.invalidateThumbnail(for: photo.fileURL)
                successCount += 1
            }
        }
        let message = successCount == 1 ? "已旋转 1 张图片" : "已旋转 \(successCount) 张图片"
        enqueueToastHandler(message, successCount == photos.count ? .success : .warning, .normal, nil)

        // V6.35.3: register undo (coalesceId="rotate" — 1s 内连续旋转合并)
        //   Photos.app 行为: 连转 5 张 = 1 个 undo, ⌘Z 一次撤销整批
        let capturedSnapshots = snapshots
        let capturedCount = successCount
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            for snap in capturedSnapshots where snap.original != nil {
                if let original = snap.original,
                   PhotoRotationService.applyOrientation(original, to: snap.photo.fileURL) {
                    PhotoRotationService.invalidateThumbnail(for: snap.photo.fileURL)
                }
            }
            self.enqueueToastHandler("已撤销旋转 \(capturedCount) 张", .info, .normal, nil)
        }
        undoManager.registerUndoOnly(description: "旋转 \(capturedCount) 张照片", undo: undo, coalesceId: "rotate")
    }

    /// V6.22.1: 读 EXIF orientation — 用 CGImageSourceCopyPropertiesAtIndex
    ///   返回 nil 表示无 orientation tag (default .up)
    private func readOrientation(url: URL) -> PhotoOrientation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let raw = props[kCGImagePropertyOrientation] as? UInt32 else { return nil }
        return PhotoOrientation(rawValue: raw)
    }

    /// V6.19.5 (P0 #16): 朗读选中照片 (Speech menu, macOS Edit > Speech 范式)
    ///   - selection 空 → toast 提示
    ///   - 1 张 → 读 "已选 1 张照片, 文件名 XXX"
    ///   - N 张 → 读 "已选 N 张照片, 第一张 XXX"
    ///   zh-CN 语音; AVSpeechSynthesizer 一次性 utterance (不持久 synthesizer)
    func speakSelection() {
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty else {
            enqueueToastHandler("请先选择要朗读的图片", .info, .normal, nil)
            return
        }
        let message: String
        if photos.count == 1 {
            message = "已选 1 张照片，文件名 \(photos[0].filename)"
        } else {
            message = "已选 \(photos.count) 张照片，第一张 \(photos[0].filename)"
        }
        let utterance = AVSpeechUtterance(string: message)
        // V6.20.3 (code audit fix #13): voice fallback chain — zh-CN → 当前 locale → en-US → system default
        let voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
            ?? AVSpeechSynthesisVoice()
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        // V6.20.2 (code audit fix #4): 用 stable synthesizer 实例 + stop 上一个 utterance
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }

    /// V6.20.2 (code audit fix #4): stable AVSpeechSynthesizer instance — 跨多次 speak() 复用
    @ObservationIgnored private let speechSynthesizer = AVSpeechSynthesizer()

    /// 进入沉浸式查看
    func enterImmersive(_ photo: Photo) {
        if let idx = visiblePhotos.firstIndex(where: { $0.id == photo.id }) {
            immersiveIndex = idx
            immersivePhoto = photo
        }
    }

    /// V4.49.1: ⌘↩ Return 触发进入沉浸式
    func enterImmersiveFromSelection() {
        guard let photo = singleSelectedPhoto else { return }
        enterImmersive(photo)
    }

    /// 清除所有筛选
    func resetFilters() {
        searchText = ""
        core?.sidebarSelection = .all
        core?.filterState = .empty
    }

    /// Delete 键处理
    func handleDelete() {
        if !selection.selectedIDs.isEmpty {
            showingBatchDeleteConfirm = true
        } else if singleSelectedPhoto != nil {
            deleteSinglePhoto()
        }
    }

    /// V4.36.6: 3 视图共用 tap 处理
    func handleTap(_ photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        let modifier: ClickModifier = {
            if modifiers.contains(.command) { return .command }
            if modifiers.contains(.shift) { return .shift }
            return .plain
        }()
        let photoIDs = visiblePhotos.map { $0.id }
        let outcome = MultiSelectMath.handleTap(
            state: selection,
            photoID: photo.id,
            modifier: modifier,
            photoIDs: photoIDs
        )
        switch outcome {
        case .singleSelect(let s), .toggleMultiSelect(let s), .rangeSelect(let s):
            selection = s
        }
    }

    /// 上一张
    func goPrev() {
        guard canPrev,
              let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        let newID = visiblePhotos[idx - 1].id
        selection = selection.selectingSingle(newID)
    }

    /// 下一张
    func goNext() {
        guard canNext,
              let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx < visiblePhotos.count - 1 else { return }
        let newID = visiblePhotos[idx + 1].id
        selection = selection.selectingSingle(newID)
    }

    /// ⌘+ 放大
    func zoomIn() {
        if let next = ThumbnailDensity.larger(than: thumbnailSize) {
            thumbnailSize = next.size
        }
    }

    /// ⌘- 缩小
    func zoomOut() {
        if let prev = ThumbnailDensity.smaller(than: thumbnailSize) {
            thumbnailSize = prev.size
        }
    }

    /// V6.14.8: ⌘0 reset zoom — 清 liveThumbnailSize, 回到 stored default
    ///   之前是 `thumbnailSize = settings.thumbnailSize` no-op (V6.14.7 修 stale test 时发现)
    func resetThumbnailSize() {
        liveThumbnailSize = nil
    }

    /// V4.37.1: Quick Look——V5.42 改走 enterImmersiveFromSelection
    func showQuickLook() {
        enterImmersiveFromSelection()
    }

    // MARK: - 批量 + Trash 操作

    /// V4.1.0 l: 切换侧栏 section 时清选中
    func clearSelectionOnFilterChange() {
        if !selection.isEmpty {
            selection = .empty
        }
    }

    /// V3.6: 删除单张 = 移到回收站
    /// V6.29.1: undo = restore from trash (Photos.app 撤销范式)
    func deleteSinglePhoto() {
        guard let photo = singleSelectedPhoto else { return }
        let count = performOnSelectedTrash({ svc, photos in svc.recycle(photos[0]) })
        guard count > 0 else { return }
        let capturedPhoto = photo
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            guard let modelContext = self.core?.modelContext else { return }
            RecycleBinService(storage: .shared, modelContext: modelContext).restore(capturedPhoto)
        }
        // 同步: undoManager push + toast undoAction (⌘Z + 点 [撤销] 都能恢复)
        undoManager.registerUndoOnly(description: "删除 1 张照片", undo: undo)
        enqueueToastHandler(
            "已移到回收站（\(settings.trashRetentionDays) 天后永久删除）",
            .info,
            .normal,
            undo
        )
    }

    /// V3.6: 批量删除
    /// V6.29.1: undo = 全部 restore from trash (Photos.app 撤销范式)
    func batchDelete() {
        // 提前 capture photos (performOnSelectedTrash 会清 selection)
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty else { return }
        let count = performOnSelectedTrash({ svc, photos in photos.forEach { svc.recycle($0) } })
        guard count > 0 else { return }
        let capturedPhotos = photos
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            guard let modelContext = self.core?.modelContext else { return }
            let service = RecycleBinService(storage: .shared, modelContext: modelContext)
            for photo in capturedPhotos {
                service.restore(photo)
            }
            self.enqueueToastHandler("已恢复 \(capturedPhotos.count) 张图片", .success, .normal, nil)
        }
        // 同步: undoManager push + toast undoAction
        undoManager.registerUndoOnly(description: "删除 \(count) 张照片", undo: undo)
        enqueueToastHandler(
            "已移到回收站 \(count) 张",
            .info,
            .normal,
            undo
        )
    }

    /// 批量移动到文件夹
    ///
    /// V6.14.10: 恢复 `undoManager.registerAction` — UndoManager 重做 (自写 stack, 避开
    ///   Foundation.UndoManager 的 run loop 交互死锁)。V6.14.4 砍, V6.14.10 拿回来。
    ///   闭包用 `[weak self]` 避免 ContentViewModel 强引用环 (cycle 仍存在
    ///   undoStack 持 entry, entry 持闭包, 但 self 是 weak → self 释放时闭包失效,
    ///   undo 调用时不做事不崩)。
    func batchMove(to folder: Folder?) {
        let photosToMove = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToMove.isEmpty, let modelContext = core?.modelContext else { return }
        let oldFolders = photosToMove.map { $0.folder }
        let count = photosToMove.count
        let folderName = folder?.name ?? "未整理"

        // V6.36.3: coalesceId="move" — 1s 内连续 batchMove 合并 (Photos.app 行为)
        undoManager.registerAction(
            description: "移动 \(count) 张照片到 \(folderName)",
            action: { [weak self] in
                for photo in photosToMove {
                    photo.folder = folder
                }
                modelContext.saveWithLog()
                self?.selection = .empty
            },
            undo: { [weak self] in
                for (photo, oldFolder) in zip(photosToMove, oldFolders) {
                    photo.folder = oldFolder
                }
                modelContext.saveWithLog()
                _ = self  // 强引用 self 进闭包, 防止 self 释放时 undo 操作失败
            },
            coalesceId: "move"
        )
    }

    /// 批量加标签
    func batchAddTag(_ tag: Tag) {
        let photosToTag = selection.selectedPhotos(in: visiblePhotos)
        guard let modelContext = core?.modelContext else { return }
        for photo in photosToTag {
            if !photo.tags.contains(where: { $0.id == tag.id }) {
                photo.tags.append(tag)
            }
        }
        modelContext.saveWithLog()
    }

    // MARK: - P4.2: 批量重命名
    /// 模板: {n} {n:N} {originalName} (见 BatchRenameTemplate)
    /// - 规划阶段: render + uniquify (within-batch + on-disk 双层)
    /// - 执行阶段: 走 undoManager.registerAction, 单步撤销整批
    /// - 错误处理: per-photo try, 失败计数, 单次 toast 汇总 (V6.08 教训: 不静默)
    func batchRename(template: String) {
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty, let modelContext = core?.modelContext else { return }
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Plan: 渲染 + 去重, 收集 (photo, oldURL, oldFilename, newBase, newExt)
        struct Plan {
            let photo: Photo
            let oldURL: URL
            let oldFilename: String
            let newBase: String
            let newExt: String
        }
        var plans: [Plan] = []
        var reserved = Set<String>()

        for (i, photo) in photos.enumerated() {
            let oldURL = photo.fileURL
            let oldFilename = photo.filename
            let ext = oldURL.pathExtension
            let originalBase = oldURL.deletingPathExtension().lastPathComponent

            // 1) render
            guard let rendered = try? BatchRenameTemplate.render(
                template: trimmed, index: i + 1, totalCount: photos.count,
                originalFilename: originalBase
            ) else { continue }

            // 2) skip self-rename (template produces same name as original)
            if rendered == originalBase && ext == oldURL.pathExtension {
                reserved.insert("\(rendered).\(ext)")
                continue
            }

            // 3) uniquify (within-batch + on-disk)
            let (finalBase, finalExt) = BatchRenameTemplate.uniquify(
                baseName: rendered, ext: ext, existingReserved: reserved,
                onDiskCheck: { name in
                    let candidateURL = oldURL.deletingLastPathComponent()
                        .appendingPathComponent(name)
                    return FileManager.default.fileExists(atPath: candidateURL.path)
                }
            )
            reserved.insert("\(finalBase).\(finalExt)")
            plans.append(Plan(
                photo: photo, oldURL: oldURL, oldFilename: oldFilename,
                newBase: finalBase, newExt: finalExt
            ))
        }

        guard !plans.isEmpty else { return }
        let count = plans.count

        // V6.36.3: coalesceId="rename" — 1s 内连续 batchRename 合并
        //   用 labeled closure 参数 (action/undo 显式 label) — coalesceId 必须在末位
        //   trailing closure 语法只能用在最后一个 closure 参数, 多个 closure 必须 labeled
        undoManager.registerAction(
            description: "批量重命名 \(count) 张照片",
            action: { [weak self] in
                var errors = 0
                for p in plans {
                    let newURL = p.oldURL.deletingLastPathComponent()
                        .appendingPathComponent("\(p.newBase).\(p.newExt)")
                    do {
                        try FileManager.default.moveItem(at: p.oldURL, to: newURL)
                        p.photo.filename = "\(p.newBase).\(p.newExt)"
                        p.photo.fileURL = newURL
                    } catch {
                        Logger.imageIO.error("batchRename 失败: \(p.oldURL.lastPathComponent, privacy: .public) → \(newURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                        errors += 1
                    }
                }
                modelContext.saveWithLog()
                if errors > 0 {
                    self?.enqueueToastHandler("部分重命名失败：\(errors) 张", .error, .long, nil)
                } else {
                    self?.enqueueToastHandler("已重命名 \(count) 张照片", .success, .long, nil)
                }
                _ = self
            },
            undo: { [weak self] in
                var undoErrors = 0
                for p in plans.reversed() {
                    let newURL = p.oldURL.deletingLastPathComponent()
                        .appendingPathComponent("\(p.newBase).\(p.newExt)")
                    do {
                        try FileManager.default.moveItem(at: newURL, to: p.oldURL)
                        p.photo.filename = p.oldFilename
                        p.photo.fileURL = p.oldURL
                    } catch {
                        Logger.imageIO.error("batchRename undo 失败: \(newURL.lastPathComponent, privacy: .public) → \(p.oldURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                        undoErrors += 1
                    }
                }
                modelContext.saveWithLog()
                if undoErrors > 0 {
                    self?.enqueueToastHandler("部分撤销失败：\(undoErrors) 张", .error, .long, nil)
                }
                _ = self
            },
            coalesceId: "rename"
        )
    }

    /// V5.12: 批量评分
    /// V6.35.3: 加 undo + coalesceId="rate" — 1s 内连续评分合并 (Photos.app 行为)
    func batchSetRating(_ rating: Int) {
        let photosToRate = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToRate.isEmpty, let modelContext = core?.modelContext else { return }
        // V6.35.3: capture 原 rating — undo 还原用
        let originalRatings = photosToRate.map { $0.rating }
        BatchSetRatingMath.applyRating(rating, count: photosToRate.count) { index, r in
            photosToRate[index].rating = r
        }
        modelContext.saveWithLog { [weak self] _ in
            self?.enqueueToastHandler("批量评分失败", .error, .long, nil)
        }
        // V6.35.3: register undo (coalesceId="rate" — 1s 窗合并连续评分)
        let capturedPhotos = photosToRate
        let capturedOriginals = originalRatings
        let capturedRating = rating
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            for (index, photo) in capturedPhotos.enumerated() where index < capturedOriginals.count {
                photo.rating = capturedOriginals[index]
            }
            if let modelContext = self.core?.modelContext {
                modelContext.saveWithLog { _ in }
            }
        }
        undoManager.registerUndoOnly(description: "评分 \(rating) 星", undo: undo, coalesceId: "rate")
    }

    /// 批量导出
    func batchExport() {
        let photosToExport = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToExport.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "选择导出位置"
        panel.prompt = "导出"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destDir = panel.url else { return }

        var successCount = 0
        for photo in photosToExport {
            let destURL = destDir.appendingPathComponent(photo.filename)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let uniqueDest = uniqueDestinationForBatchExport(for: destURL)
                    try FileManager.default.copyItem(at: photo.fileURL, to: uniqueDest)
                } else {
                    try FileManager.default.copyItem(at: photo.fileURL, to: destURL)
                }
                successCount += 1
            } catch {
                enqueueToastHandler("导出失败：\(photo.filename)", .error, .long, nil)
            }
        }
        if successCount > 0 {
            enqueueToastHandler("已导出 \(successCount) 张图片", .success, .normal, nil)
        }
    }

    /// 避免导出时文件名冲突
    func uniqueDestinationForBatchExport(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        while true {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let candidate = dir.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    /// 在 visiblePhotos ∩ selectedIDs 上执行 trash 操作
    /// V5.13: 注入 onError
    /// V6.29.1: 不显示 toast, 由 caller 自己决定 (e.g. batchDelete 走 undo toast, permanentDeleteSelected 走普通 toast)
    ///   返回操作的照片数 (caller 用来生成 toast message / undo description)
    @discardableResult
    func performOnSelectedTrash(
        _ operation: (RecycleBinService, [Photo]) -> Void
    ) -> Int {
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty, let modelContext = core?.modelContext else { return 0 }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [weak self] error in
                self?.enqueueToastHandler(
                    Copy.recycleBinOperationFailed(error.localizedDescription),
                    .error,
                    .long
                , nil)
            }
        )
        operation(service, photos)
        let count = photos.count
        selection = .empty
        return count
    }

    /// 恢复选中的照片 (从回收站)
    /// V6.29.1: 不走 undo toast (V1 简化: 恢复操作少, ⌘Z 不需要做撤销恢复的反向)
    ///   走普通 success toast
    func restoreSelectedFromTrash() {
        let count = performOnSelectedTrash({ svc, photos in photos.forEach { svc.restore($0) } })
        if count > 0 {
            enqueueToastHandler("已恢复 \(count) 张图片", .success, .normal, nil)
        }
    }

    /// 永久删除选中的照片
    /// V6.29.1: 不走 undo toast (永久删除无法恢复, 文件已从磁盘删除)
    ///   走普通 toast
    func permanentDeleteSelected() {
        let count = performOnSelectedTrash({ svc, photos in svc.purgeAll(photos) })
        if count > 0 {
            enqueueToastHandler("已永久删除 \(count) 张图片", .info, .normal, nil)
        }
    }

    /// 清空回收站
    func emptyTrash() {
        let trashed = allPhotos.filter { $0.isInTrash }
        guard !trashed.isEmpty, let modelContext = core?.modelContext else { return }
        RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [weak self] error in
                self?.enqueueToastHandler("清空回收站失败：\(error.localizedDescription)", .error, .long, nil)
            }
        ).purgeAll(trashed)
        let count = trashed.count
        selection = .empty
        enqueueToastHandler("已清空回收站（\(count) 张）", .info, .normal, nil)
    }

    /// V3.6.15: 重复图清理
    func keepNewestPerDuplicateGroup() {
        let visible = visiblePhotos.filter { !$0.isInTrash }
        let purgeable = PhotoStats.duplicatesToPurge(in: visible)
        guard !purgeable.isEmpty, let modelContext = core?.modelContext else { return }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [weak self] error in
                self?.enqueueToastHandler("批量移到回收站失败：\(error.localizedDescription)", .error, .long, nil)
            }
        )
        for photo in purgeable { service.recycle(photo) }
        enqueueToastHandler("已移到回收站 \(purgeable.count) 张重复图", .info, .normal, nil)
    }
}
