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
    @Query private var allPhotos: [Photo]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext

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
    @State private var showingNewFolderAlert = false
    @State private var showingNewTagAlert = false
    @State private var newName = ""

    // 拖拽目标高亮
    @State private var dropTargetFolderID: UUID?
    // V3.6.12: 拖到 trash 行的高亮状态
    @State private var isTrashDropTargeted: Bool = false

    // ─── 计算重复图数量 ───
    private var duplicateCount: Int {
        let groups = Dictionary(grouping: allPhotos) { $0.fileHash }
        let duplicateHashes = groups.compactMap { $0.key != nil && $0.value.count > 1 ? $0.key : nil }
        return allPhotos.filter { photo in
            guard let hash = photo.fileHash else { return false }
            return duplicateHashes.contains(hash)
        }.count
    }

    // 各 section 的 item 数（用于显示在 section header 上）
    // V3.6.1：用 PhotoStats 纯函数集合（之前每行各自 filter，4 次遍历）
    // V5.7: 砍 favorites 字段——侧边栏不再有收藏入口（走筛选 popover 评分 ≥ 5）
    private var libraryCounts: (all: Int, unfiled: Int, trashed: Int) {
        (
            all: PhotoStats.inLibrary(allPhotos).count,
            unfiled: PhotoStats.unfiled(allPhotos).count,
            trashed: PhotoStats.trashed(allPhotos).count
        )
    }

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
                    sidebarRow(icon: "photo.on.rectangle.angled", label: "全部", count: libraryCounts.all, target: .all)
                    // V5.7: 砍 sidebarRow "收藏"——侧边栏只放主导航
                    //   收藏 = 评分 ≥ 5 走筛选 popover（用户在筛选 popover 内点击 ≥5 星即可看收藏）
                    sidebarRow(icon: "tray", label: "待整理", count: libraryCounts.unfiled, target: .unfiled)
                    if duplicateCount > 0 {
                        sidebarRow(icon: "doc.on.doc", label: "重复图", count: duplicateCount, target: .duplicates, iconColor: SidebarStyle.iconColorDuplicate)
                    }
                    // V4.1.0: 智能文件夹移进"我的图馆"section（之前是独立 section）
                    sidebarRow(icon: "clock.arrow.circlepath", label: "最近 7 天", target: .recent7Days, iconColor: SidebarStyle.iconColorRecent)
                    sidebarRow(icon: "large.circle", label: "大图（>5MB）", target: .largeFiles, iconColor: SidebarStyle.iconColorLarge)
                }
            } header: {
                // V4.1.0: 可见 header（V3.6.25 之前被隐藏）
                SidebarSectionHeader("我的图馆", icon: "sparkles", isExpanded: $isLibraryExpanded)
            }

            // ─── Section 2: 我的文件夹 ───
            Section {
                if isFoldersExpanded {
                    ForEach(folders) { folder in
                        folderSidebarRow(folder)
                    }

                    Button {
                        newName = ""
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
                SidebarSectionHeader("我的文件夹", icon: "folder", isExpanded: $isFoldersExpanded)
            }

            // ─── Section 3: 标签 ───
            Section {
                if isTagsExpanded {
                    if tags.isEmpty {
                        // V3.6.21: 改用 EmptyStateView 统一空状态
                        EmptyStateView(
                            icon: "tag",
                            title: "还没有标签",
                            subtitle: "新建一个标签，给照片打上分类标记",
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
                        newName = ""
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
                SidebarSectionHeader("标签", icon: "tag", isExpanded: $isTagsExpanded)
            }

            // ─── Section 4: 最近删除（单独 section，底部入口）───
            Section {
                sidebarRow(
                    icon: "trash",
                    label: "最近删除",
                    count: libraryCounts.trashed,
                    target: .recentlyDeleted,
                    // V4.6.0: 改用 SidebarStyle.iconColorTrash token
                    iconColor: libraryCounts.trashed > 0 ? SidebarStyle.iconColorTrash : nil
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
            } header: {
                // V4.1.0: trash 是关键入口，不可折叠
                SidebarSectionHeader("最近删除", icon: "trash", isExpanded: .constant(true))
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        // V5.51: "图馆" → "图库" typo 修复 + 走 Term.library 字典
        .navigationTitle(Term.library)

        .alert(Copy.newFolder, isPresented: $showingNewFolderAlert) {
            TextField(Copy.folderNamePlaceholder, text: $newName)
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.create) { createFolder() }
        }

        .alert(Copy.newTag, isPresented: $showingNewTagAlert) {
            TextField(Copy.tagNamePlaceholder, text: $newName)
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
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
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
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
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

        // 拉取要移动的 photos（按 ID 查 SwiftData）
        var photos: [Photo] = []
        for id in idsToMove {
            let descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })
            if let photo = try? context.fetch(descriptor).first {
                photos.append(photo)
            }
        }
        guard !photos.isEmpty else { return }

        // 直接修改 + 保存（不走 undoManager）
        for photo in photos {
            photo.folder = folder
        }
        try? context.save()
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
        guard !draggedPhotos.isEmpty else { return false }

        performTrash(
            draggedPhotos: draggedPhotos,
            selectedIDs: capturedSelectedIDs,
            context: capturedContext
        )
        return true
    }

    /// 实际执行 recycle（trash drop 用）
    private func performTrash(
        draggedPhotos: [Photo],
        selectedIDs: Set<UUID>,
        context: ModelContext
    ) {
        // 多选时整组 trash：拖动的是被选中的图，就 trash 整组
        let draggedIDs = Set(draggedPhotos.map { $0.id })
        let idsToTrash: Set<UUID>
        if !selectedIDs.isEmpty && !draggedIDs.intersection(selectedIDs).isEmpty {
            idsToTrash = selectedIDs
        } else {
            idsToTrash = draggedIDs
        }

        // 拉取 photos（按 ID 查 SwiftData，过滤掉已在 trash 的）
        var photos: [Photo] = []
        for id in idsToTrash {
            let descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })
            if let photo = try? context.fetch(descriptor).first, !photo.isInTrash {
                photos.append(photo)
            }
        }
        guard !photos.isEmpty else { return }

        // recycle（软删）
        let service = RecycleBinService(storage: .shared, modelContext: context)
        for photo in photos { service.recycle(photo) }
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
}

#Preview {
    SidebarView(
        selection: .constant(.all),
        photoSelection: .constant(SelectionState()),
        thumbnailSize: .constant(170),
        sortOption: .constant(.importedAtDesc)
    )
    .frame(width: 220, height: 600)
}
