//
//  ContentView.swift
//  ImageGallery
//
//  主视图。整体布局：顶部工具栏 / 三栏布局 / 底部状态栏。
//  状态管理：选中、侧边栏、搜索、缩略图大小、可见列表、导入进度、多选。
//  支持：拖拽导入、Delete 键删除、方向键切换图片、启动记忆、导入进度。
//  多选：⌘+点击加选、⇧+点击范围选择、⌘+A 全选、⌥+拖动框选、Esc 取消。
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// 侧边栏选中项类型
enum SidebarSelection: Hashable {
    case all
    case favorites
    case unfiled
    case duplicates

    // V2: 智能文件夹
    case recent7Days       // 最近 7 天导入
    case largeFiles        // 大图 > 5MB

    case folder(Folder)
    case tag(Tag)

    // V3.6 NEW: 回收站
    case recentlyDeleted
}

struct ContentView: View {
    // 选中的图片（单选 / 详情）
    @State private var selectedPhoto: Photo?

    // 多选状态
    @State private var selectedIDs: Set<UUID> = []
    @State private var lastSelectedID: UUID?  // 范围选择起点
    @State private var isBoxSelecting = false

    // 侧边栏的选中项
    @State private var sidebarSelection: SidebarSelection? = .all

    // 搜索文本
    @State private var searchText = ""

