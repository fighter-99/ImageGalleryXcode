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

    // 多选集合（双向绑定）
    @Binding var selectedIDs: Set<UUID>

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
    private var libraryCounts: (all: Int, favorites: Int, unfiled: Int, trashed: Int) {
        (
            all: PhotoStats.inLibrary(allPhotos).count,
            favorites: PhotoStats.favorites(allPhotos).count,
            unfiled: PhotoStats.unfiled(allPhotos).count,
            trashed: PhotoStats.trashed(allPhotos).count
        )
    }

    var body: some View {
        // V3.5.15：纯导航侧栏，搜索在工具栏（V3.5.14 的侧栏顶部搜索框已移除）
        List(selection: $selection) {
            // ─── 智能项 ───
            Section {
                sidebarRow(icon: "photo.on.rectangle.angled", label: "全部", count: libraryCounts.all, target: .all)
                sidebarRow(icon: "star", label: "收藏", count: libraryCounts.favorites, target: .favorites)
                sidebarRow(icon: "tray", label: "待整理", count: libraryCounts.unfiled, target: .unfiled)
                if duplicateCount > 0 {
                    sidebarRow(icon: "doc.on.doc", label: "重复图", count: duplicateCount, target: .duplicates, iconColor: .orange)
                }
                // V3.6 NEW: 回收站入口（始终显示，包括 0 张时；不显示空状态可能让用户找不到入口）
                // V3.6.6: count > 0 时图标橙色高亮，提醒有待处理项
                // V3.6.12: 拖拽缩略图到 trash 行直接 recycle（Photos.app 习惯动作）
                sidebarRow(
                    icon: "trash",
                    label: "最近删除",
                    count: libraryCounts.trashed,
                    target: .recentlyDeleted,
                    iconColor: libraryCounts.trashed > 0 ? .orange : nil
                )
                // V3.6.33: .onDrop(of: [.text]) → .dropDestination(for: URL.self)
                // 配对 .draggable(URL) 现代 API 对
                .dropDestination(for: URL.self) { urls, _ in
                    handleTrashDrop(urls: urls)
                } isTargeted: { isTargeted in
                    isTrashDropTargeted = isTargeted
                }
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isTrashDropTargeted ? Color.orange.opacity(0.25) : Color.clear)
                        .padding(-4)
                )
                .animation(Animations.quick, value: isTrashDropTargeted)
            } header: {
                // V3.6.25: 隐藏 section header（"我的图馆"）
                EmptyView()
            }

            // ─── 智能文件夹 ───
            Section {
                sidebarRow(icon: "clock.arrow.circlepath", label: "最近 7 天", target: .recent7Days)
                sidebarRow(icon: "large.circle", label: "大图 (>5MB)", target: .largeFiles)
            } header: {
                SidebarSectionHeader("智能文件夹", icon: "sparkles")
            }

            // ─── 用户文件夹 ───
            Section {
                ForEach(folders) { folder in
                    folderSidebarRow(folder)
                }

                Button {
                    newName = ""
                    showingNewFolderAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .frame(width: 18)
                            .foregroundStyle(Color.accentColor)
                        Text("新建文件夹")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                SidebarSectionHeader("我的文件夹", icon: "folder")
            }

            // ─── 标签 ───
            Section {
                if tags.isEmpty {
                    // V3.6.21: 改用 EmptyStateView 统一空状态（替代之前灰色小字）
                    EmptyStateView(
                        icon: "tag",
                        title: "还没有标签",
                        subtitle: "新建一个标签，给照片打上分类标记",
                        iconColor: .secondary
                    )
                    .frame(height: 100)  // 紧凑版（避免在 List row 内占太多空间）
                } else {
                    ForEach(tags) { tag in
                        sidebarRow(
                            icon: "tag",
                            label: tag.name,
                            // V3.6.4：用 PhotoStats 排除 trashed 的（之前 tag.photos.count 包含 trashed）
                            count: PhotoStats.inLibraryCount(tag),
                            target: .tag(tag),
                            iconColor: Color(hex: tag.colorHex)  // 标签用 tag 颜色
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteTag(tag)
                            } label: {
                                Label("删除标签", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    newName = ""
                    showingNewTagAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .frame(width: 18)
                            .foregroundStyle(Color.accentColor)
                        Text("新建标签")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                SidebarSectionHeader("标签", icon: "tag")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)  // V3.5.8：隐藏 List 默认背景（用 Surface 统一）
        .listRowSeparator(.hidden)         // V3.5.8：隐藏 List 默认分隔线
        .navigationTitle("图馆")

        .alert("新建文件夹", isPresented: $showingNewFolderAlert) {
            TextField("文件夹名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") { createFolder() }
        }

        .alert("新建标签", isPresented: $showingNewTagAlert) {
            TextField("标签名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") { createTag() }
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
        try? modelContext.save()
        selection = .folder(folder)
    }

    private func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        try? modelContext.save()
        if case .folder(let current) = selection, current.id == folder.id {
            selection = .all
        }
    }

    private func createTag() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let randomColor = TagColors.presets.randomElement() ?? "#5B8FF9"
        let tag = Tag(name: trimmed, colorHex: randomColor)
        modelContext.insert(tag)
        try? modelContext.save()
        selection = .tag(tag)
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        try? modelContext.save()
        if case .tag(let current) = selection, current.id == tag.id {
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
        let capturedSelectedIDs = selectedIDs

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
        let capturedSelectedIDs = selectedIDs

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
    private func folderDropHighlight(_ folder: Folder) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(dropTargetFolderID == folder.id
                      ? Color.accentColor.opacity(0.20)
                      : Color.clear)
                .padding(-4)
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(dropTargetFolderID == folder.id
                        ? Color.accentColor
                        : Color.clear,
                        lineWidth: 2)
                .padding(-4)
        }
        .animation(Animations.quick, value: dropTargetFolderID == folder.id)
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
            target: .folder(folder)
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
                Label("删除文件夹", systemImage: "trash")
            }
        }
    }
}

#Preview {
    SidebarView(
        selection: .constant(.all),
        selectedIDs: .constant([])
    )
    .frame(width: 220, height: 600)
}
