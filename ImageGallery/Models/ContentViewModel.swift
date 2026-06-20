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
    /// V6.28.1: importProgress 迁 ImportViewModel.importProgress
    /// V6.28.2: titlebarAccessory 迁 WindowViewModel.titlebarAccessory
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

    // MARK: - V6.28.1: Import 子模型

    /// V6.28.1: Import 业务 — 启动 / 拖入 / 重复检测 / 批量导入 / 进度
    ///   caller 走 model.importVM.startImport() / model.importVM.importProgress 等
    let importVM: ImportViewModel

    // MARK: - V6.28.2: Window 子模型

    /// V6.28.2: Window 业务 — NSToolbar 配置 + Titlebar accessory + windowDidBecomeKey
    ///   caller 走 model.windowVM.configureToolbar(window:) / model.windowVM.titlebarAccessory
    let windowVM: WindowViewModel

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

    // MARK: - V6.28.2: configureToolbar + titlebarAccessory 迁 WindowViewModel

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

    // MARK: - V6.28.1: 导入业务 (startImport/handleDropImport/importPhotos) 迁 ImportViewModel

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
    /// V6.28.1: 创建 ImportViewModel + 设 weak core back-ref + wire toast callback
    /// V6.28.2: 创建 WindowViewModel (共享 settings) + 设 weak core back-ref
    init(settings: UserSettings? = nil) {
        let s = settings ?? UserSettings()
        let um = ImageGalleryUndoManager()
        self.settings = s
        self.undoManager = um
        // GridViewModel 共享 settings + undoManager (同实例)——用本地 um 而非 self.undoManager
        // 避免 init order trap (self.grid 赋值时 self 未完整初始化)
        self.grid = GridViewModel(settings: s, undoManager: um)
        // V6.28.1: ImportViewModel — 单独 init, 后 wire (同 GridViewModel pattern)
        self.importVM = ImportViewModel()
        // V6.28.2: WindowViewModel — 共享 settings, 后 wire
        self.windowVM = WindowViewModel(settings: s)
        // weak back-ref (避免 retain cycle — ContentViewModel 持 grid/importVM/windowVM strong, 它们持 core weak)
        self.grid.core = self
        self.importVM.core = self
        self.windowVM.core = self
        // wire toast callback (子模型的 toast 走 Core 的 enqueueToast)
        self.grid.enqueueToastHandler = { [weak self] message, type, duration in
            self?.enqueueToast(message, type: type, duration: duration)
        }
        self.importVM.enqueueToastHandler = { [weak self] message, type, duration in
            self?.enqueueToast(message, type: type, duration: duration)
        }
    }
}