    // 缩略图大小
    @State private var thumbnailSize: CGFloat = 170  // V3.6.13: 保留 @State 用 toolbar 临时调，onChange 同步 stored
    // V3.6.13: viewMode 改用 @AppStorage 持久化（SettingsView 可设默认）
    @AppStorage("viewModeRaw") private var viewModeRaw: String = ViewMode.grid.rawValue
    private var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .grid }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    // 排序方式（Eagle 化工具栏新增）
    @State private var sortOption: SortOption = .importedAtDesc

    // 当前可见图片列表
    @State private var visiblePhotos: [Photo] = []

    // 拖拽状态
    @State private var isDropTargeted = false

    // 导入进度
    @State private var importProgress: ImportProgress?

    // 批量删除确认
    @State private var showingBatchDeleteConfirm = false

    // V3.6.6: 清空回收站二次确认（防误操作：永久删除所有 trashed 项）
    @State private var showingEmptyTrashConfirm = false

    // V3.6.24: 导入时重复检测 dialog（防止 fileHash 重复的图片被再次导入）
    @State private var importDuplicateCheck: ImageImporter.DuplicateCheckResult?
    @State private var pendingImportURLs: [URL] = []

    // 批量移动
    // （showingBatchMoveSheet 已移除：批量移动流程当前在 PhotoGridView 内联实现，
    //   该状态从未被读。如未来要重新走 sheet 流程再加回。）

    // 新建文件夹弹窗
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""

    // 沉浸式查看
    @State private var immersivePhoto: Photo?
    @State private var immersiveIndex: Int = 0

    // 栏显隐状态（ContentView 唯一持有，ImageGalleryApp 通过 UserDefaults 同步）
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showDetail") private var showDetail = true

    // 设置面板
    @State private var showSettings = false
    @AppStorage("accentColorID") private var accentColorID: String = AccentColor.system.rawValue

    // V3.6 NEW: 回收站保留时长（默认 30 天）
    @AppStorage("trashRetentionDays") private var retentionDays: Int = TrashRetentionDays.defaultValue.rawValue

    // V3.6.22: 应用外观（默认跟随系统）
    @AppStorage("appearanceMode") private var appearanceModeRaw: Int = AppearanceMode.defaultValue.rawValue
    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    // V3.6 NEW: 启动时清理过期回收站项的"只跑一次"标记
    // ContentView 可能多次出现（开关窗口、切 sidebar），用 flag 避免重复清理
    @State private var hasPurgedExpiredTrash = false

    // 当前选中的强调色（从 accentColorID 解析）
    private var accentColor: AccentColor {
        AccentColor(rawValue: accentColorID) ?? .system
    }

    // Toast 提示
    @State private var toast: ToastInfo?
    @State private var toastTask: Task<Void, Never>?

    // SwiftData：获取所有图片（用于状态栏显示总数）
    @Query private var allPhotos: [Photo]
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]
    @Query(sort: \Tag.createdAt, order: .forward) private var allTags: [Tag]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext

    // V3.5 Phase 1 Step 4：撤销/重做（@Observable + @State 模式）
    @State private var undoManager = ImageGalleryUndoManager()

    // 启动记忆
    @AppStorage("thumbnailSize") private var storedThumbnailSize: Double = 170
    @AppStorage("sidebarSelection") private var storedSidebarKey: String = "all"
    @AppStorage("sortOption") private var storedSortOption: String = SortOption.importedAtDesc.rawValue

    // V3.5.12：三栏列宽（HStack + 自定义 drag handles，避开 NSSplitView）
    @AppStorage("sidebarColumnWidth") private var storedSidebarWidth: Double = 220
    @AppStorage("detailColumnWidth") private var storedDetailWidth: Double = 320
    @State private var sidebarColumnWidth: CGFloat = 220
    @State private var detailColumnWidth: CGFloat = 320
    @State private var sidebarDragStartWidth: CGFloat = 220
    @State private var detailDragStartWidth: CGFloat = 320
    private let sidebarMinWidth: CGFloat = 160
    private let sidebarMaxWidth: CGFloat = 320
    private let detailMinWidth: CGFloat = 240
    private let detailMaxWidth: CGFloat = 480
    private let contentMinWidth: CGFloat = 400

    // 当前的筛选条件
    private var currentFolder: Folder? {
        if case .folder(let folder) = sidebarSelection { return folder }
        return nil
    }

    private var currentTag: Tag? {
        if case .tag(let tag) = sidebarSelection { return tag }
        return nil
    }

    private var filterFavorites: Bool {
        if case .favorites = sidebarSelection { return true }
        return false
    }

    private var filterUnfiled: Bool {
        if case .unfiled = sidebarSelection { return true }
        return false
    }

    private var filterDuplicates: Bool {
        if case .duplicates = sidebarSelection { return true }
        return false
    }

    private var filterRecent7Days: Bool {
        if case .recent7Days = sidebarSelection { return true }
        return false
    }

    private var filterLargeFiles: Bool {
        if case .largeFiles = sidebarSelection { return true }
        return false
    }

    // V3.6 NEW: 回收站筛选
    private var filterInTrash: Bool {
        if case .recentlyDeleted = sidebarSelection { return true }
        return false
    }

    // V3.6.15 NEW: 重复图筛选（用于 .duplicates 视图的 count/totalSize 区分）
    private var filterInDuplicates: Bool {
        if case .duplicates = sidebarSelection { return true }
        return false
    }

    // 派生属性
    private var currentIndex: Int {
        guard let id = selectedIDs.first ?? selectedPhoto?.id,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }) else {
            return 0
        }
        return idx + 1
    }

    private var canPrev: Bool { currentIndex > 1 }
    private var canNext: Bool { currentIndex > 0 && currentIndex < visiblePhotos.count }

    // 单选图片（多选时为 nil）
    private var singleSelectedPhoto: Photo? {
        guard selectedIDs.count <= 1, let id = selectedIDs.first ?? selectedPhoto?.id else { return nil }
        return visiblePhotos.first(where: { $0.id == id })
    }

    // 多选模式（>1 张）
    private var isMultiSelect: Bool { selectedIDs.count > 1 }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    // V3.5.6 Finder 化：总占用空间格式化
    private var totalSizeFormatted: String {
        let bytes = PhotoStats.totalSize(allPhotos)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // V3.5.19：当前选中图片的总大小（字节）
    // 用于多选详情面板显示 "已选 N 张 · 12.3 MB"
    private var selectedTotalSize: Int64 {
        visiblePhotos
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    // V3.6 NEW: 回收站视图用的 count + totalSize
    // DetailPane 在 .recentlyDeleted 模式下显示这两个值
    // V3.6.1：用 PhotoStats 纯函数（之前在 SidebarView 也重复算过 trashed）
    private var trashedCount: Int {
        PhotoStats.trashed(allPhotos).count
    }

    private var trashedTotalSize: Int64 {
        PhotoStats.trashedSize(allPhotos)
    }

    // V3.6.15 NEW: 重复图视图用的 group count + purgeable count + size
    // DetailPane 在 .duplicates 模式下显示这些值
    /// 重复组数（fileHash 相同且 ≥ 2 张）
    private var duplicateGroupCount: Int {
        PhotoStats.duplicateGroups(in: visiblePhotos).count
    }

    /// 可清理照片数（每组保留最新，其他）
    private var duplicatePurgeableCount: Int {
        PhotoStats.duplicatesToPurge(in: visiblePhotos).count
    }

    /// 可清理照片总大小
    private var duplicatePurgeableSize: Int64 {
        PhotoStats.duplicatesToPurge(in: visiblePhotos).reduce(0) { $0 + $1.fileSize }
    }

    // V3.5.17：把 6 个宽度 state vars + 4 个约束 + 2 个 AppStorage 钩子打包
    // 给 MainSplitView 使用
    private var columnLayout: ColumnLayoutState {
        ColumnLayoutState(
            sidebarColumnWidth: $sidebarColumnWidth,
            detailColumnWidth: $detailColumnWidth,
            sidebarDragStartWidth: $sidebarDragStartWidth,
            detailDragStartWidth: $detailDragStartWidth,
            sidebarMinWidth: 160,
            sidebarMaxWidth: 320,
            detailMinWidth: 240,
            detailMaxWidth: 480,
            onSidebarDragEnd: { storedSidebarWidth = Double(sidebarColumnWidth) },
            onDetailDragEnd: { storedDetailWidth = Double(detailColumnWidth) },
            restoreFromStorage: {
                sidebarColumnWidth = CGFloat(storedSidebarWidth)
                detailColumnWidth = CGFloat(storedDetailWidth)
            }
        )
    }

    var body: some View {
        mainLayout
            // V3.6.22: 应用外观（浅色/深色/跟随系统）
            .preferredColorScheme(appearanceMode.colorScheme)
            .onAppear {
                thumbnailSize = CGFloat(storedThumbnailSize)
                sidebarSelection = restoreSelection(storedSidebarKey)
                sortOption = SortOption(rawValue: storedSortOption) ?? .importedAtDesc
                // V3.6 NEW: 启动时清理过期回收站项（只跑一次）
                if !hasPurgedExpiredTrash {
                    hasPurgedExpiredTrash = true
                    purgeExpiredTrashOnStartup()
                }
            }
            // V3.6.13: 监听 SettingsView 修改 storedThumbnailSize，实时同步当前 session
            // 避免\"重启后生效\"的尴尬
            .onChange(of: storedThumbnailSize) { _, new in
                thumbnailSize = CGFloat(new)
            }
            .onChange(of: storedSortOption) { _, new in
                sortOption = SortOption(rawValue: new) ?? .importedAtDesc
            }
            // V3.6.13: viewModeRaw 通过 computed property 自动响应 AppStorage 变化
            .onChange(of: viewModeRaw) { _, _ in }
            .onChange(of: thumbnailSize) { _, new in
                storedThumbnailSize = Double(new)
            }
            .onChange(of: sidebarSelection) { _, new in
                storedSidebarKey = serializeSelection(new)
            }
            .onChange(of: sortOption) { _, new in
                storedSortOption = new.rawValue
            }
            .onDeleteCommand(perform: handleDelete)
            .focusable()
            .onKeyPress(.leftArrow) {
                if canPrev { goPrev() }
                return .handled
            }
            .onKeyPress(.rightArrow) {
                if canNext { goNext() }
                return .handled
            }
            .onKeyPress(.escape) {
                if !selectedIDs.isEmpty {
                    selectedIDs = []
                    return .handled
                }
                return .ignored
            }
            .onKeyPress("a", phases: .down) { press in
                if press.modifiers.contains(EventModifiers.command) {
                    selectedIDs = Set(visiblePhotos.map { $0.id })
                    return .handled
                }
                return .ignored
            }
            // 快捷键：⌘+1-6 切换侧边栏
            .contentKeyboardShortcuts(
                sidebarSelection: $sidebarSelection,
                onImport: startImport,
                onNewFolder: { showingNewFolderAlert = true },
                onResetFilters: resetFilters,
                onToggleFavorite: toggleFavorite,
                onCopy: copyToPasteboard,
                onToggleSortDirection: toggleSortDirection,
                onToggleSidebar: { showSidebar.toggle() },
                onUndo: undoManager.undo,
                onRedo: undoManager.redo,
                // V3.6.23: ⌘F 聚焦搜索框（通过 notification 桥接，避免 ContentView body 改动）
                onFocusSearch: {
                    NotificationCenter.default.post(name: .focusSearchField, object: nil)
                }
            )
            .confirmationDialog(
                "确定要删除 \(selectedIDs.count) 张图片吗？",
                isPresented: $showingBatchDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { batchDelete() }
                Button("取消", role: .cancel) {}
            } message: {
                // V3.6 改：删除走回收站，N 天后才永久清除
                Text("选中的图片会移到「最近删除」，\(retentionDays) 天后自动永久清除。可在「最近删除」中恢复。")
            }
            // ⌘N 新建文件夹
            .alert("新建文件夹", isPresented: $showingNewFolderAlert) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) { newFolderName = "" }
                Button("创建") {
                    createFolderFromAlert()
                    newFolderName = ""
                }
            } message: {
                Text("为新文件夹命名")
            }
            // V3.5.18：监听"设置..."菜单 + 弹设置 sheet + 应用强调色
            // 抽到 helper 函数里避免 body 链过长触发 Swift 类型检查超时
            .applySettingsChrome(
                onOpenSettings: { showSettings = true },
                showSettings: $showSettings,
                tintColor: accentColor.color
            )
            // V3.6.6: 清空回收站二次确认
            .confirmationDialog(
                "确定要清空回收站吗？",
                isPresented: $showingEmptyTrashConfirm,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive) { emptyTrash() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("回收站里的所有照片将被永久删除，无法恢复。")
            }
            // V3.6.24: 导入时重复检测 dialog
            .confirmationDialog(
                duplicateDialogTitle,
                isPresented: Binding(
                    get: { importDuplicateCheck != nil },
                    set: { if !$0 { importDuplicateCheck = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("全部跳过（保留现有）") { confirmSkipDuplicates() }
                Button("全部导入（可能重复）", role: .destructive) { confirmImportAllDuplicates() }
                Button("取消", role: .cancel) { cancelDuplicateImport() }
            } message: {
                Text("选\"跳过\"避免重复导入。")
            }
    }

    // ⌘N 触发的创建文件夹
    private func createFolderFromAlert() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = Folder(name: trimmed)
        modelContext.insert(folder)
        try? modelContext.save()
        sidebarSelection = .folder(folder)
    }

    // 隐藏的快捷键按钮（.background 注入，不可见但响应快捷键）
    // 切换当前排序方向（在同字段的 asc/desc 之间切换）
    private func toggleSortDirection() {
        sortOption = sortOption.toggledDirection
    }

    // V3.5 Phase 1 Step 3：分享选中的照片
    // 使用 macOS 系统分享面板（NSSharingServicePicker）
    // 可选：AirDrop / 信息 / 邮件 / 备忘录 / 第三方 App 等
    private func shareSelected() {
        let urls: [URL]
        if !selectedIDs.isEmpty {
            urls = visiblePhotos
                .filter { selectedIDs.contains($0.id) }
                .map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            urls = [photo.fileURL]
        } else {
            return  // 没有选中
        }

        let picker = NSSharingServicePicker(items: urls)
        let view = NSApp.keyWindow?.contentView ?? NSView()
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    // 复制到剪贴板（支持多选）
    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // 收集所有要复制的文件 URL
        let urls: [URL]
        if !selectedIDs.isEmpty {
            // 多选：复制所有选中
            urls = visiblePhotos
                .filter { selectedIDs.contains($0.id) }
                .map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            // 单选：复制单张
            urls = [photo.fileURL]
        } else {
            return  // 没有选中
        }

        // 写入剪贴板
        pasteboard.writeObjects(urls as [NSURL])
        showToast(urls.count == 1 ? "已复制 1 张图片" : "已复制 \(urls.count) 张图片", type: .success)
    }

    // 进入沉浸式查看（双击图片触发）
    private func enterImmersive(_ photo: Photo) {
        if let idx = visiblePhotos.firstIndex(where: { $0.id == photo.id }) {
            immersiveIndex = idx
            immersivePhoto = photo
        }
    }

    // 清除所有筛选
    private func resetFilters() {
        sidebarSelection = .all
        searchText = ""
    }

    // 收藏切换（单选切换；多选批量反向）
    private func toggleFavorite() {
        if let photo = singleSelectedPhoto {
            photo.isFavorite.toggle()
            try? modelContext.save()
        } else if !selectedIDs.isEmpty {
            let targetPhotos = visiblePhotos.filter { selectedIDs.contains($0.id) }
            let allFavorited = targetPhotos.allSatisfy { $0.isFavorite }
            for photo in targetPhotos {
                photo.isFavorite = !allFavorited
            }
            try? modelContext.save()
        }
    }

    // 主布局（V3.5.17：拆到 Views/MainLayoutView.swift）
    private var mainLayout: some View {
        MainLayoutView(
            toolbar: {
                ToolbarView(
                    searchText: $searchText,
                    onImport: startImport,
                    // V3.6.13: viewMode 通过 computed property 包装，构造 Binding 传给 ToolbarView
                    viewMode: Binding(
                        get: { self.viewMode },
                        set: { self.viewMode = $0 }
                    ),
                    thumbnailSize: $thumbnailSize,
                    sortOption: $sortOption,
                    // V3.5.15：侧栏显隐按钮已移至 title bar（ToolbarItem .navigation）
                    onShare: shareSelected,            // V3.5 Phase 1 Step 3
                    hasSelection: !selectedIDs.isEmpty || singleSelectedPhoto != nil,
                    onUndo: undoManager.undo,         // V3.5 Phase 1 Step 4
                    onRedo: undoManager.redo,
                    canUndo: undoManager.canUndo,
                    canRedo: undoManager.canRedo
                )
            },
            pathBar: {
                // V3.5.17：PathBar 已禁用（用户偏好）
                // 保留 MainLayoutView 接口；空 @ViewBuilder 闭包 = EmptyView = 不占空间
                // 如要恢复：取消下面注释即可
                //
                // if !pathSegments.isEmpty {
                //     PathBar(
                //         segments: pathSegments,
                //         onNavigate: { target in
                //             if let target = target {
                //                 sidebarSelection = target
                //             }
                //         }
                //     )
                // }
            },
            split: {
                MainSplitView(
                    layout: columnLayout,
                    showSidebar: $showSidebar,
                    showDetail: $showDetail,
                    isDropTargeted: $isDropTargeted,
                    isBoxSelecting: $isBoxSelecting,
                    onDrop: handleDrop,
                    sidebar: {
                        SidebarView(
                            selection: $sidebarSelection,
                            selectedIDs: $selectedIDs
                            // V3.5.15：搜索移到工具栏（侧栏无搜索）
                        )
                    },
                    center: {
                        PhotoGridPane(
                            selectedPhoto: $selectedPhoto,
                            selectedIDs: $selectedIDs,
                            lastSelectedID: $lastSelectedID,
                            folder: currentFolder,
                            tag: currentTag,
                            searchText: searchText,
                            filterFavorites: filterFavorites,
                            filterUnfiled: filterUnfiled,
                            filterDuplicates: filterDuplicates,
                            filterRecent7Days: filterRecent7Days,
                            filterLargeFiles: filterLargeFiles,
                            filterInTrash: filterInTrash,  // V3.6 NEW
                            // V3.6.6: 透传 retentionDays 给缩略图 badge
                            retentionDays: retentionDays,
                            thumbnailSize: thumbnailSize,
                            sortOption: sortOption,
                            onVisiblePhotosChange: { visiblePhotos = $0 },
                            onImport: startImport,
                            onBatchDelete: { showingBatchDeleteConfirm = true },
                            onClearMultiSelect: { selectedIDs = [] },
                            onDoubleTap: enterImmersive,
                            onExportComplete: { count in
                                showToast("已导出 \(count) 张图片", type: .success)
                            }
                        )
                    },
                    detail: {
                        DetailPane(
                            singleSelectedPhoto: singleSelectedPhoto,
                            isMultiSelect: isMultiSelect,
                            count: filterInTrash ? trashedCount : (filterInDuplicates ? duplicatePurgeableCount : selectedIDs.count),
                            totalSize: filterInTrash ? trashedTotalSize : (filterInDuplicates ? duplicatePurgeableSize : selectedTotalSize),
                            folders: folders,
                            allTags: allTags,
                            onDelete: deleteSinglePhoto,
                            onPrev: goPrev,
                            onNext: goNext,
                            canPrev: canPrev,
                            canNext: canNext,
                            currentIndex: currentIndex,
                            totalCount: visiblePhotos.count,
                            // V3.5.19：多选 batch 动作从原 PhotoGridView.multiSelectTopBar 搬过来
                            onBatchMove: { folder in batchMove(to: folder) },
                            onBatchAddTag: { tag in batchAddTag(tag) },
                            onBatchToggleFavorite: batchToggleFavorite,
                            onBatchExport: batchExport,
                            onBatchDelete: { showingBatchDeleteConfirm = true },
                            onClearSelection: { selectedIDs = []; selectedPhoto = nil },
                            // V3.6 NEW: 回收站模式
                            sidebarSelection: sidebarSelection,
                            retentionDays: retentionDays,
                            onTrashRestore: restoreSelectedFromTrash,
                            onTrashPermanentDelete: permanentDeleteSelected,
                            // V3.6.6: 改弹二次确认（不再直接调 emptyTrash）
                            onEmptyTrash: { showingEmptyTrashConfirm = true },
                            // V3.6.15: 重复图清理（一键保留每组最新）
                            onKeepNewestPerDuplicateGroup: keepNewestPerDuplicateGroup
                        )
                    }
                )
                .boxSelectionGesture(
                    isBoxSelecting: $isBoxSelecting,
                    selectedIDs: $selectedIDs,
                    lastSelectedID: $lastSelectedID,
                    visiblePhotos: visiblePhotos
                )
                // V3.6.32: 恢复到 V3.6.27 顶层加 .boxSelectionGesture 模式
                // 之前 R2 改到 PhotoGridView 内部，simultaneousGesture 仍破坏 cell .onDrag
                // 现在先恢复 V1（最安全），box-select V2 留待未来换实现思路
            },
            statusBar: {
                // V3.5.6 Finder 化：Status Bar（底部信息条）
                StatusBar(
                    totalCount: allPhotos.count,
                    totalSize: totalSizeFormatted,
                    selectedCount: selectedIDs.count
                )
            },
            showSidebar: $showSidebar,
            undoManager: undoManager,
            toast: toast,
            immersivePhoto: $immersivePhoto,
            immersiveIndex: $immersiveIndex,
            visiblePhotos: visiblePhotos,
            onImmersiveDismiss: { immersivePhoto = nil }
        )
    }

    // 显示 Toast（自动消失）
    private func showToast(_ message: String, type: ToastView.ToastType = .info) {
        toastTask?.cancel()
        toast = ToastInfo(message: message, type: type)
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    self.toast = nil
                }
            }
        }
    }


    // 处理 Delete 键
    private func handleDelete() {
        if !selectedIDs.isEmpty {
            showingBatchDeleteConfirm = true
        } else if singleSelectedPhoto != nil {
            deleteSinglePhoto()
        }
    }

    // ─── 上一张 / 下一张 ───
    private func goPrev() {
        guard canPrev,
              let id = singleSelectedPhoto?.id ?? selectedIDs.first,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        let newID = visiblePhotos[idx - 1].id
        selectedIDs = [newID]
        lastSelectedID = newID
    }

    private func goNext() {
        guard canNext,
              let id = singleSelectedPhoto?.id ?? selectedIDs.first,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx < visiblePhotos.count - 1 else { return }
        let newID = visiblePhotos[idx + 1].id
        selectedIDs = [newID]
        lastSelectedID = newID
    }

    // ─── 启动时清理过期回收站项（V3.6 NEW）───
    private func purgeExpiredTrashOnStartup() {
        let days = TrashRetentionDays(rawValue: retentionDays) ?? .defaultValue
        let service = RecycleBinService(storage: .shared, modelContext: modelContext)
        service.purgeExpired(retentionDays: days.rawValue)
    }

    // ─── 启动导入 ───
    private func startImport() {
        let panel = NSOpenPanel()
        panel.title = "选择图片或文件夹"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else { return }

        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)

        let importer = ImageImporter(
            modelContext: modelContext,
            folder: currentFolder
        ) { current, total in
            Task { @MainActor in
                importProgress = ImportProgress(current: current, total: total, isImporting: true)
                if current >= total && total > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let p = importProgress, p.current >= p.total {
                        importProgress = nil
                    }
                }
            }
        }
        // V3.6.24: 导入前重复检测（fileHash 重复弹 dialog 让用户选跳过/副本）
        runImportWithDuplicateCheck(urls: panel.urls)
    }

    /// V3.6.24: 扫现有 photo + 算新 url fileHash，弹 dialog 让用户选
    /// V3.6.27: 改用 async 版本（后台 actor 算 SHA256，不阻塞 main thread）
    private func runImportWithDuplicateCheck(urls: [URL]) {
        Task { @MainActor in
            let check = await ImageImporter.checkDuplicatesAsync(
                newURLs: urls,
                in: modelContext
            ) { current, total in
                // V3.6.27: 进度反馈（"检测重复中... 5/12"）
                importProgress = ImportProgress(current: current, total: total, isImporting: true)
            }
            // 算完后清进度
            importProgress = nil
            if check.hasDuplicates {
                pendingImportURLs = urls
                importDuplicateCheck = check
            } else {
                importPhotos(urls: urls)
            }
        }
    }

    // V3.6.24: 重复检测 dialog 的动态 title（避免 body message: 闭包触发 type-check）
    private var duplicateDialogTitle: String {
        guard let check = importDuplicateCheck else { return "检测到重复文件" }
        return "发现 \(check.existing.count) 张已存在 / \(check.newCount) 张新文件"
    }

    private func confirmSkipDuplicates() {
        let existing = Set(importDuplicateCheck?.existing ?? [])
        let newURLs = pendingImportURLs.filter { !existing.contains($0) }
        importDuplicateCheck = nil
        pendingImportURLs = []
        if !newURLs.isEmpty { importPhotos(urls: newURLs) }
    }

    private func confirmImportAllDuplicates() {
        let allURLs = pendingImportURLs
        importDuplicateCheck = nil
        pendingImportURLs = []
        importPhotos(urls: allURLs)
    }

    private func cancelDuplicateImport() {
        importDuplicateCheck = nil
        pendingImportURLs = []
    }

    /// V3.6.24: 实际跑导入（dialog 确认后调用，或无重复时直接调）
    private func importPhotos(urls: [URL]) {
        importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
        let importer = ImageImporter(modelContext: modelContext, folder: currentFolder) { current, total in
            Task { @MainActor in
                importProgress = ImportProgress(current: current, total: total, isImporting: true)
                if current >= total && total > 0 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let p = importProgress, p.current >= p.total {
                        importProgress = nil
                    }
                }
            }
        }
        importer.importURLs(urls)
    }

    // ─── 拖拽导入 ───
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                defer { group.leave() }
                guard let data = data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            // V3.6.24: 拖拽导入也走重复检测
            runImportWithDuplicateCheck(urls: urls)
        }

        return true
    }

    // ─── 删除单张（V3.6：走 RecycleBinService，不再调 undoManager）───
    private func deleteSinglePhoto() {
        guard let photo = singleSelectedPhoto else { return }
        // V3.6：删除 = 移到回收站（软删），文件保留在 Photos/ 原位
        RecycleBinService(storage: .shared, modelContext: modelContext).recycle(photo)
        // 清选择（与旧行为一致）
        selectedIDs = []
        selectedPhoto = nil
        showToast("已移到「最近删除」（\(retentionDays) 天后永久删除）", type: .info)
    }

    // ─── 批量删除（V3.6：走 RecycleBinService，不再调 undoManager）───
    private func batchDelete() {
        performOnSelectedTrash(
            { svc, photos in photos.forEach { svc.recycle($0) } },
            message: { "已移到「最近删除」 \($0) 张" }
        )
    }

    // V3.5.19：从 PhotoGridView 搬上来的 4 个 batch 方法
    // 原因：multi-select 顶部栏被移到详情面板里，详情面板的 MultiSelectDetailView
    // 需要直接调用这些方法。

    // ─── 批量移动到文件夹 ───
    private func batchMove(to folder: Folder?) {
        let photosToMove = visiblePhotos.filter { selectedIDs.contains($0.id) }
        guard !photosToMove.isEmpty else { return }

        // 快照：移动前的 folder 列表
        let oldFolders = photosToMove.map { $0.folder }
        let count = photosToMove.count
        let folderName = folder?.name ?? "待整理"

        undoManager.registerAction(
            description: "移动 \(count) 张照片到 \(folderName)"
        ) {
            for photo in photosToMove {
                photo.folder = folder
            }
            try? modelContext.save()
            // 移动后清空多选
            selectedIDs = []
            selectedPhoto = nil
        } undo: {
            for (photo, oldFolder) in zip(photosToMove, oldFolders) {
                photo.folder = oldFolder
            }
            try? modelContext.save()
        }
    }

    // ─── 批量加标签 ───
    private func batchAddTag(_ tag: Tag) {
        let photosToTag = visiblePhotos.filter { selectedIDs.contains($0.id) }
        for photo in photosToTag {
            if !photo.tags.contains(where: { $0.id == tag.id }) {
                photo.tags.append(tag)
            }
        }
        try? modelContext.save()
        // 加标签后保留多选（用户可能想加多个标签）
    }

    // ─── 批量导出 ───
    private func batchExport() {
        let photosToExport = visiblePhotos.filter { selectedIDs.contains($0.id) }
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
                print("❌ 导出失败: \(photo.filename) - \(error)")
            }
        }
        showToast("已导出 \(successCount) 张图片", type: .success)
    }

    /// 避免导出时文件名冲突
    private func uniqueDestinationForBatchExport(for url: URL) -> URL {
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

    // ─── 批量收藏切换 ───
    private func batchToggleFavorite() {
        let photosToToggle = visiblePhotos.filter { selectedIDs.contains($0.id) }
        guard !photosToToggle.isEmpty else { return }
        // 全部已收藏 → 全部取消；否则 → 全部收藏
        let allFavorited = photosToToggle.allSatisfy { $0.isFavorite }
        for photo in photosToToggle {
            photo.isFavorite = !allFavorited
        }
        try? modelContext.save()
    }

    // ─── 回收站操作（V3.6 NEW）───

    /// 在 visiblePhotos ∩ selectedIDs 上执行 trash 操作（3 个 batch 方法的共用骨架）
    /// - Parameters:
    ///   - operation: 实际的 SwiftData 变更（recycle / restore / purge）
    ///   - message: toast 消息生成器（接收处理数量）
    ///   - type: toast 类型（默认 .info；恢复用 .success）
    private func performOnSelectedTrash(
        _ operation: (RecycleBinService, [Photo]) -> Void,
        message: (Int) -> String,
        type: ToastView.ToastType = .info
    ) {
        let photos = visiblePhotos.filter { selectedIDs.contains($0.id) }
        guard !photos.isEmpty else { return }
        let service = RecycleBinService(storage: .shared, modelContext: modelContext)
        operation(service, photos)
        let count = photos.count
        selectedIDs = []
        selectedPhoto = nil
        showToast(message(count), type: type)
    }

    /// 恢复选中的照片（从回收站 → 图库）
    private func restoreSelectedFromTrash() {
        performOnSelectedTrash(
            { svc, photos in photos.forEach { svc.restore($0) } },
            message: { "已恢复 \($0) 张图片" },
            type: .success
        )
    }

    /// 永久删除选中的照片（文件 + SwiftData）
    private func permanentDeleteSelected() {
        performOnSelectedTrash(
            { svc, photos in svc.purgeAll(photos) },
            message: { "已永久删除 \($0) 张图片" }
        )
    }

    /// 清空回收站（永久删除所有 trashed 项；不走 selectedIDs）
    private func emptyTrash() {
        let trashed = allPhotos.filter { $0.isInTrash }
        guard !trashed.isEmpty else { return }
        RecycleBinService(storage: .shared, modelContext: modelContext).purgeAll(trashed)
        let count = trashed.count
        selectedIDs = []
        selectedPhoto = nil
        showToast("已清空回收站（\(count) 张）", type: .info)
    }

    /// V3.6.15 NEW: 重复图清理 — 每组保留 importedAt 最新的，其他移到回收站
    private func keepNewestPerDuplicateGroup() {
        // 找所有可见图（应用当前 filter 后的子集）里可清理的
        let visible = visiblePhotos.filter { !$0.isInTrash }
        let purgeable = PhotoStats.duplicatesToPurge(in: visible)
        guard !purgeable.isEmpty else { return }
        let service = RecycleBinService(storage: .shared, modelContext: modelContext)
        for photo in purgeable { service.recycle(photo) }
        showToast("已移到「最近删除」 \(purgeable.count) 张重复图", type: .info)
    }

    // ─── 序列化 SidebarSelection ───
    private func serializeSelection(_ selection: SidebarSelection?) -> String {
        guard let selection = selection else { return "all" }
        switch selection {
        case .all: return "all"
        case .favorites: return "favorites"
        case .unfiled: return "unfiled"
        case .duplicates: return "duplicates"
        case .recent7Days: return "recent7Days"
        case .largeFiles: return "largeFiles"
        case .folder(let f): return "folder:\(f.id.uuidString)"
        case .tag(let t): return "tag:\(t.id.uuidString)"
        case .recentlyDeleted: return "recentlyDeleted"  // V3.6 NEW
        }
    }

    // ─── 恢复 SidebarSelection ───
    private func restoreSelection(_ key: String) -> SidebarSelection? {
        switch key {
        case "all": return .all
        case "favorites": return .favorites
        case "unfiled": return .unfiled
        case "duplicates": return .duplicates
        case "recent7Days": return .recent7Days
        case "largeFiles": return .largeFiles
        case "recentlyDeleted": return .recentlyDeleted  // V3.6 NEW
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
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}

// MARK: - V3.5.18：设置面板 chrome helper
//
// 抽出 4 个 modifier 到独立 generic extension，避免 body 链超长触发
// Swift 编译器的 "unable to type-check this expression in reasonable time" 错误。
// 同样模式可复用：任何"挂在已有视图链尾端"的 modifier 都能用此技巧。
extension View {
    func applySettingsChrome(
        onOpenSettings: @escaping () -> Void,
        showSettings: Binding<Bool>,
        tintColor: Color
    ) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            onOpenSettings()
        }
        .sheet(isPresented: showSettings) {
            SettingsView()
        }
        .tint(tintColor)
        .environment(\.appAccent, tintColor)
    }
}
