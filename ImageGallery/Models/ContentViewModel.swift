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
    /// V3.6 导入进度 (V5.53 搬过来——startImport/importPhotos 都需要)
    var importProgress: ImportProgress? = nil

    // MARK: - V5.55-2: P0 滚动位置保留
    // 绑 SwiftUI .scrollPosition(id:)——滚动时自动更新
    // .onChange 同步到 settings.scrollAnchorPhotoID (持久化)
    // 启动时 .task 读 settings.scrollAnchorPhotoID 恢复
    /// 字符串 (UUID) 而非 UUID?——SwiftUI Binding<String?> 兼容
    var scrollAnchorPhotoID: String? = nil

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

    // MARK: V5.56 Key Photo——每日期组代表图

    /// V5.56: DateGroup 代表图 (每组 1 张)——sidebar 折叠 / DateSectionHeader 用
    /// 优先级 (从高到低):
    ///   1. group.photos.first 排除 trashed (避免代表图指向已删)
    ///   2. fallback 到 group.photos.first (即使全 trashed 也返回某张)
    ///   3. group.photos 为空 → nil
    /// 时间复杂度 O(n) (group 内 photos 数量, 实际 n ≤ 几十)
    /// group.photos 已按 importedAt 降序 (PhotoStats.groupByDate 实现)
    func representativePhoto(for group: DateGroup) -> Photo? {
        if let live = group.photos.first(where: { !$0.isInTrash }) {
            return live
        }
        return group.photos.first
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
        controller.onLayoutModeChange = { [model = self] mode in
            model.layoutMode = mode
            if model.viewMode != .grid {
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
        window.titlebarAppearsTransparent = true

        // V4.37.4: titlebar 右上角小按钮（Photos.app ⓘ 风格）
        //   V5.52-6: titlebarAccessory 也搬过来（NSObject 引用，model 持有）
        let accessory = TitlebarAccessoryController(
            inactiveSymbol: "info.circle",
            activeSymbol: "info.circle.fill",
            accessibilityLabel: "信息面板",
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
        isActive ? "隐藏信息面板 (⌘I)" : "显示信息面板 (⌘I)"
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
        sidebarSelection = .folder(folder)
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
        pasteboard.writeObjects(urls as [NSURL])
        showToast(urls.count == 1 ? "已复制 1 张图片" : "已复制 \(urls.count) 张图片", type: .success)
    }

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

    /// ⌘0 reset zoom
    func resetThumbnailSize() {
        thumbnailSize = CGFloat(settings.thumbnailSize)
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
    func runImportWithDuplicateCheck(urls: [URL]) {
        Task { @MainActor in
            guard let modelContext else { return }
            let check = await ImageImporter.checkDuplicatesAsync(
                newURLs: urls,
                in: modelContext
            ) { [self] current, total in
                self.importProgress = ImportProgress(current: current, total: total, isImporting: true)
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
    func importPhotos(urls: [URL]) {
        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        guard let modelContext else { return }
        let importer = ImageImporter(modelContext: modelContext, folder: currentFolder) { [self] current, total, inserted, failureCount in
            Task { @MainActor in
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
        var result: [URL] = []
        let fileManager = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let contents = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    result.append(contentsOf: expandFolders(contents))
                }
            } else {
                result.append(url)
            }
        }
        return result
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
    func batchMove(to folder: Folder?) {
        let photosToMove = selection.selectedPhotos(in: visiblePhotos)
        guard !photosToMove.isEmpty, let modelContext else { return }
        let oldFolders = photosToMove.map { $0.folder }
        let count = photosToMove.count
        let folderName = folder?.name ?? "待整理"

        undoManager.registerAction(
            description: "移动 \(count) 张照片到 \(folderName)"
        ) {
            for photo in photosToMove {
                photo.folder = folder
            }
            modelContext.saveWithLog()
            self.selection = .empty
        } undo: {
            for (photo, oldFolder) in zip(photosToMove, oldFolders) {
                photo.folder = oldFolder
            }
            modelContext.saveWithLog()
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
        case .folder(let f): return "folder:\(f.id.uuidString)"
        case .tag(let t): return "tag:\(t.id.uuidString)"
        case .recentlyDeleted: return "recentlyDeleted"
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
                    let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == uuid })
                    if let folder = try? modelContext.fetch(descriptor).first {
                        return .folder(folder)
                    }
                }
            }
            if key.hasPrefix("tag:") {
                let uuidStr = String(key.dropFirst(4))
                if let uuid = UUID(uuidString: uuidStr) {
                    let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == uuid })
                    if let tag = try? modelContext.fetch(descriptor).first {
                        return .tag(tag)
                    }
                }
            }
            return .all
        }
    }

    /// V5.52-1 起步: 无参 init——modelContext 由 .task 注入
    init() {}
}
