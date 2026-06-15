//
//  ContentViewModel.swift
//  ImageGallery
//
//  V5.52 NEW: ContentView 的 @Observable 业务模型
//  把 ContentView 的 22 个 @State + 12 个 @AppStorage + 30+ computed + 41 methods + configureNSToolbar 全部抽到这里
//
//  关键约束 (从 V5.52 探索确定):
//    - @Observable + @MainActor + final class (macOS 14+ 已是项目标准, ImageGalleryUndoManager 沿用)
//    - modelContext init 注入 (不能 @Environment 因为非 View)
//    - @Query 不能进 class——由 view 通过 .onChange 推过来 (3 个 @ObservationIgnored 缓存)
//    - 12 @AppStorage 不能进 class——由 view 推到 Settings 字段
//    - ToolbarController.shared 12 个闭包原本 [self] capture struct value copy——现在 capture [model] (class stable ref)
//
//  阶段:
//    - V5.52-1: skeleton ✓
//    - V5.52-2: UserSettings 12 var ✓
//    - V5.52-3: 22 个 business @State ✓
//    - V5.52-4: 30+ computed (本文件) ← 当前
//    - V5.52-5: 41 funcs
//    - V5.52-6: configureToolbar
//    - V5.52-7: @Query 推送 .onChange + pane builders
//

import Foundation
import SwiftUI
import SwiftData

/// V5.52: ContentView 的业务模型——@MainActor @Observable 单一根
@MainActor
@Observable
final class ContentViewModel {
    /// V5.52-2: 12 keys UserDefaults 镜像
    var settings = UserSettings()

    /// V5.52-3: modelContext 由 .task 注入
    @ObservationIgnored var modelContext: ModelContext? = nil

    /// V5.52-3: 22 个 business @State

    var selection = SelectionState()
    var sidebarSelection: SidebarSelection? = .all
    var filterState = FilterState()
    var searchText = ""
    var thumbnailSize: CGFloat = 200
    var sortOption: SortOption = .filenameAsc
    var showingBatchDeleteConfirm = false
    var showingEmptyTrashConfirm = false
    var importDuplicateCheck: ImageImporter.DuplicateCheckResult? = nil
    var pendingImportURLs: [URL] = []
    var showingNewFolderAlert = false
    var newFolderName = ""
    var immersivePhoto: Photo? = nil
    var immersiveIndex: Int = 0
    var storageErrorMessage: String? = nil
    var titlebarAccessory: TitlebarAccessoryController? = nil
    var toastQueue: [ToastInfo] = []
    var toastTask: Task<Void, Never>? = nil
    var undoManager = ImageGalleryUndoManager()
    var sidebarColumnWidth: CGFloat = 220
    var detailColumnWidth: CGFloat = 360
    var sidebarDragStartWidth: CGFloat = 220
    var detailDragStartWidth: CGFloat = 360

    // MARK: - V5.52-4: 30+ computed properties 搬到 model

    // V5.52-7 起步: @Query 缓存 (view 通过 .onChange 推过来)
    ///   V5.52-4 computed 已经引用——V5.52-7 再加 .onChange
    @ObservationIgnored var allPhotos: [Photo] = []
    @ObservationIgnored var folders: [Folder] = []
    @ObservationIgnored var allTags: [Tag] = []

    // MARK: 配置 wrapper (跟 @AppStorage 镜像字段配合)

