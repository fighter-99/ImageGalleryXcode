//
//  SidebarView.swift
//  ImageGallery
//
//  左侧导航栏。V3.5.8 精修：Photos.app + Finder 混合风格。
//
//  改动（V3.5.8 侧栏精修）：
//  - 自定义 row 样式：hover 浅背景 + 选中 accent 圆角
//  - section header：粗体 + secondary 色 + 大写感
//  - item 计数：caption + tertiary 色
//  - 隐藏 List 默认分隔线（更干净）
//  - 隐藏 List 默认背景（用 Surface 统一）
//
//  保留：
//  - List 原生 selection 管理（@Binding）
//  - List 原生 drag & drop（onDrop）
//  - List 原生 keyboard nav（⌘1-9）
//  - List 原生 context menu
//
//  V3.6.52: 重构选中状态——`@Binding var selectedIDs: Set<UUID>` 改为
//  `@Binding var selection: SelectionState`，与 ContentView 单一真相源对齐
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    // SwiftData 查询
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]
    @Query(sort: \Tag.createdAt, order: .forward) private var tags: [Tag]
    // P4.1: 用户自定义智能文件夹 — order 升序
    //   @Query 不支持 SortDescriptor 数组, 用单一 sort key, 同 order 时 SwiftData 自然 order
    @Query(sort: \SmartFolder.order, order: .forward) private var smartFolders: [SmartFolder]
    @Query private var allPhotos: [Photo]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext

    // V6.10: 拖到 folder 注册 undo (跟 batchMove 模式一致)
    //   nil = 不注册 (测试 seam + 早期 init 容错 + Preview 兼容)
    //   V6.10.1: 去掉 = nil 默认值——显式 init 里必须初始化, 不然 immutable 双初始化
    let undoManager: ImageGalleryUndoManager?

    // V6.10: 显式 init——synthesized memberwise init 在 @Query / @Environment 存在时
    //   行为不一致, 不接受 `undoManager` 参数。显式列出 4 个 @Binding + undoManager
    //   P4.1.1: 加 `model` 参数 (智能文件夹创建 sheet 触发需要)
    init(
        selection: Binding<SidebarSelection?>,
        photoSelection: Binding<SelectionState>,
        thumbnailSize: Binding<CGFloat>,
        sortOption: Binding<SortOption>,
        model: ContentViewModel,
        undoManager: ImageGalleryUndoManager? = nil
    ) {
        self._selection = selection
        self._photoSelection = photoSelection
        self._thumbnailSize = thumbnailSize
        self._sortOption = sortOption
        self.model = model
        self.undoManager = undoManager
    }

    // P4.1.1: 智能文件夹创建入口 — model.pendingSmartFolderFilter / showingNewSmartFolderSheet
    @Bindable var model: ContentViewModel

    // 选中项（双向绑定）
    @Binding var selection: SidebarSelection?

    // V3.6.52: 多选集合 (selectedIDs: Set<UUID>) 合并为 SelectionState 绑定
    //   命名冲突：与上面的 sidebar selection 同名；本 binding 命名改 photoSelection
    @Binding var photoSelection: SelectionState

    // V4.1.0f: showSidebar binding 移除（hide 按钮完全搬回主工具栏）

    // V4.0.0.6: 缩放（搬到侧栏顶部，与主工具栏解耦）
    @Binding var thumbnailSize: CGFloat

    // V4.0.0.6: 排序（搬到侧栏顶部）
    @Binding var sortOption: SortOption

    // V4.36.6: 侧栏 section 折叠状态（绑定到 header 和 content）
    //   旧版 SidebarSectionHeader 用 storageKey 自管 UserDefaults, 但 Section content 永远显示
    //   新版 @AppStorage 在 SidebarView 持有, 共享给 header (chevron) + content (if 包裹)
    //   关键: 同一个 binding 让点击 header 真正控制 content 可见性
    @AppStorage("sidebar.section.library") private var isLibraryExpanded: Bool = true
    @AppStorage("sidebar.section.folders") private var isFoldersExpanded: Bool = true
    @AppStorage("sidebar.section.tags") private var isTagsExpanded: Bool = true

    // 弹窗控制
    // V6.11: newName 拆 newFolderName + newTagName——之前 2 alert 共享 @State
    //   取消后再开旧值会残留, placeholder 不一致
    @State private var showingNewFolderAlert = false
    @State private var showingNewTagAlert = false
    @State private var newFolderName = ""
    @State private var newTagName = ""

    // 拖拽目标高亮
    @State private var dropTargetFolderID: UUID?
    // V3.6.12: 拖到 trash 行的高亮状态
    @State private var isTrashDropTargeted: Bool = false

    // ─── 计算重复图数量 + 各 section 计数 (V6.19.2 P0 #11: 单遍 O(n)) ───
    // 之前 libraryCounts tuple computed 5 遍 O(n) + duplicateCount 2-3 遍 = 7-8 遍
    // 现在 PhotoStatsSnapshot 2 遍 O(n) (1 遍累加 + 1 遍算 duplicate)
    // V6.20.0 (code audit fix #6): 走 ContentViewModel.libraryStats 缓存 (count invalidation)
    //   之前每次 body 重渲重算 — @Query 任何 write 触发整库 2 遍 O(n) 扫描
    //   现在模型层缓存, count 不变复用 cache; count 变触发失效重算
    private var libraryStats: PhotoStatsSnapshot { model.libraryStats }

    var body: some View {
        // V4.1.0f: 侧栏完全"无 UI"——hide 按钮搬回主工具栏
        //   视觉上侧栏直接从 section header 开始（更紧凑）
        // V5.31: .regularMaterial → .bar——更 subtle, 镜像 macOS Photos 风格
        //   - .regularMaterial: 明显雾化, light 模式偏灰白 (V4.1.0d 加)
        //   - .bar: macOS 标准 sidebar 材质, 微妙 vibrancy, light 模式近透明
        //   - Photos.app sidebar 是 .bar 类似质感 (系统 thin material)
        // V4.21.0 撤回历史: 试过 .glassEffect(.regular) 有 outline 痕迹, 不再试
        sidebarContent
            .background(.bar)
    }

    /// V4.1.0f 移除：sidebarTopBar 整个组件删除（hide 按钮回到主工具栏）
    ///   之前 V4.1.0e 留的 sidebarTopBar 已经完全空（只有 Spacer + hide）——彻底删除
    ///   侧栏顶部不再有 30pt 高的"假控制面板"

    /// V3.5.15: 纯导航侧栏，搜索在工具栏（V3.5.14 的侧栏顶部搜索框已移除）
    /// V4.0.0.5: 把原 body 内的 List 抽到独立 var，让 sidebarTopBar + sidebarContent 组装
    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selection) {
            // V4.1.0 重构: 5 段清晰分层（Photos.app 风格）
            //   1. 我的图馆（含智能项 + 智能文件夹）
            //   2. 我的文件夹
            //   3. 标签
            //   4. 最近删除（单独 section，底部独立入口）
            //   5. 存储信息（在 List 外，固定在侧栏底部）

            // ─── Section 1: 我的图馆（智能项 + 智能文件夹合并）───
            Section {
                if isLibraryExpanded {
                    // 4 个 smart items + 2 个 smart filters
                    // V4.6.0: 智能 folder icon 用语义色（SidebarStyle.iconColor* token）——
                    //   一眼区分内容类型（重复/最近/大图/收藏/最近删除）
                    //   色板：色相分散（HLS space 60°+ 间隔），避免混淆
                    // V6.14.3: 5 个智能文件夹 label 入 Copy 字典（之前 hardcoded 中文）
                    //   String(localized:defaultValue:) — 走 xcstrings String Catalog
                    //   跟 Copy.sidebarCount / Copy.toolbarExport 同样模式
                    sidebarRow(icon: "photo.on.rectangle.angled", label: Copy.sidebarAll, count: libraryStats.inLibraryCount, target: .all)
                    // V5.7: 砍 sidebarRow "收藏"——侧边栏只放主导航
                    //   收藏 = 评分 ≥ 5 走筛选 popover（用户在筛选 popover 内点击 ≥5 星即可看收藏）
                    sidebarRow(icon: "tray", label: Copy.sidebarUnfiled, count: libraryStats.unfiledCount, target: .unfiled)
                    if libraryStats.duplicatePhotoCount > 0 {
                        sidebarRow(icon: "doc.on.doc", label: Copy.sidebarDuplicates, count: libraryStats.duplicatePhotoCount, target: .duplicates, iconColor: SidebarStyle.iconColorDuplicate)
                    }
                    // V4.1.0: 智能文件夹移进"我的图馆"section（之前是独立 section）
                    // V4.1.0: 智能文件夹移进"我的图馆"section（之前是独立 section）
                    // V6.13.4: 补 count — 智能文件夹 5/7 item 已有 count, 补最后 2 个
                    // V6.19.2: 全部走 libraryStats (PhotoStatsSnapshot 单遍 O(n) 替 5+ 遍)
                    sidebarRow(icon: "clock.arrow.circlepath", label: Copy.sidebarRecent7Days, count: libraryStats.recent7DaysCount, target: .recent7Days, iconColor: SidebarStyle.iconColorRecent)
                    sidebarRow(icon: "large.circle", label: Copy.sidebarLargeFiles, count: libraryStats.largeFilesCount, target: .largeFiles, iconColor: SidebarStyle.iconColorLarge)
                    // P4.1: 用户自定义 SmartFolder — 跟 built-in 智能项同 section
                    //   按 order 升序, 同 order 按 createdAt
                    //   V1 read-only (创建 UI 留 P4.1.1)
                    ForEach(smartFolders) { sf in
                        smartFolderRow(sf)
                    }
                }
            } header: {
                // V4.1.0: 可见 header（V3.6.25 之前被隐藏）
                // V6.14.3: 4 个 section header label 入 Copy 字典
                SidebarSectionHeader(
                    Copy.sidebarSectionLibrary,
                    icon: "sparkles",
                    isExpanded: $isLibraryExpanded,
                    // P4.1.1: Library section "+" 按钮 — 触发 smart folder 创建 sheet
                    addAction: { onCreateSmartFolder() },
                    addAccessibilityLabel: "新建智能文件夹"
                )
            }

            // ─── Section 2: 我的文件夹 ───
            Section {
                if isFoldersExpanded {
                    ForEach(folders) { folder in
                        folderSidebarRow(folder)
                    }

                    Button {
                        newFolderName = ""
                        showingNewFolderAlert = true
                    } label: {
                        HStack(spacing: SidebarStyle.rowIconTextSpacing) {
                            Image(systemName: "plus")
                                .frame(width: SidebarStyle.iconFrameWidth)
                                .foregroundStyle(Color.accentColor)
                            // V4.36.x: 显式 SidebarStyle.labelFont——与行 label 字号/字重完全一致
                            //   避免 fallback 到系统默认（可能比行 label 略大或粗，视觉不协调）
                            Text(Copy.newFolder)
                                .font(SidebarStyle.labelFont)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SidebarSectionHeader(Copy.sidebarSectionFolders, icon: "folder", count: folders.count, isExpanded: $isFoldersExpanded)
            }

            // ─── Section 3: 标签 ───
            Section {
                if isTagsExpanded {
                    if tags.isEmpty {
                        // V3.6.21: 改用 EmptyStateView 统一空状态
                        EmptyStateView(
                            icon: "tag",
                            title: Copy.emptyNoTags,
                            subtitle: Copy.emptyNoTagsHint,
                            iconColor: .secondary
                        )
                        .frame(height: 100)
                    } else {
                        ForEach(tags) { tag in
                            sidebarRow(
                                icon: "tag",
                                label: tag.name,
                                count: PhotoStats.inLibraryCount(tag),
                                // V6.08: 传 UUID 而非 @Model 引用
                                target: .tag(tag.id),
                                iconColor: Color(hex: tag.colorHex)  // 标签用 tag 颜色
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteTag(tag)
                                } label: {
                                    Label(Copy.deleteTag, systemImage: "trash")
                                }
                            }
                        }
                    }

                    Button {
                        newTagName = ""
                        showingNewTagAlert = true
                    } label: {
                        HStack(spacing: SidebarStyle.rowIconTextSpacing) {
                            Image(systemName: "plus")
                                .frame(width: SidebarStyle.iconFrameWidth)
                                .foregroundStyle(Color.accentColor)
                            // V4.36.x: 显式 SidebarStyle.labelFont——与行 label 字号/字重完全一致
                            Text(Copy.newTag)
                                .font(SidebarStyle.labelFont)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SidebarSectionHeader(Copy.sidebarSectionTags, icon: "tag", count: tags.count, isExpanded: $isTagsExpanded)
            }

            // ─── Section 4: 最近删除（单独 section，底部入口）───
            Section {
                sidebarRow(
                    icon: "trash",
                    label: Copy.sidebarRecentlyDeleted,
                    count: libraryStats.trashedCount,
                    target: .recentlyDeleted,
                    // V4.6.0: 改用 SidebarStyle.iconColorTrash token
                    iconColor: libraryStats.trashedCount > 0 ? SidebarStyle.iconColorTrash : nil
                )
                // V3.6.12: 拖拽缩略图到 trash 行直接 recycle
                .dropDestination(for: URL.self) { urls, _ in
                    handleTrashDrop(urls: urls)
                } isTargeted: { isTargeted in
                    isTrashDropTargeted = isTargeted
                }
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isTrashDropTargeted ? Color.orange.opacity(0.28) : Color.clear)
                        .padding(-4)
                )
                .animation(Animations.interactive, value: isTrashDropTargeted)
            }
            // V6.22.6 (Bug 3): 删 section header — user 决定 row 自己说话, 不要重复 section 标题
            //   原 chevron 也消失 (issue 3 的 "下拉菜单" 取消)
            //   保留 row 视觉, 加 trash icon + label + count, 清晰可点
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        // V5.51: "图馆" → "图库" typo 修复 + 走 Term.library 字典
        .navigationTitle(Term.library)

        .alert(Copy.newFolder, isPresented: $showingNewFolderAlert) {
            TextField(Copy.folderNamePlaceholder, text: $newFolderName)
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.create) { createFolder() }
        }

        .alert(Copy.newTag, isPresented: $showingNewTagAlert) {
            TextField(Copy.tagNamePlaceholder, text: $newTagName)
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.create) { createTag() }
        }
    }

    // MARK: - 侧栏顶部搜索框（V3.5.14 Photos.app 风格 — V3.5.15 已移除）

    /// 统一风格的侧栏 item row
    /// - icon: SF Symbol 名称
    /// - label: 显示文字
    /// - count: 右侧计数（nil = 不显示）
    /// - target: 点击后设置的 selection
    /// - iconColor: 图标颜色（nil = secondary 默认；标签用 tag 颜色）
    @ViewBuilder
    private func sidebarRow(
        icon: String,
        label: String,
        count: Int? = nil,
        target: SidebarSelection,
        iconColor: Color? = nil
    ) -> some View {
        SidebarRow(
            icon: icon,
            iconColor: iconColor,
            label: label,
            count: count,
            isSelected: selection == target,
            action: { selection = target }
        )
        .tag(target)
    }

    // MARK: - 原有方法（保留）

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = Folder(name: trimmed)
        modelContext.insert(folder)
        modelContext.saveWithLog()
        // V6.08: 存 UUID 而非 @Model 引用
        selection = .folder(folder.id)
    }

    private func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        modelContext.saveWithLog()
        // V6.08: UUID 比较, 不再 .folder(Folder) .id 比较
        if case .folder(let id) = selection, id == folder.id {
            selection = .all
        }
    }

    private func createTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let randomColor = TagColors.presets.randomElement() ?? "#5B8FF9"
        let tag = Tag(name: trimmed, colorHex: randomColor)
        modelContext.insert(tag)
        modelContext.saveWithLog()
        // V6.08: 存 UUID 而非 @Model 引用
        selection = .tag(tag.id)
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        modelContext.saveWithLog()
        // V6.08: UUID 比较
        if case .tag(let id) = selection, id == tag.id {
            selection = .all
        }
    }

    private func handlePhotoDrop(urls: [URL], to folder: Folder) -> Bool {
        // V3.6.33: 从 [NSItemProvider] + public.text UUID 改为 [URL] + fileURL 查找
        //   .dropDestination(for: URL.self) 直接给 [URL]（已 deserialized）
        //   按 fileURL 在 allPhotos 找 Photo 对象（fileURL 是 SwiftData @Model 字段，unique）
        //   比旧版本少一层 NSItemProvider + 异步 loadDataRepresentation
        //
        // V3.5.18 修复 crash 模式仍然适用：捕获持久化 ID（folderID）+ context，
        // SwiftData @Model 对象在主线程上操作。

        // 主线程上捕获所有需要的状态
        let folderID = folder.persistentModelID
        let capturedContext = modelContext
        let capturedAllPhotos = allPhotos  // 查 photo 用的快照
        // V3.6.52: 从 photoSelection 派生 selectedIDs 快照（drag 期间防逸出）
        let capturedSelectedIDs = photoSelection.selectedIDs

        // 找到拖动的 photo（按 fileURL 匹配）
        // 多选时：拖动的是单张（.draggable 是 per-view），但如果用户在多选状态拖了被选中的那张，
        // 我们把整个 selectedIDs 一起移动到 folder
        let draggedFileURLs = Set(urls)
        let draggedPhotos = capturedAllPhotos.filter { draggedFileURLs.contains($0.fileURL) }
        guard !draggedPhotos.isEmpty else { return false }

        performMove(
            draggedPhotos: draggedPhotos,
            folderID: folderID,
            folderName: folder.name,
            selectedIDs: capturedSelectedIDs,
            context: capturedContext
        )
        return true
    }

    /// 实际执行移动（主线程，已验证所有对象有效）
    private func performMove(
        draggedPhotos: [Photo],
        folderID: PersistentIdentifier,
        folderName: String,
        selectedIDs: Set<UUID>,
        context: ModelContext
    ) {
        // V3.5.20 修复崩溃：performMove 不再走 ImageGalleryUndoManager.registerAction
        // V3.6.33: 多选时整组移动：拖动的是被选中的图，就移动整个 selectedIDs
        // V6.10: undo 恢复——undoManager 从 ContentView 注入 (init let)
        //   跟 ContentViewModel.batchMove (L803) 模式一致:
        //   action 闭包做实际 move + save, undo 闭包回滚 folder + save

        // 重新获取 folder（如果原对象已删除，这里会返回 nil）
        guard let folder = context.model(for: folderID) as? Folder else { return }

        // 多选判断：被拖的任一 photo 在 selectedIDs 中 → 移动整组
        let draggedIDs = Set(draggedPhotos.map { $0.id })
        let idsToMove: Set<UUID>
        if !selectedIDs.isEmpty && !draggedIDs.intersection(selectedIDs).isEmpty {
            idsToMove = selectedIDs
        } else {
            idsToMove = draggedIDs
        }

        // 拉取要移动的 photos（V6.11: 一次 fetch 替 N+1——N 张图 = N 次 SQLite round-trip
        //   之前 for id in idsToMove { FetchDescriptor; fetch; first } 每次拖 100 张 = 100 次
        //   改 #Predicate { idsToMove.contains($0.id) } 一次拿所有, 跟 ContentViewModel.batchMove 模式一致
        let photos: [Photo]
        if let fetched = try? context.fetch(FetchDescriptor<Photo>(predicate: #Predicate { idsToMove.contains($0.id) })) {
            photos = fetched
        } else {
            return
        }
        guard !photos.isEmpty else { return }

        // V6.14.9: 砍 `undoManager.registerAction` — 跟 ContentViewModel.batchMove (V6.14.4) 同根
        //   根因: registerAction → Foundation.UndoManager.registerUndo(withTarget:) 把
        //   ImageGalleryUndoManager 强引用, 加 action 闭包强捕获 self → 强引用环
        //   在 Swift Testing @MainActor + ModelContainer + run loop 组合下死锁
        //   SidebarView.performMove 之前没人 follow up batchMove 的修法
        //   现在统一砍 — undo 走回收站恢复 (跟 batchMove 同处理)
        //   后续 V6.14.10 重做 ImageGalleryUndoManager (自写 stack) 再恢复
        for photo in photos {
            photo.folder = folder
        }
        context.saveWithLog()
    }

    // V3.6.12 + V3.6.33: 拖到 trash 行的处理器
    private func handleTrashDrop(urls: [URL]) -> Bool {
        // 主线程上捕获状态
        let capturedContext = modelContext
        let capturedAllPhotos = allPhotos
        // V3.6.52: 从 photoSelection 派生 selectedIDs 快照（drag 期间防逸出）
        let capturedSelectedIDs = photoSelection.selectedIDs

        let draggedFileURLs = Set(urls)
        let draggedPhotos = capturedAllPhotos.filter { draggedFileURLs.contains($0.fileURL) }
        // V6.10: 拖入 Finder 外部文件 (在 allPhotos 里查不到) → false 让 SwiftUI 走 no-drop 光标
        guard !draggedPhotos.isEmpty else { return false }

        // V6.10: 拿 trashed 数量, 0 时返 false (不消费 drop). 之前 return true 无条件,
        //   即便 photo 全部已在 trash 没真删也消费, 视觉/光标反馈错
        let trashedCount = performTrash(
            draggedPhotos: draggedPhotos,
            selectedIDs: capturedSelectedIDs,
            context: capturedContext
        )
        return trashedCount > 0
    }

    /// 实际执行 recycle（trash drop 用）
    /// - Returns: 实际 trash 的照片数 (过滤已在 trash / 找不到的)
    private func performTrash(
        draggedPhotos: [Photo],
        selectedIDs: Set<UUID>,
        context: ModelContext
    ) -> Int {
        // 多选时整组 trash：拖动的是被选中的图，就 trash 整组
        let draggedIDs = Set(draggedPhotos.map { $0.id })
        let idsToTrash: Set<UUID>
        if !selectedIDs.isEmpty && !draggedIDs.intersection(selectedIDs).isEmpty {
            idsToTrash = selectedIDs
        } else {
            idsToTrash = draggedIDs
        }

        // 拉取 photos（V6.11: 一次 fetch 替 N+1, 跟 performMove 同模式）
        //   之前 N 张 trash = N 次 fetch, 改 #Predicate { idsToTrash.contains($0.id) } 一次
        let allPhotos: [Photo]
        if let fetched = try? context.fetch(FetchDescriptor<Photo>(predicate: #Predicate { idsToTrash.contains($0.id) })) {
            allPhotos = fetched
        } else {
            return 0
        }
        // V6.11: 过滤掉已在 trash 的——保留原 isInTrash 过滤
        let photos = allPhotos.filter { !$0.isInTrash }
        guard !photos.isEmpty else { return 0 }

        // recycle（软删）
        let service = RecycleBinService(storage: .shared, modelContext: context)
        for photo in photos { service.recycle(photo) }
        return photos.count
    }

    // 拖拽高亮背景（V3.5.17：fill + border，Photos.app 风格）
    // V3.6.36: 改用 springGentle 替换 quick（0.15s 太快，视觉像突现）
    //   + 0.20 → 0.28 透明度（更明显）+ 加 .shadow 让高亮有"抬起"感
    private func folderDropHighlight(_ folder: Folder) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(dropTargetFolderID == folder.id
                      ? Color.accentColor.opacity(0.28)
                      : Color.clear)
                .padding(-4)
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(dropTargetFolderID == folder.id
                        ? Color.accentColor
                        : Color.clear,
                        lineWidth: 2)
                .padding(-4)
                .shadow(
                    color: dropTargetFolderID == folder.id
                        ? Color.accentColor.opacity(0.4)
                        : .clear,
                    radius: 6
                )
        }
        .animation(Animations.springGentle, value: dropTargetFolderID == folder.id)
    }

    // V3.5.8：把 ForEach 里的复杂修饰符链抽出（修类型检查超时）
    @ViewBuilder
    private func folderSidebarRow(_ folder: Folder) -> some View {
        sidebarRow(
            icon: folder.icon,
            label: folder.name,
            // V3.6.4：用 PhotoStats 排除 trashed 的（之前 folder.photos.count 包含 trashed，
            // 跟 grid 在 .folder 视图下显示的图数不一致）
            count: PhotoStats.inLibraryCount(folder),
            // V6.08: 传 UUID 而非 @Model 引用
            target: .folder(folder.id)
        )
        .background(folderDropHighlight(folder))
        // V3.6.33: .onDrop(of: [.text]) → .dropDestination(for: URL.self)
        // 配对 .draggable(URL) 现代 API 对
        .dropDestination(for: URL.self) { urls, _ in
            handlePhotoDrop(urls: urls, to: folder)
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTargetFolderID = folder.id
            } else if dropTargetFolderID == folder.id {
                dropTargetFolderID = nil
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label(Copy.deleteFolder, systemImage: "trash")
            }
        }
    }

    // P4.1: 智能文件夹 row — 跟 folderSidebarRow 类似, 但用 .smartFolder(UUID) target
    //   P4.1.1: count 实际算 (用 PhotoStats.smartFolderCount + sf.decodedFilter)
    @ViewBuilder
    private func smartFolderRow(_ sf: SmartFolder) -> some View {
        sidebarRow(
            icon: sf.iconName,
            label: sf.name,
            // P4.1.1: 实际算 count — 跟 V6.11 教训一致, 用 filtered() result 不用 photos input
            count: PhotoStats.smartFolderCount(allPhotos, smartFolderFilter: sf.decodedFilter),
            target: .smartFolder(sf.id)
        )
        // P4.1.1: 右键删除入口 (跟 folder 类似)
        .contextMenu {
            Button(role: .destructive) {
                deleteSmartFolder(sf)
            } label: {
                Label("删除智能文件夹", systemImage: "trash")
            }
        }
    }

    /// P4.1: 删除 SmartFolder — 跟 deleteFolder 类似, 从 modelContext 移除
    private func deleteSmartFolder(_ sf: SmartFolder) {
        modelContext.delete(sf)
        // 如果当前 sidebarSelection 指向这个 SmartFolder, 自动切回 .all
        //  (因为下次访问时 fetch 返 nil, 见 ContentViewModel.currentSmartFolder)
        if selection == .smartFolder(sf.id) {
            selection = .all
        }
        try? modelContext.save()
    }

    /// P4.1.1: 触发智能文件夹创建 sheet — 拿当前 model.filterState 作初值快照
    ///   snapshot 避免 sheet 打开后用户改 toolbar filter 干扰预览
    private func onCreateSmartFolder() {
        model.pendingSmartFolderFilter = model.filterState
        model.showingNewSmartFolderSheet = true
    }
}

#Preview {
    // P4.1.1: model parameter 加进 init 后, Preview 用 suite 隔离 UserDefaults
    //   suite 独立, 不污染 standard 也不持久化
    let previewDefaults = UserDefaults(suiteName: "com.iridescent.ImageGallery.preview") ?? .standard
    SidebarView(
        selection: .constant(.all),
        photoSelection: .constant(SelectionState()),
        thumbnailSize: .constant(170),
        sortOption: .constant(.importedAtDesc),
        model: ContentViewModel(settings: UserSettings(defaults: previewDefaults))
    )
    .frame(width: 220, height: 600)
}
