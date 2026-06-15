//
//  ContentViewModel.swift
//  ImageGallery
//
//  V5.52 NEW: ContentView 的 @Observable 业务模型
//  把 ContentView 的 21 个 @State + 12 个 @AppStorage + 30+ computed + 41 methods + configureNSToolbar 全部抽到这里
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
//    - V5.52-3: 22 个 business @State (本文件) ← 当前
//    - V5.52-4: 30+ computed
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
    /// V5.52-2: 12 keys UserDefaults 镜像 (改名 UserSettings 避免和 SwiftUI Settings scene 撞名)
    var settings = UserSettings()

    /// V5.52-3: modelContext 由 .task 注入 (init 时还没有, 延迟到 view 出现后)
    /// V5.52-5 之后 funcs 通过 self.modelContext! 访问
    /// @ObservationIgnored 避免被追踪
    @ObservationIgnored var modelContext: ModelContext? = nil

    // MARK: - V5.52-3: 22 个 business @State 搬到 model

    /// 选中态 (V3.6.52 合并 selectedPhoto/selectedIDs/lastSelectedID 为 SelectionState)
    var selection = SelectionState()

    /// 侧栏选中项 (.all / .folder / .tag / .recent7Days / ...)
    var sidebarSelection: SidebarSelection? = .all

    /// 4 维 filter popover (folders/tags/shapes/minRating)
    var filterState = FilterState()

    /// 工具栏搜索框文本 (NSSearchField 双向同步)
    var searchText = ""

    /// 当前 session 缩略图大小 (V5.16: 170→200)
    ///   跟 settings.thumbnailSize 区别: 这是 live, 那个是持久化 default
    var thumbnailSize: CGFloat = 200

    /// 排序方式 (V5.31: importedAtDesc → filenameAsc)
    var sortOption: SortOption = .filenameAsc

    /// 批量删除 / 清空回收站 / 重复检测 dialog state
    var showingBatchDeleteConfirm = false
    var showingEmptyTrashConfirm = false
    var importDuplicateCheck: ImageImporter.DuplicateCheckResult? = nil
    var pendingImportURLs: [URL] = []

    /// ⌘N 新建文件夹 alert
    var showingNewFolderAlert = false
    var newFolderName = ""

    /// 沉浸式大图状态 (Photos.app 风格全屏查看)
    var immersivePhoto: Photo? = nil
    var immersiveIndex: Int = 0

    /// V4.11.0 磁盘写入错误 (PhotoStorage.verifyStorage 失败)
    var storageErrorMessage: String? = nil

    /// V5.42-2 砍: titlebar ⓘ 按钮 NSObject 引用 (V5.22 引入)
    ///   Body .onChange(of: showDetail) 同步状态
    var titlebarAccessory: TitlebarAccessoryController? = nil

    /// V5.13 toast 队列 + 自动 dismiss task
    var toastQueue: [ToastInfo] = []
    var toastTask: Task<Void, Never>? = nil

    /// V3.5 Phase 1 Step 4 撤销/重做
    var undoManager = ImageGalleryUndoManager()

    /// 侧栏 / 详情列宽 + drag 起始宽度
    ///   跟 settings.sidebarColumnWidth / settings.detailColumnWidth 区别:
    ///   实时拖拽中改的是这些, drag end 才写回 settings 持久化
    var sidebarColumnWidth: CGFloat = 220
    var detailColumnWidth: CGFloat = 360
    var sidebarDragStartWidth: CGFloat = 220
    var detailDragStartWidth: CGFloat = 360

    /// V5.52-1 起步: 无参 init——modelContext 由 .task 注入
    init() {}
}