    /// V3.6.13: viewMode 包装 (从 viewModeRaw 字符串解析)
    var viewMode: ViewMode {
        get { ViewMode(rawValue: settings.viewModeRaw) ?? .grid }
        set { settings.viewModeRaw = newValue.rawValue }
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

    // MARK: 侧栏派生 flag

    /// 当前侧栏选中的 folder (from sidebarSelection .folder case)
    var currentFolder: Folder? {
        if case .folder(let folder) = sidebarSelection { return folder }
        return nil
    }

    /// 当前侧栏选中的 tag
    var currentTag: Tag? {
        if case .tag(let tag) = sidebarSelection { return tag }
        return nil
    }

    var filterUnfiled: Bool {
        if case .unfiled = sidebarSelection { return true }
        return false
    }

    var filterDuplicates: Bool {
        if case .duplicates = sidebarSelection { return true }
        return false
    }

    var filterRecent7Days: Bool {
        if case .recent7Days = sidebarSelection { return true }
        return false
    }

    var filterLargeFiles: Bool {
        if case .largeFiles = sidebarSelection { return true }
        return false
    }

    var filterInTrash: Bool {
        if case .recentlyDeleted = sidebarSelection { return true }
        return false
    }

    var filterInDuplicates: Bool {
        if case .duplicates = sidebarSelection { return true }
        return false
    }

    // MARK: 选中派生

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

    // MARK: 可见照片 (核心: 筛选 + 排序后)

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
            selectedFolderIDs: filterState.folders,
            selectedTagIDs: filterState.tags,
            selectedShapes: filterState.shapes,
            minRating: filterState.minRating
        )
    }

    // MARK: 状态栏 / 详情面板数据

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

    /// V3.6.15: 重复图 group / purgeable count / size
    var duplicateGroupCount: Int { PhotoStats.duplicateGroups(in: visiblePhotos).count }
    var duplicatePurgeableCount: Int { PhotoStats.duplicatesToPurge(in: visiblePhotos).count }
    var duplicatePurgeableSize: Int64 {
        PhotoStats.duplicatesToPurge(in: visiblePhotos).reduce(0) { $0 + $1.fileSize }
    }

    // MARK: navigation title / subtitle

    /// V4.2.0 P0❸: navigationTitle——给 Dock / ⌘⇥ / Mission Control / VoiceOver 用
    var currentViewTitle: String {
        switch sidebarSelection {
        case .all, .none:           return "全部照片"
        case .unfiled:              return "待整理"
        case .duplicates:           return "重复图"
        case .recent7Days:          return "最近 7 天"
        case .largeFiles:           return "大图（>5MB）"
        case .recentlyDeleted:      return Term.recycleBin
        case .folder(let f):        return f.name
        case .tag(let t):           return "#\(t.name)"
        }
    }

    /// V4.2.0 P0❸: subtitle——"N 张 · X MB"
    ///   V4.36.x: 工具栏筛选激活时追加 "· 已筛选 (N)"
    var currentViewSubtitle: String {
        let count = visiblePhotos.count
        let bytes = visiblePhotos.reduce(Int64(0)) { $0 + $1.fileSize }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        var s = "\(count) 张 · \(size)"
        if filterState.isActive {
            s += " · 已筛选 (\(filterState.activeCount))"
        }
        return s
    }

    /// V4.4.8: toolbar 搜索框左 padding——跟 grid 左缘对齐
    var searchFieldLeadingOffset: CGFloat {
        guard settings.showSidebar else { return 12 }
        let togglePlusSpacing: CGFloat = 64
        return max(12, sidebarColumnWidth - togglePlusSpacing)
    }

    // MARK: 列宽 (columnLayout 内部用——MainSplitView 接收 ColumnLayoutState)

    /// V3.5.12: 列宽约束常量
    let sidebarMinWidth: CGFloat = 160
    let sidebarMaxWidth: CGFloat = 320
    let detailMinWidth: CGFloat = 340
    let detailMaxWidth: CGFloat = 480
    let contentMinWidth: CGFloat = 400

    // MARK: 派生 string

    /// V4.0.0: dialog 标题——批量删除 (复用 showingDuplicateCheck binding 模式)
    var batchDeleteTitle: String {
        let n = selection.selectedIDs.count
        return n == 0 ? Copy.deleteConfirmTitle : "\(n) 张图片"
    }

    /// V4.0.0: 重复检测 dialog title
    var duplicateDialogTitle: String {
        guard let check = importDuplicateCheck else { return "" }
        return "发现 \(check.existing.count) 张已存在 / \(check.newCount) 张新文件"
    }

    /// V5.52-1 起步: 无参 init——modelContext 由 .task 注入
    init() {}
}
