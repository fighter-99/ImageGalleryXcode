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
import UniformTypeIdentifiers
import AVFoundation  // V6.19.5 (P0 #16): speakSelection() AVSpeechSynthesizer

/// V5.52: ContentView 的业务模型——@MainActor @Observable 单一根
@MainActor
@Observable
final class ContentViewModel {
    /// V5.52-2: 13 keys UserDefaults 镜像 (V5.58-1 init 从 UserDefaults 读)
    /// V5.59-1: var → let + 接受外部注入 (默认 UserSettings() 兼容现有测试)
    ///   ImageGalleryApp.sharedSettings 传同一引用进来, ContentViewModel 与 menu/SettingsView 共享
    let settings: UserSettings

    /// V5.52-3: modelContext 由 .task 注入
    @ObservationIgnored var modelContext: ModelContext? = nil

    /// V5.52-3: 22 个 business @State

    var selection = SelectionState()
    var sidebarSelection: SidebarSelection? = nil  // V5.59-2: init 时从 settings.sidebarSelection 反序列化
    var filterState = FilterState()
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
    //   @ObservationIgnored: 不需要 observation tracking (fire-and-forget throttle)
    //   instance var (不是 static): Swift extension 不能有 stored property, instance var 放 model 上
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
    /// V3.6 导入进度 (V5.53 搬过来——startImport/importPhotos 都需要)
    var importProgress: ImportProgress? = nil

    // MARK: - V5.55-2: P0 滚动位置保留
    // 绑 SwiftUI .scrollPosition(id:)——滚动时自动更新
    // .onChange 同步到 settings.scrollAnchorPhotoID (持久化)
    // 启动时 .task 读 settings.scrollAnchorPhotoID 恢复
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

    // MARK: - V5.52-4: 30+ computed properties 搬到 model

    // V5.52-7 起步: @Query 缓存 (view 通过 .onChange 推过来)
    ///   V5.52-4 computed 已经引用——V5.52-7 再加 .onChange
    @ObservationIgnored var allPhotos: [Photo] = []
    @ObservationIgnored var folders: [Folder] = []
    @ObservationIgnored var allTags: [Tag] = []
    /// P4.1.1: smartFolders cache — 跟 allPhotos/folders/allTags 同 pattern
    ///   ContentView .onChange(of: smartFolders) 推送; createSmartFolder 用 max+1 算 order
    @ObservationIgnored var smartFoldersCache: [SmartFolder] = []

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

