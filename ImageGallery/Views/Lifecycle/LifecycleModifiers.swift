//
//  LifecycleModifiers.swift
//  ImageGallery
//
//  V6.100: 从 ContentView+Lifecycle.swift 抽出 lifecycle 5 sub-modifier (第 1 个)
//    原因: contentBodyModifiers 250 行 / 53 参数已经踩过 type-check timeout (V6.97 P2-3 教训)
//    拆 5 sub-modifier 跟 V6.97.2 ShortcutsHandler 模式一致:
//      - LifecycleModifiers (本文件): appLifecycleHooks + .task + 4 .onChange
//      - KeyboardModifiers: gridInputHandling + contentKeyboardShortcuts
//      - DialogModifiers: batchActionDialogs + applySettingsChrome + exposeUndoManager
//      - SheetModifiers: batchRenameSheet + shareSheet + markupSheet + cropSheet + smartFolderSheets
//      - NotificationModifiers: 12 个 .onReceive + shortcutsHandler
//
//  Lifecycle modifiers 负责 app 启动一次性 hook + state 同步:
//   - appLifecycleHooks: .onAppear (restore selection / purge trash / check storage)
//   - .task: 启动 warmupRecentThumbnails + uitest auto import
//   - 4 .onChange: 推 @Query 缓存到 model.grid (V6.28 refactor 后模式)
//
//  抽出来后 ContentView body chain 13 modifier → 8 modifier (减 5 链)
//  编译推断秒过 (V5.59-2 同样的 type-check 解决模式)
//

import SwiftUI
import SwiftData

extension View {
    /// V6.100: Lifecycle modifiers — app 启动 .onAppear + .task + 4 .onChange 推 @Query cache
    ///   从 ContentView+Lifecycle.contentBodyModifiers 抽 (line 105-301, 200 行)
    ///   拆出后 ContentView body chain 13 → 8 modifier
    @MainActor
    func lifecycleModifiers(
        model: ContentViewModel,
        modelContext: ModelContext,
        allPhotos: [Photo],
        folders: [Folder],
        allTags: [Tag],
        smartFolders: [SmartFolder],
        sidebarSelection: SidebarSelection?,
        sortOption: SortOption,
        viewModeRaw: String,
        hasPurgedExpiredTrash: Binding<Bool>,
        onRestoreSelection: @escaping () -> Void,
        onPurgeExpiredTrashOnStartup: @escaping () -> Void,
        onCheckStorage: @escaping () -> Void,
        onMigrateFavoriteToRating: @escaping () -> Void,
        onSerializeSidebarSelection: @escaping (SidebarSelection?) -> String,
        onClearSelectionOnFilterChange: @escaping () -> Void,
        onSelectionEscape: @escaping () -> Void,
        filterState: FilterState,
        selection: SelectionState
    ) -> some View {
        self
            .appLifecycleHooks(
                thumbnailSize: model.grid.thumbnailSize,
                sidebarSelection: sidebarSelection,
                sortOption: sortOption,
                viewModeRaw: viewModeRaw,
                onAppear: {
                    onRestoreSelection()
                    if !hasPurgedExpiredTrash.wrappedValue {
                        hasPurgedExpiredTrash.wrappedValue = true
                        onPurgeExpiredTrashOnStartup()
                    }
                    onCheckStorage()
                    onMigrateFavoriteToRating()
                },
                onSidebarSelectionChange: { new in
                    _ = onSerializeSidebarSelection(new)
                    onClearSelectionOnFilterChange()
                }
            )
            // V6.22.0 (P2 #12): Thumbnail warmup + V6.22.11 (XCUITest): launch arg auto-import
            .task {
                model.modelContext = modelContext
                // V6.28: @Query cache 推 model.grid
                model.grid.allPhotos = allPhotos
                model.grid.folders = folders
                model.grid.allTags = allTags
                await Self.warmupRecentThumbnails(context: modelContext, count: 50)
                // V6.22.11: launch arg auto-trigger
                let args = ProcessInfo.processInfo.arguments
                guard let idx = args.firstIndex(of: "-uitest-import-dir"),
                      idx + 1 < args.count else { return }
                let dir = args[idx + 1]
                let dirURL = URL(fileURLWithPath: dir)
                let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp"]
                guard let contents = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { return }
                let urls = contents.filter { imageExts.contains($0.pathExtension.lowercased()) }
                guard !urls.isEmpty else { return }
                // V6.97.5: importPhotos async, .task 已 async 加 await
                model.importVM.importProgress = ImportProgress(current: 0, total: 0, isImporting: true)
                await model.importVM.importPhotos(urls: urls)
            }
            // V6.28: .onChange 推 model.grid
            .onChange(of: allPhotos) { _, new in model.grid.allPhotos = new }
            .onChange(of: folders) { _, new in model.grid.folders = new }
            .onChange(of: allTags) { _, new in model.grid.allTags = new }
            // P4.1.1: smartFolders 推 model.grid.smartFoldersCache (createSmartFolder 用 max+1 算 order)
            .onChange(of: smartFolders) { _, new in model.grid.smartFoldersCache = new }
            // V6.74.2: 删 .onChange(of: showDetail) sync — SwiftUI .toolbar .primaryAction 自动 re-render ⓘ icon
            // V5.62-2: filterState 变化推送, child popover update (现在 SwiftUI 直接读 binding)
            .onChange(of: filterState) { _, _ in
                if !selection.isEmpty {
                    onSelectionEscape()
                }
            }
    }

    /// V6.22.0 (P2 #12): 拉最近 N 张 photo URLs, 触发 ImageLoader.warmupThumbnails 预热
    ///   .background priority 不抢主线程 (用户感知启动快)
    ///   V6.100: 从 ContentView+Lifecycle.warmupRecentThumbnails 搬过来 (private static)
    @MainActor
    static func warmupRecentThumbnails(context: ModelContext?, count: Int) async {
        guard let context else { return }
        let descriptor = FetchDescriptor<Photo>(
            sortBy: [SortDescriptor(\Photo.importedAt, order: .reverse)]
        )
        var fetch = descriptor
        fetch.fetchLimit = count
        let photos = (try? context.fetch(fetch)) ?? []
        let urls = photos.map { $0.fileURL }
        guard !urls.isEmpty else { return }
        await Task(priority: .background) {
            await ImageLoader.warmupThumbnails(urls: urls, maxPixelSize: 200)
        }.value
    }
}