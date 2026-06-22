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
    @ObservationIgnored var liveThumbnailSize: CGFloat? = nil
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
    /// V6.20.2 (code audit fix #4): stable AVSpeechSynthesizer instance — 跨多次 speak() 复用
    @ObservationIgnored let speechSynthesizer = AVSpeechSynthesizer()

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
    /// V6.38.0 (P0 perf): 加 cache — SidebarSelection 是 Hashable, 缓存命中避免 SwiftData fetch
    ///   之前每次访问 = 1 次 SQLite round-trip; 现在仅 sidebarSelection 真变时 fetch
    ///   invalidation: cachedSidebarSelection 跟当前 core.sidebarSelection 不等 → 重 fetch
    @ObservationIgnored private var cachedCurrentFolder: Folder? = nil
    @ObservationIgnored private var cachedFolderSelection: SidebarSelection? = nil  // sentinel: nil = 未 resolve
    var currentFolder: Folder? {
        let sel = core?.sidebarSelection
        if sel == cachedFolderSelection, let cached = cachedCurrentFolder { return cached }
        guard case .folder(let id) = sel, let modelContext = core?.modelContext else {
            cachedCurrentFolder = nil
            cachedFolderSelection = sel
            return nil
        }
        // V6.68 (Q9 错误处理统一): 改用 modelContext.fetchFirst — 失败时 Logger.swiftData.error 留诊断线索
        //   之前 try? ... .first 完全静默, fetch 错误没法诊断
        let folder = modelContext.fetchFirst(Folder.self, predicate: #Predicate { $0.id == id })
        cachedCurrentFolder = folder
        cachedFolderSelection = sel
        return folder
    }

    /// V6.08: 当前侧栏选中的 tag——同 currentFolder 模式
    /// V6.38.0 (P0 perf): 加 cache (同 currentFolder 模式)
    @ObservationIgnored private var cachedCurrentTag: Tag? = nil
    @ObservationIgnored private var cachedTagSelection: SidebarSelection? = nil
    var currentTag: Tag? {
        let sel = core?.sidebarSelection
        if sel == cachedTagSelection, let cached = cachedCurrentTag { return cached }
        guard case .tag(let id) = sel, let modelContext = core?.modelContext else {
            cachedCurrentTag = nil
            cachedTagSelection = sel
            return nil
        }
        // V6.68 (Q9): fetchFirst 收口 (跟 currentFolder 同模式)
        let tag = modelContext.fetchFirst(Tag.self, predicate: #Predicate { $0.id == id })
        cachedCurrentTag = tag
        cachedTagSelection = sel
        return tag
    }

    /// P4.1.1: 当前侧栏选中的 smartFolder——跟 currentFolder/currentTag 同 UUID fetch 模式
    /// V6.38.0 (P0 perf): 加 cache (同 currentFolder 模式)
    @ObservationIgnored private var cachedCurrentSmartFolder: SmartFolder? = nil
    @ObservationIgnored private var cachedSmartFolderSelection: SidebarSelection? = nil
    var currentSmartFolder: SmartFolder? {
        let sel = core?.sidebarSelection
        if sel == cachedSmartFolderSelection, let cached = cachedCurrentSmartFolder { return cached }
        guard case .smartFolder(let id) = sel, let modelContext = core?.modelContext else {
            cachedCurrentSmartFolder = nil
            cachedSmartFolderSelection = sel
            return nil
        }
        // V6.68 (Q9): fetchFirst 收口
        let sf = modelContext.fetchFirst(SmartFolder.self, predicate: #Predicate { $0.id == id })
        cachedCurrentSmartFolder = sf
        cachedSmartFolderSelection = sel
        return sf
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
    /// V6.38.2 (P0 perf): 加 cache — singleSelectedPhoto/currentIndex/canPrev/canNext 每次 body 各调一次
    ///   之前每次 resolvedSingle = O(n) firstIndex lookup; 一次 body 调 4 次 = 4× O(n) = 4000 ops (1000 photos)
    ///   现在 cache hit: O(1) tuple return
    @ObservationIgnored private var cachedResolvedSingle: (photo: Photo, visibleIndex: Int)? = nil
    @ObservationIgnored private var cachedResolvedSingleKey: Int = 0
    @ObservationIgnored private var resolvedSingleCacheValid: Bool = false
    var resolvedSingle: (photo: Photo, visibleIndex: Int)? {
        let key = resolvedSingleCacheKey()
        if resolvedSingleCacheValid && key == cachedResolvedSingleKey {
            return cachedResolvedSingle
        }
        guard let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }) else {
            cachedResolvedSingle = nil
            cachedResolvedSingleKey = key
            resolvedSingleCacheValid = true
            return nil
        }
        let result = (visiblePhotos[idx], idx)
        cachedResolvedSingle = result
        cachedResolvedSingleKey = key
        resolvedSingleCacheValid = true
        return result
    }

    /// V6.38.2: cache key — singleSelectedID + visiblePhotos cache key 复合
    ///   singleSelectedID 变化 (单选切换) → cache miss
    ///   visiblePhotos 变化 (filter) → cache miss (visibleCacheKey 变)
    private func resolvedSingleCacheKey() -> Int {
        var hasher = Hasher()
        hasher.combine(selection.singleSelectedID)
        hasher.combine(cachedVisibleKey)
        hasher.combine(visibleCacheValid)
        return hasher.finalize()
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
    ///   V6.38.0 (P0 perf): 加 cache — ContentView body 5-10× 读 visiblePhotos,
    ///     之前每次都跑全库 filter+sort (~50K array ops for 1000 photos).
    ///     仿 V6.20.0 libraryStats pattern: filterSignature hash 作 invalidation key.
    ///     仅 filter inputs 真变时才重算. Hash key 包含:
    ///       - allPhotos.count (新增/删除触发)
    ///       - currentFolder.id / currentTag.id / currentSmartFolder.id (sidebar 切换)
    ///       - searchText / sortOption (text 输入 + 排序)
    ///       - 5 个 sidebar flag (unfiled/duplicates/recent7Days/largeFiles/inTrash)
    ///       - filterState 4 维 (folders/tags/shapes/minRating)
    ///     注意: smartFolderFilter 跟 currentSmartFolder.id 同步变, 已包含
    @ObservationIgnored private var cachedVisiblePhotos: [Photo] = []
    @ObservationIgnored private var cachedVisibleKey: Int = 0
    @ObservationIgnored private var visibleCacheValid: Bool = false
    var visiblePhotos: [Photo] {
        let key = visiblePhotosCacheKey()
        if visibleCacheValid && key == cachedVisibleKey {
            return cachedVisiblePhotos
        }
        let computed = PhotoStats.filtered(
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
        cachedVisiblePhotos = computed
        cachedVisibleKey = key
        visibleCacheValid = true
        return computed
    }

    /// V6.38.0: 算 visiblePhotos 缓存 key — 复合 hash of all filter inputs
    ///   用 Hasher 而不是手动位运算: Swift 标准库优化, Set/UUID/Int 自动 hash 正确
    ///   任何 input 变 → key 变 → cache miss → 重算 + 更新 cache
    private func visiblePhotosCacheKey() -> Int {
        var hasher = Hasher()
        hasher.combine(allPhotos.count)
        hasher.combine(currentFolder?.id)
        hasher.combine(currentTag?.id)
        hasher.combine(currentSmartFolder?.id)
        hasher.combine(searchText)
        hasher.combine(sortOption.rawValue)
        hasher.combine(filterUnfiled)
        hasher.combine(filterDuplicates)
        hasher.combine(filterRecent7Days)
        hasher.combine(filterLargeFiles)
        hasher.combine(filterInTrash)
        hasher.combine(core?.filterState.folders)
        hasher.combine(core?.filterState.tags)
        hasher.combine(core?.filterState.shapes)
        hasher.combine(core?.filterState.minRating)
        return hasher.finalize()
    }

    // MARK: - 状态栏 / 详情面板数据

    /// V3.5.6 Finder 化: 总占用空间格式化
    var totalSizeFormatted: String {
        let bytes = PhotoStats.totalSize(allPhotos)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// V3.5.19: 当前选中图片总大小
    /// V6.38.1: 走 selectedPhotosInVisible cache (单次 evaluate, O(1) cache hit)
    var selectedTotalSize: Int64 {
        selectedPhotosInVisible
            .reduce(0) { $0 + $1.fileSize }
    }

    /// V6.38.1 (P0 perf): `selectedPhotosInVisible` cache
    ///   12 处 caller (selectedTotalSize computed + 11 user actions), 之前每次都 O(n) filter
    ///     - copyToPasteboard / shareSelectedURLs / rotateSelected / speakSelection
    ///     - batchDelete / batchMove / batchAddTag / batchRename / batchSetRating / batchExport
    ///     - performOnSelectedTrash
    ///   现在 cache 命中: O(1). key 复合 (selection.selectedIDs + visible cache key)
    ///     任一变化 → cache miss → 重算
    @ObservationIgnored private var cachedSelectedInVisible: [Photo] = []
    @ObservationIgnored private var cachedSelectedInVisibleKey: Int = 0
    @ObservationIgnored private var selectedInVisibleCacheValid: Bool = false
    var selectedPhotosInVisible: [Photo] {
        let key = selectedInVisibleCacheKey()
        if selectedInVisibleCacheValid && key == cachedSelectedInVisibleKey {
            return cachedSelectedInVisible
        }
        let computed = selection.selectedPhotos(in: visiblePhotos)
        cachedSelectedInVisible = computed
        cachedSelectedInVisibleKey = key
        selectedInVisibleCacheValid = true
        return computed
    }

    /// V6.38.1: cache key — selectedIDs + visiblePhotos cache key 复合
    ///   selection.selectedIDs 变化 (用户操作) → cache miss
    ///   visiblePhotos 变化 (filter 变化) → cache miss (visibleCacheKey 变)
    private func selectedInVisibleCacheKey() -> Int {
        var hasher = Hasher()
        hasher.combine(selection.selectedIDs)
        hasher.combine(cachedVisibleKey)
        hasher.combine(visibleCacheValid)
        return hasher.finalize()
    }

    /// V3.6: 回收站视图 count + size
    var trashedCount: Int { PhotoStats.trashed(allPhotos).count }
    var trashedTotalSize: Int64 { PhotoStats.trashedSize(allPhotos) }

    // V6.20.0 (code audit fix #6): libraryStats 缓存 — PhotoStatsSnapshot.compute 每次 body 重渲都重算
    //   @Query allPhotos 任何 SwiftData write (import/delete/tag/rating/drag-drop) 都触发 SidebarView body 重渲染
    //   之前 7-8 遍 O(n) (V6.19.2 P0 #11 优化前) 改 2 遍 (snapshot) 仍 per-render 重算 — 大库 + 频繁写入场景下卡顿
    // V6.59 (audit P2.5): cache key 加 photos.map(\.id) hash (跟 count XOR)
    //   之前 key 只看 count: trash/restore 不改 count 但改 trashedCount → sidebar stale
    //   现在 key 看 count + content fingerprint: 任何 photo insert/delete/edit 必失效
    @ObservationIgnored private var cachedLibraryStats: PhotoStatsSnapshot?
    @ObservationIgnored private var libraryStatsCacheKey: Int = 0
    private var libraryStatsCurrentKey: Int {
        allPhotos.count &* (allPhotos.reduce(0) { $0 &+ $1.id.hashValue })
    }
    var libraryStats: PhotoStatsSnapshot {
        let key = libraryStatsCurrentKey
        if let cached = cachedLibraryStats, libraryStatsCacheKey == key {
            return cached
        }
        let snapshot = PhotoStatsSnapshot.compute(allPhotos)
        cachedLibraryStats = snapshot
        libraryStatsCacheKey = key
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
        case .all, .none:           return Copy.gridViewTitleAll
        case .unfiled:              return Copy.sidebarUnfiled
        case .duplicates:           return Copy.sidebarDuplicates
        case .recent7Days:          return Copy.gridTitleRecent7Days
        case .largeFiles:           return Copy.gridTitleLargeFiles
        case .recentlyDeleted:      return Term.recycleBin
        case .folder:               return currentFolder?.name ?? Copy.gridViewTitleAll
        case .tag:                  return currentTag.map { "#\($0.name)" } ?? Copy.gridViewTitleAll
        // P4.1.1: 智能文件夹标题 — 名字来自 decoded entity, 删除时 fallback "智能文件夹"
        case .smartFolder:          return currentSmartFolder?.name ?? Copy.smartFolderFallback
        }
    }

    /// V4.2.0 P0❸: subtitle——"N 张 · X MB"
    ///   V4.36.x: 工具栏筛选激活时追加 "· 已筛选 (N)"
    ///   V6.38.0 (P0 perf): 单次 evaluate visiblePhotos (之前 .count + .reduce = 2 次 cache miss,
    ///     即使 cache 后也是 2 次 hashtable lookup). 提取到 let 单次访问.
    var currentViewSubtitle: String {
        let photos = visiblePhotos
        let count = photos.count
        let bytes = photos.reduce(Int64(0)) { $0 + $1.fileSize }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        var s = Copy.statusCountAndSize(count, size: size)
        if let activeCount = core?.filterState.activeCount, core?.filterState.isActive == true {
            s += Copy.statusFilteredSuffix(activeCount)
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
        return n == 0 ? Copy.deleteConfirmTitle : Copy.alertDeleteNPhotos(n)
    }

    /// V4.0.0: 重复检测 dialog title
    /// V6.28.1: importDuplicateCheck 迁 ImportViewModel — 走 core?.importVM.importDuplicateCheck
    var duplicateDialogTitle: String {
        guard let check = core?.importVM.importDuplicateCheck else { return "" }
        return Copy.duplicatesFoundBreakdown(check.existing.count, newCount: check.newCount)
    }

    /// V6.62: 搜索自动建议 — 最近搜索词（搜索框 .searchSuggestions 用）
    /// V6.74.4: 加 recordRecentSearch() 真正接入 — 由 ContentView .onSubmit(of: .search) 触发
    var recentSearches: [String] = []

    /// V6.74.4: 记录最近搜索 — dedup (大小写不敏感) + trim 非空 + cap 20
    ///   触发时机: ContentView .onSubmit(of: .search) (用户回车 / 提交)
    ///   行为: 重复词移到最前 (Photos / Finder 范式), 超过 20 截断
    ///   不在 setter 自动触发: 避免用户输入 "ca" → "t" 时 rec "ca"
    func recordRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var deduped = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        deduped.insert(trimmed, at: 0)  // 最新在最前
        if deduped.count > 20 {
            deduped = Array(deduped.prefix(20))
        }
        recentSearches = deduped
    }

    // MARK: - Init

    /// V6.28: GridViewModel init — Core (ContentViewModel) 反向注入 weak ref
    ///   settings/undoManager 共享实例 (Core 同对象)
    init(settings: UserSettings, undoManager: ImageGalleryUndoManager) {
        self.settings = settings
        self.undoManager = undoManager
    }

}

// MARK: - Grid model change notification
extension Notification.Name {
    /// V6.XX: 发送时机: 删除/移动/评分等操作后 — PhotoGridView 通过 .onReceive 监听并触发布局刷新
    static let gridModelDidChange = Notification.Name("gridModelDidChange")
}