    /// V6.08: 当前侧栏选中的 folder——从 modelContext 按 UUID fetch
    ///   之前 .folder(Folder) 直接返回 @Model 引用, folder 被删后引用悬挂
    ///   现在存 UUID 每次 fetch, 删 folder 自动 nil → UI 自动切回 .all
    /// V6.10: try? modelContext.fetch(...)——fetch throws, 失败返 nil 走 .all
    var currentFolder: Folder? {
        guard case .folder(let id) = sidebarSelection, let modelContext else { return nil }
        return (try? modelContext.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// V6.08: 当前侧栏选中的 tag——同 currentFolder 模式
    var currentTag: Tag? {
        guard case .tag(let id) = sidebarSelection, let modelContext else { return nil }
        return (try? modelContext.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// P4.1.1: 当前侧栏选中的 smartFolder——跟 currentFolder/currentTag 同 UUID fetch 模式
    ///   删后自动返 nil (V6.08 dangling ref 防护)
    var currentSmartFolder: SmartFolder? {
        guard case .smartFolder(let id) = sidebarSelection, let modelContext else { return nil }
        return (try? modelContext.fetch(FetchDescriptor<SmartFolder>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// P4.1.1: 当前 smartFolder 的 filter (decoded)
    ///   nil = no smart folder active; .empty (isActive=false) = 激活但无 constraint, 走 no-op
    var smartFolderFilter: FilterState? {
        currentSmartFolder?.decodedFilter
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
            minRating: filterState.minRating,
            // P4.1.1: smart folder filter 跟 toolbar filter 独立 AND 应用
            smartFolderFilter: smartFolderFilter
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

    // V6.20.0 (code audit fix #6): libraryStats 缓存 — PhotoStatsSnapshot.compute 每次 body 重渲都重算
    //   @Query allPhotos 任何 SwiftData write (import/delete/tag/rating/drag-drop) 都触发 SidebarView body 重渲染
    //   之前 7-8 遍 O(n) (V6.19.2 P0 #11 优化前) 改 2 遍 (snapshot) 仍 per-render 重算 — 大库 + 频繁写入场景下卡顿
    //   修: 缓存 snapshot + allPhotos.count 比较 (O(1) invalidation key)
    //   libraryStats getter: cache hit → return cached; cache miss → compute + cache + return
    //   ContentView .onChange(of: allPhotos) 同步更新 countInCache 触发失效
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

    // MARK: V5.56 Key Photo——每日期组代表图

    /// V5.56: DateGroup 代表图 (每组 1 张)——sidebar 折叠 / DateSectionHeader 用
    /// 优先级 (从高到低):
    ///   1. group.photos.first 排除 trashed (避免代表图指向已删)
    ///   2. fallback 到 group.photos.first (即使全 trashed 也返回某张)
    ///   3. group.photos 为空 → nil
    /// 时间复杂度 O(n) (group 内 photos 数量, 实际 n ≤ 几十)
    /// group.photos 已按 importedAt 降序 (PhotoStats.groupByDate 实现)
    /// V6.11: 全 trashed 时返 nil——之前 fallback group.photos.first 返 trashed photo
    ///   DateSectionHeader 会显示灰缩略图, UX 差。返 nil 让 DateSectionHeader 走 text-only 分支
    ///   (line 39 init 没 representative 时不显示缩略图, label + count 清晰)
    func representativePhoto(for group: DateGroup) -> Photo? {
        return group.photos.first(where: { !$0.isInTrash })
    }

    // MARK: navigation title / subtitle

    /// V4.2.0 P0❸: navigationTitle——给 Dock / ⌘⇥ / Mission Control / VoiceOver 用
    /// V6.08: .folder/.tag 改 UUID 存储, 名字从 modelContext fetch
    var currentViewTitle: String {
        switch sidebarSelection {
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

    // MARK: - V5.52-6: configureToolbar 搬过来——12 个 ToolbarController 闭包

    /// V4.8.0: NSToolbar 配置（WindowAccessor 触发）
    /// V5.52-6: 从 ContentView.configureNSToolbar 搬过来
    ///   - 设置 window.toolbar = NSToolbar（AppKit 原生，Photos.app 风格）
    ///   - 设置 NSToolbar.delegate = ToolbarController.shared
    ///   - 设置 NSToolbar 视觉：.iconOnly display + .unified style
    ///   - 绑 12 个 action closures 到 ToolbarController.shared
    ///   - 12 个闭包 capture [model] (class stable ref)——比原 [self] (struct value copy) 更正确
    func configureToolbar(window: NSWindow) {
        // 只在第一次设置
        guard window.toolbar == nil else { return }

        // V3.7.1: 删 V6.12.6 setFrameAutosaveName
        //   - 原计划用 NSWindow.frameAutosaveName 走 macOS autosave (Photos 范式)
        //   - 实测 `defaults read ImageGallery` → "Domain ImageGallery does not exist"
        //     证明 autosave 从来没真存过数据
        //   - 根因: SwiftUI Scene 创建的 NSWindow 不响应 setFrameAutosaveName
        //     (SwiftUI 自己管 frame state, AppKit autosave 绑不住)
        //   - 修法: ImageGalleryApp.swift AppDelegate 自实现 frame 持久化
        //     (NSWindowDelegate.windowDidResize/windowDidMove 写 UserDefaults
        //      + applicationDidFinishLaunching 读 UserDefaults setFrame)
        //   - 4 个 UserDefaults key: imageGalleryWindowSizeW/H, imageGalleryWindowPosX/Y
        //   - configureToolbar 不再做 frame 持久化, AppDelegate 接管

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        toolbar.delegate = ToolbarController.shared
        toolbar.displayMode = .iconOnly
        // V4.8.3: centeredItemIdentifiers = [.search] 让搜索框居中
        //   (Photos.app 风格——搜索框与 grid 中线对齐)
        //   5 actions 走默认 .principalItems 区域，在 trailing 端
        toolbar.centeredItemIdentifiers = [ToolbarController.Identifier.search.nsIdentifier]
        toolbar.allowsUserCustomization = true   // 用户可自定义 toolbar items
        toolbar.autosavesConfiguration = true   // 自定义状态自动保存
        toolbar.showsBaselineSeparator = false  // 不显示底部分隔线
        // V6.13.2: 允许 displayMode 切换 (macOS 14+ Photos.app 范式)
        //   用户点 toolbar title → menu 切 Icon Only / Icon and Text / Text Only / Use Small Size
        //   NSToolbar 自动 rebuild, makeSimpleItem 已用 label="" + image 跟所有 mode 兼容
        //   NSSearchToolbarItem + NSMenuToolbarItem 自动 follow displayMode
        if #available(macOS 14.0, *) {
            toolbar.allowsDisplayModeCustomization = true
        }

        // 绑 action closures
        // V5.52-6: [model] capture (class stable ref)——比原 [self] (struct value copy) 更正确
        //   避免 struct 改 self 拷贝的 footgun; class ref 稳定 + @Observable 追踪
        let controller = ToolbarController.shared
        controller.onToggleSidebar = { [model = self] in
            withAnimation(Animations.medium) { model.settings.showSidebar.toggle() }
        }
        // V5.7: 砍 onToggleFavorite——工具栏 ❤ 收藏按钮已移除
        controller.onBatchExport = { [model = self] in
            model.batchExport()
        }
        controller.onDelete = { [model = self] in
            model.handleDelete()
        }
        controller.onImport = { [model = self] in
            model.startImport()
        }
        // V4.37.1: ⌘Y Quick Look——复用 showQuickLook()（与空格键同路径）
        controller.onQuickLook = { [model = self] in
            model.showQuickLook()
        }
        // V4.37.2: ⌘[ / ⌘] 上下张切换（macOS Quick Look 标准）
        controller.onPrev = { [model = self] in
            model.goPrev()
        }
        controller.onNext = { [model = self] in
            model.goNext()
        }
        // V5.24 NEW: 布局模式 + 密度 toolbar 集成桥接
        // V5.55-3 bug fix: 若当前 viewMode 是 .list/.timeline, 选 layoutMode 不生效
        // (gridPane 才用 layoutMode——list/timeline 视图下选无效果)
        // 自动切到 .grid 让用户选的 layoutMode 立即可见
        // V6.12.14: ThumbnailLayoutMode 加 .list 后——选 .list 切 viewMode = .list
        //   之前总是强制 .grid; 现在按 mode 切对应 viewMode
        //   .grid (.squareFit) → viewMode = .grid
        //   .list             → viewMode = .list
        //   thumbnailSize/density 等其他 toolbar 不变, 只换 viewMode 配合
        controller.onLayoutModeChange = { [model = self] mode in
            model.layoutMode = mode
            // V6.12.14: 同步切 viewMode——list 选项切到 list 视图, grid 选项回 grid 视图
            switch mode {
            case .list:
                model.viewMode = .list
            case .squareFit:
                model.viewMode = .grid
            }
        }
        controller.onDensityChange = { [model = self] density in
            model.thumbnailSize = density
            // 同步 storedThumbnailSize 以便重启后恢复（V4.15.0 ⌘0 行为一致）
            model.settings.thumbnailSize = Double(density)
        }
        // V5.39.3 NEW: 排序 toolbar 桥接
        controller.onSortOptionChange = { [model = self] newSort in
            model.sortOption = newSort
        }
        // V4.90.0: filterContentProvider 改 filterCoordinatorFactory
        //   注意: folders/allTags 是 Q-bucket (view-owned), 由 caller 在调用时 push 进 model
        // V5.52-7 后: model.folders / model.allTags 由 .onChange 推送
        controller.filterCoordinatorFactory = { [model = self] onStateChange in
            return FilterPopoverCoordinator(
                folders: model.folders,
                tags: model.allTags,
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
            if model.searchText != newText {
                model.searchText = newText
            }
        }

        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        // V6.12.5: 删 window.titlebarAppearsTransparent = true
        //   之前设 .unified + .hidden title + transparent titlebar 三件套, 系统 vibrancy
        //   看不到内容, 整个 toolbar 区域变成纯灰条 (toolbar 按钮还能用但视觉像未完工).
        //   macOS .unified toolbarStyle 已经自带磨砂 vibrancy——只要 titlebar 不强行
        //   transparent, 系统会自动显示半透背景让窗口内容透上来 (Photos.app 实际靠这个).
        //   titleVisibility = .hidden 保留 (不要 title 文字, 只要 chrome 区域)

        // V4.37.4: titlebar 右上角小按钮（Photos.app ⓘ 风格）
        //   V5.52-6: titlebarAccessory 也搬过来（NSObject 引用，model 持有）
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
            hasSelection: selection.hasSelection,
            hasMultipleSelection: selection.isMultiSelect
        )
    }

    /// V4.37.4: titlebar ⓘ 按钮 tooltip——从 ContentView.titlebarAccessoryTooltip 搬过来
    func titlebarAccessoryTooltip(isActive: Bool) -> String {
        isActive ? Copy.titlebarInfoTooltipHide : Copy.titlebarInfoTooltipShow
    }

    // MARK: - V5.53: 40 funcs + 2 statics 全部搬到 model
    //   V5.52-5 deferred 的 41 funcs 全部实现
    //   ContentView 里的版本改为 1-liner proxy: `private func X() { model.X() }`

    /// V4.11.0: 检查 Application Support/ImageGallery/Photos/ 目录可写性
    ///   PhotoStorage.verifyStorage() 是 v3.6 写但从未调用的死代码——v4.11.0 接入
    func checkStorage() {
        if PhotoStorage.shared.verifyStorage() {
            storageErrorMessage = nil
        } else {
            storageErrorMessage = Copy.storageError
        }
    }

    /// ⌘N 触发的创建文件夹
    func createFolderFromAlert() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
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
        let nextOrder = (smartFoldersCache.map(\.order).max() ?? -1) + 1
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
        sortOption = sortOption.toggledDirection
    }

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
        //   之前 \`writeObjects(urls as [NSURL])\` 只声明 fileURL promise — Photoshop/Pixelmator
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
        showToast(urls.count == 1 ? "已复制 1 张图片" : "已复制 \(urls.count) 张图片", type: .success)
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
            showToast("请先选择要分享的图片", type: .info)
            return []
        }
        return urls
    }

    /// V6.19.5 (P0 #16): 朗读选中照片 (Speech menu, macOS Edit > Speech 范式)
    ///   - selection 空 → toast 提示
    ///   - 1 张 → 读 "已选 1 张照片, 文件名 XXX"
    ///   - N 张 → 读 "已选 N 张照片, 第一张 XXX"
    ///   zh-CN 语音; AVSpeechSynthesizer 一次性 utterance (不持久 synthesizer)
    func speakSelection() {
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty else {
            showToast("请先选择要朗读的图片", type: .info)
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
        //   之前 ?? 链: zh-CN ?? locale ?? "en-US" — 如果 zh-CN 没装 + locale nil + en-US 也没装, voice = nil
        //   AVSpeechSynthesizer 用系统默认 voice (可能英文, 用户无感)
        //   现在 fallback 到 AVSpeechSynthesisVoice() 系统默认 + zh-CN 优先
        let voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
            ?? AVSpeechSynthesisVoice()
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        // V6.20.2 (code audit fix #4): 用 stable synthesizer 实例 + stop 上一个 utterance
        //   之前 \`AVSpeechSynthesizer().speak()\` 每次新建实例, 上一个 utterance 被 cut off + audio glitch
        //   现在 stable instance + stopSpeaking(.immediate) → smooth 切换
        //   macOS Edit > Speech 标准 pattern (一个 app 一个 synthesizer)
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(utterance)
    }

    /// V6.20.2 (code audit fix #4): stable AVSpeechSynthesizer instance — 跨多次 speak() 复用
    ///   @ObservationIgnored: 不需要 observation tracking (speak 是 fire-and-forget)
    private let speechSynthesizer = AVSpeechSynthesizer()

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
        sidebarSelection = .all
        searchText = ""
        filterState = .empty
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

    /// 兼容旧 showToast 调用
    func showToast(_ message: String, type: ToastView.ToastType = .info) {
        enqueueToast(message, type: type, duration: .normal)
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

    /// ─── 启动时清理过期回收站项（V3.6 NEW）───
    func purgeExpiredTrashOnStartup() {
        let days = TrashRetentionDays(rawValue: settings.trashRetentionDays) ?? .defaultValue
        guard let modelContext else { return }
        let service = RecycleBinService(storage: .shared, modelContext: modelContext)
        service.purgeExpired(retentionDays: days.rawValue)
    }

    /// ─── 启动导入 ───
    func startImport() {
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

    /// Finder 拖入导入
    func handleDropImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        runImportWithDuplicateCheck(urls: urls)
    }

    /// V3.6.24: 扫现有 photo + 算新 url fileHash
    /// V3.6.27: 改用 async 版本
    /// V6.11: [weak self] + guard let self——V6.10 C4 修了 importPhotos, runImportWithDuplicateCheck 同 pattern 漏
    ///   SHA256 计算期间 (成百文件) 强 capture 阻 ContentViewModel 释放。view dismiss 后 model 残留
    ///   直到 hash 跑完, 用户体验: 关闭设置窗 立即打开 → 旧 model 还在 → 新 model 跟旧重叠
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
    /// V6.10: [self] → [weak self]——importer 是 local let, 不会长留;
    ///   但 Task 内部 await 期间 (1.5s 延迟清进度) importer 持 self, 阻 model 释放。
    ///   改 [weak self] + guard let self 防 model 中途销毁 (view dismiss) 写 nil
    func importPhotos(urls: [URL]) {
        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        guard let modelContext else { return }
        let importer = ImageImporter(modelContext: modelContext, folder: currentFolder) { [weak self] current, total, inserted, failureCount in
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
        //   跟 ImageImporter.collectFiles 同根因 (C2), 拖入 symlink 环会无限递归
        //   拆出 private overload 持 visited Set, 外部签名不变
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

    /// V4.1.0 l: 切换侧栏 section 时清选中
    func clearSelectionOnFilterChange() {
        if !selection.isEmpty {
            selection = .empty
        }
    }

    /// V3.6: 删除单张 = 移到回收站
    func deleteSinglePhoto() {
        guard let photo = singleSelectedPhoto, let modelContext else { return }
        RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [self] error in
                enqueueToast("移到回收站失败：\(error.localizedDescription)", type: .error, duration: .long)
            }
        ).recycle(photo)
        selection = .empty
        showToast("已移到回收站（\(settings.trashRetentionDays) 天后永久删除）", type: .info)
    }

    /// V3.6: 批量删除
    func batchDelete() {
        performOnSelectedTrash(
            { svc, photos in photos.forEach { svc.recycle($0) } },
            message: { "已移到回收站 \($0) 张" }
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
        guard !photosToMove.isEmpty, let modelContext else { return }
        let oldFolders = photosToMove.map { $0.folder }
        let count = photosToMove.count
        let folderName = folder?.name ?? "未整理"

        undoManager.registerAction(
            description: "移动 \(count) 张照片到 \(folderName)"
        ) { [weak self] in
            for photo in photosToMove {
                photo.folder = folder
            }
            modelContext.saveWithLog()
            self?.selection = .empty
        } undo: { [weak self] in
            for (photo, oldFolder) in zip(photosToMove, oldFolders) {
                photo.folder = oldFolder
            }
            modelContext.saveWithLog()
            _ = self  // 强引用 self 进闭包, 防止 self 释放时 undo 操作失败
        }
    }

    /// 批量加标签
    func batchAddTag(_ tag: Tag) {
        let photosToTag = selection.selectedPhotos(in: visiblePhotos)
        guard let modelContext else { return }
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
        guard !photos.isEmpty, let modelContext else { return }
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

        undoManager.registerAction(
            description: "批量重命名 \(count) 张照片"
        ) { [weak self] in
            var errors = 0
            for p in plans {
                let newURL = p.oldURL.deletingLastPathComponent()
                    .appendingPathComponent("\(p.newBase).\(p.newExt)")
                do {
                    try FileManager.default.moveItem(at: p.oldURL, to: newURL)
                    p.photo.filename = "\(p.newBase).\(p.newExt)"
                    p.photo.fileURL = newURL
                } catch { errors += 1 }
            }
            modelContext.saveWithLog()
            if errors > 0 {
                self?.enqueueToast("部分重命名失败：\(errors) 张", type: .error, duration: .long)
            } else {
                self?.showToast("已重命名 \(count) 张照片", type: .success)
            }
            _ = self
        } undo: { [weak self] in
            var undoErrors = 0
            // 反向撤销 — 撤销顺序避开 forward 时的写写依赖
            for p in plans.reversed() {
                let newURL = p.oldURL.deletingLastPathComponent()
                    .appendingPathComponent("\(p.newBase).\(p.newExt)")
                do {
                    try FileManager.default.moveItem(at: newURL, to: p.oldURL)
                    p.photo.filename = p.oldFilename
                    p.photo.fileURL = p.oldURL
                } catch { undoErrors += 1 }
            }
            modelContext.saveWithLog()
            if undoErrors > 0 {
                self?.enqueueToast("部分撤销失败：\(undoErrors) 张", type: .error, duration: .long)
            }
            _ = self
        }
    }

    /// V5.12: 批量评分
    func batchSetRating(_ rating: Int) {
        let photosToRate = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToRate.isEmpty, let modelContext else { return }
        BatchSetRatingMath.applyRating(rating, count: photosToRate.count) { index, r in
            photosToRate[index].rating = r
        }
        modelContext.saveWithLog { [self] _ in
            enqueueToast("批量评分失败", type: .error, duration: .long)
        }
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
                enqueueToast("导出失败：\(photo.filename)", type: .error, duration: .long)
            }
        }
        if successCount > 0 {
            showToast("已导出 \(successCount) 张图片", type: .success)
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
    func performOnSelectedTrash(
        _ operation: (RecycleBinService, [Photo]) -> Void,
        message: (Int) -> String,
        type: ToastView.ToastType = .info
    ) {
        let photos = selection.selectedPhotos(in: visiblePhotos)
        guard !photos.isEmpty, let modelContext else { return }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [self] error in
                enqueueToast(
                    Copy.recycleBinOperationFailed(error.localizedDescription),
                    type: .error,
                    duration: .long
                )
            }
        )
        operation(service, photos)
        let count = photos.count
        selection = .empty
        showToast(message(count), type: type)
    }

    /// 恢复选中的照片
    func restoreSelectedFromTrash() {
        performOnSelectedTrash(
            { svc, photos in photos.forEach { svc.restore($0) } },
            message: { "已恢复 \($0) 张图片" },
            type: .success
        )
    }

    /// 永久删除选中的照片
    func permanentDeleteSelected() {
        performOnSelectedTrash(
            { svc, photos in svc.purgeAll(photos) },
            message: { "已永久删除 \($0) 张图片" }
        )
    }

    /// 清空回收站
    func emptyTrash() {
        let trashed = allPhotos.filter { $0.isInTrash }
        guard !trashed.isEmpty, let modelContext else { return }
        RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [self] error in
                enqueueToast("清空回收站失败：\(error.localizedDescription)", type: .error, duration: .long)
            }
        ).purgeAll(trashed)
        let count = trashed.count
        selection = .empty
        showToast("已清空回收站（\(count) 张）", type: .info)
    }

    /// V3.6.15: 重复图清理
    func keepNewestPerDuplicateGroup() {
        let visible = visiblePhotos.filter { !$0.isInTrash }
        let purgeable = PhotoStats.duplicatesToPurge(in: visible)
        guard !purgeable.isEmpty, let modelContext else { return }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [self] error in
                enqueueToast("批量移到回收站失败：\(error.localizedDescription)", type: .error, duration: .long)
            }
        )
        for photo in purgeable { service.recycle(photo) }
        showToast("已移到回收站 \(purgeable.count) 张重复图", type: .info)
    }

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
                    // (下次访问 currentFolder 返回 nil, UI 自动切 .all)
                    // 这里不 fetch——避免无谓 IO, 访问时才 fetch
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
                    // 跟 folder/tag 一样: 不 fetch, 访问时再 fetch
                    // (SmartFolder 删除时 sidebarSelection 自动失效, fetch 返 nil → 切回 .all)
                    return .smartFolder(uuid)
                }
            }
            return .all
        }
    }

    /// V5.52-1 起步: 无参 init——modelContext 由 .task 注入
    /// V5.59-1: 接受 settings 参数 (默认 nil, body 内 fallback 新实例——避免 default expr 不能调 @MainActor init)
    ///   ImageGalleryApp 传 sharedSettings 引用进来, 实现 ContentView/menu/SettingsView 共享
    init(settings: UserSettings? = nil) {
        self.settings = settings ?? UserSettings()
    }
}
