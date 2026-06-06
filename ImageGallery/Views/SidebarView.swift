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
import UniformTypeIdentifiers

struct SidebarView: View {
    // SwiftData 查询
    @Query(sort: \Folder.createdAt, order: .forward) private var folders: [Folder]
    @Query(sort: \Tag.createdAt, order: .forward) private var tags: [Tag]
    @Query private var allPhotos: [Photo]

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

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
    private var libraryCounts: (all: Int, favorites: Int, unfiled: Int) {
        let favorites = allPhotos.filter { $0.isFavorite }.count
        let unfiled = allPhotos.filter { $0.folder == nil }.count
        return (allPhotos.count, favorites, unfiled)
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
            } header: {
                SidebarSectionHeader("我的图馆")
            }

            // ─── 智能文件夹 ───
            Section {
                sidebarRow(icon: "clock.arrow.circlepath", label: "最近 7 天", target: .recent7Days)
                sidebarRow(icon: "large.circle", label: "大图 (>5MB)", target: .largeFiles)
            } header: {
                SidebarSectionHeader("智能文件夹")
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
                SidebarSectionHeader("我的文件夹")
            }

            // ─── 标签 ───
            Section {
                if tags.isEmpty {
                    Text("还没有标签")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 26)  // 对齐图标位置
                } else {
                    ForEach(tags) { tag in
                        sidebarRow(
                            icon: "tag",
                            label: tag.name,
                            count: tag.photos.count,
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
                SidebarSectionHeader("标签")
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

    private func handlePhotoDrop(providers: [NSItemProvider], to folder: Folder) -> Bool {
        // V3.5.18 修复 crash：
        // 1. 闭包捕获了 self（struct 副本），里面的 selectedIDs/folder/modelContext 是陈旧值
        // 2. SwiftData @Model 对象在异步闭包里访问可能 EXC_BAD_ACCESS
        // 3. loadObject(ofClass:) 在 macOS 14+ 不稳定，用 loadDataRepresentation
        // 修复：主线程上捕获 persistentID/IDs/context，异步回调里重新获取 folder

        // 主线程上捕获所有需要的状态
        let folderID = folder.persistentModelID
        let folderName = folder.name  // String 是值类型，安全
        let capturedSelectedIDs = selectedIDs
        let capturedContext = modelContext

        var anyHandled = false
        for provider in providers {
            // 用 hasItemConformingToTypeIdentifier 检查（比 canLoadObject 更可靠）
            guard provider.hasItemConformingToTypeIdentifier("public.text") else { continue }
            anyHandled = true

            // 用 loadDataRepresentation（macOS 14+ 推荐）
            provider.loadDataRepresentation(forTypeIdentifier: "public.text") { data, error in
                guard error == nil,
                      let data = data,
                      let str = String(data: data, encoding: .utf8),
                      let uuid = UUID(uuidString: str) else { return }

                // 回到主线程执行 SwiftData 操作
                DispatchQueue.main.async {
                    // 重新获取 folder（如果原对象已删除，这里会返回 nil）
                    guard let folder = capturedContext.model(for: folderID) as? Folder else { return }

                    // 执行移动
                    performMove(
                        draggedUUID: uuid,
                        to: folder,
                        folderName: folderName,
                        selectedIDs: capturedSelectedIDs,
                        context: capturedContext
                    )
                }
            }
        }
        return anyHandled
    }

    /// 实际执行移动（主线程，已验证所有对象有效）
    private func performMove(
        draggedUUID: UUID,
        to folder: Folder,
        folderName: String,
        selectedIDs: Set<UUID>,
        context: ModelContext
    ) {
        // 确定要移动的 ID 集合
        let idsToMove: Set<UUID>
        if !selectedIDs.isEmpty && selectedIDs.contains(draggedUUID) {
            idsToMove = selectedIDs
        } else {
            idsToMove = [draggedUUID]
        }

        // 快照：每个 photo 移动前的 folder
        var snapshots: [(id: UUID, oldFolder: Folder?)] = []
        var photos: [Photo] = []
        for id in idsToMove {
            let descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })
            if let photo = try? context.fetch(descriptor).first {
                snapshots.append((id, photo.folder))
                photos.append(photo)
            }
        }
        guard !photos.isEmpty else { return }

        // 注册撤销（用捕获的 String 名字，避免再访问 SwiftData @Model）
        let count = photos.count
        undoManager?.registerAction(
            description: "移动 \(count) 张照片到 \(folderName)"
        ) {
            for photo in photos {
                photo.folder = folder
            }
            try? context.save()
            // V3.5.18 修复：删除 selectedIDs = []（在异步闭包里设 @Binding 会崩）
        } undo: {
            for (snapshot, photo) in zip(snapshots, photos) {
                photo.folder = snapshot.oldFolder
            }
            try? context.save()
        }
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
        .animation(.easeInOut(duration: 0.15), value: dropTargetFolderID == folder.id)
    }

    // V3.5.8：把 ForEach 里的复杂修饰符链抽出（修类型检查超时）
    @ViewBuilder
    private func folderSidebarRow(_ folder: Folder) -> some View {
        sidebarRow(
            icon: folder.icon,
            label: folder.name,
            count: folder.photos.count,
            target: .folder(folder)
        )
        .background(folderDropHighlight(folder))
        .onDrop(of: [.text], isTargeted: Binding(
            get: { dropTargetFolderID == folder.id },
            set: { isTargeted in
                if isTargeted {
                    dropTargetFolderID = folder.id
                } else if dropTargetFolderID == folder.id {
                    dropTargetFolderID = nil
                }
            }
        )) { providers in
            handlePhotoDrop(providers: providers, to: folder)
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
