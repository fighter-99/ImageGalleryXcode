//
//  DetailView.swift
//  ImageGallery
//
//  右侧详情面板。显示当前选中图片的大图、元数据、标签管理、删除。
//  顶部带"上一张/下一张"导航，方便连续翻看。
//

import SwiftUI
import os  // V4.9.5: Logger.imageIO for async load failure
import SwiftData
import AppKit

struct DetailView: View {
    // @Bindable 让 SwiftUI 监听 SwiftData @Model 属性的变化
    @Bindable var photo: Photo

    // SwiftData 上下文
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager  // V3.5 Phase 2

    // 所有标签
    @Query(sort: \Tag.createdAt, order: .forward) private var allTags: [Tag]

    // 通知父视图
    let onDelete: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let canPrev: Bool
    let canNext: Bool
    let currentIndex: Int    // 1-based, 0 表示无
    let totalCount: Int

    // 弹窗控制
    @State private var showingAddTagAlert = false

    // V4.9.5: 大图 async 加载——避免同步 IO 阻塞主线程
    //   .task(id: photo.id) 自动取消旧任务，photo 变化时重载
    @State private var bigImage: NSImage?
    @State private var bigImageLoadFailed: Bool = false
    @State private var showingDeleteConfirm = false
    @State private var showingRenameAlert = false
    @State private var newTagName = ""
    @State private var newFileName = ""

    var body: some View {
        // V3.5.21：详情面板卡片化 — ScrollView + VStack of cards
        // V4.16.0: 加 .contextMenu——右击 detail panel 任意位置可复制
        //   operationsCard 已有 3 个高频按钮（收藏/Finder/删除）
        //   contextMenu 提供"复制"1 个补充 action（不重复 operationsCard）
        //
        // V4.24.0: 完整 Photos 风格——去 4 card 容器视觉分隔
        //   ↑ V4.5.0 注释 "分隔靠外层 VStack(spacing: Spacing.md) 自然间距"——这本身造成
        //     4 个 card 像漂浮的 4 个独立卡片
        //   ↑ macOS Photos 实际：单长滚动区 + sections 用 Divider 分隔（无 VStack spacing）
        //   ↑ 1️⃣ 大图 0 padding 紧贴 detail panel 边缘（顶/底 0）——Photos 风格顶部大图
        //   ↑ 2️⃣ 3️⃣ 4️⃣ sections 间 Divider 分隔，无 VStack spacing
        //   ↑ sections 内 padding 保留（info/tags/operations 元数据呼吸空间）
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 1️⃣ 大图区（顶部，0 padding 紧贴 detail panel 边缘）
                bigImageCard

                Divider().padding(.vertical, Spacing.xs)

                // 2️⃣ 信息区（文件名 + 元数据）
                infoCard

                Divider().padding(.vertical, Spacing.xs)

                // 3️⃣ 标签区
                tagsCard

                Divider().padding(.vertical, Spacing.xs)

                // 4️⃣ 操作区
                operationsCard

                Spacer(minLength: 0)
            }
        }
        // V4.1.0d: 改用 .regularMaterial——与侧栏、主工具栏统一
        //   整个控制区 = 半透明毛玻璃；主区 = opaque canvas（照片焦点）
        // V4.21.0: 撤回 V4.18.0 .glassEffect(.regular)——同 SidebarView
        //   macOS 26 单 view glassEffect 视觉副作用未消除
        .background(.regularMaterial)
        .frame(minWidth: 280)
        .alert("新建标签", isPresented: $showingAddTagAlert) {
            TextField("标签名称", text: $newTagName)
            Button("取消", role: .cancel) {}
            Button("创建") { createAndAddTag() }
        }
        .alert("重命名", isPresented: $showingRenameAlert) {
            TextField("新文件名", text: $newFileName)
            Button("取消", role: .cancel) {}
            Button("确定") { renamePhoto() }
        } message: {
            Text("给图片一个新名字（不包含扩展名）")
        }
        .confirmationDialog(
            "确定要删除这张图片吗？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deletePhoto() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("图片将从图库中移除，文件也会被永久删除。")
        }
        // V4.16.0: 右击 detail panel 任意位置 → 复制（与 operationsCard 不重复）
        .contextMenu {
            Button {
                // NSPasteboard 复制 photo.fileURL（URL promise——接受方读原文件）
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([photo.fileURL as NSURL])
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - 卡片组件（V3.5.21 / V4.5.0 重写）

    /// 通用卡片容器
    ///
    /// V3.5.21 原版：cardBackground 填充 + 0.5pt cardBorder 描边
    /// V4.5.0 重写：删双层背景 + 边框
    ///   原因：detail panel 已用 .regularMaterial 整体 vibrancy，再加 cardBackground 是
    ///        双层背景叠加 → 4 个 card 形成 4 个浅灰圆角 + 4 圈细灰边 = 「卡片浅框」幽灵
    ///        （与 V4.4.5 cell 浅框同源）
    ///   现在：仅保留 padding，分隔靠外层 VStack(spacing: Spacing.md) 自然间距
    ///        + 各 card 内部字体层级（headline / secondary / caption）形成视觉层次
    ///        Photos.app detail panel 同款做法
    private func detailCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 1️⃣ 大图卡
    private var bigImageCard: some View {
        Group {
            if let nsImage = bigImage {
                // V4.26.0: 加 .frame(maxHeight: .infinity)——双方向 fit
                //   V4.25.0 只删 maxHeight 360 但没加 .infinity——image 按 aspectRatio
                //   算 fit 高度, 在窄 detail panel visible area 时仍超出被裁
                //   .frame(maxWidth: .infinity, maxHeight: .infinity) + aspectRatio(.fit)
                //   = SwiftUI 按 min(width, height) 缩放——image 完整 fit 父容器
                //   视觉效果: 大图在 detail panel visible area 完整显示 (按比例缩放)
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bigImageLoadFailed {
                // V4.9.5: 加载失败——显示 photo 占位 + 错误 icon
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Palette.cellFilled)
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.tertiary)
                    }
            } else {
                // V4.9.5: 加载中——Shimmer 占位（V4.4.0 Shimmer 复用）
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Palette.cellFilled)
                    // V4.25.0: 删 maxHeight 360——Shimmer 占位也按 detail panel 宽度自适应
                    .frame(maxWidth: .infinity)
                    .modifier(Shimmer(duration: 1.2))
            }
        }
        // V4.25.0: 删 maxHeight 360——大图按 aspectRatio 完整显示
        //   V4.4.0 当时限制 360pt 是 "占 50% 高度"——但 360pt 固定值不随窗口高度变
        //   大图竖向 1080×1621 在 detail panel 280pt 宽度下, height = 420pt——超过 360pt 被裁剪
        //   macOS Photos 实际: 大图按 aspectRatio 完整显示 + 整个 detail panel 滚动
        //   删 maxHeight 限制——大图按 fit 缩放到 detail panel 宽度 + 高度由 aspectRatio 决定
        .frame(maxWidth: .infinity)
        // V4.9.5: async 加载——photo.id 变化时自动取消旧任务
        .task(id: photo.id) {
            bigImage = nil
            bigImageLoadFailed = false
            bigImage = await ImageLoader.loadImageAsync(
                at: photo.fileURL,
                maxPixelSize: 2000
            )
            if bigImage == nil {
                bigImageLoadFailed = true
                Logger.imageIO.error("DetailView loadImageAsync failed: \(photo.fileURL.path, privacy: .public)")
            }
        }
        // V4.17.0: photo 切换时 opacity + scale spring 过渡
        //   .id(photo.id) 强制 child 替换触发 transition
        //   视觉：旧图淡出 + 缩小 + 新图淡入 + 放大
        //   旧实现：photo 切换瞬间图替换（无 transition 感觉"跳"）
        .id(photo.id)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: photo.id)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Palette.cellFilled.opacity(0.3))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Surface.cardBorder, lineWidth: 0.5)
        )
        // 导航覆盖层：← / 索引 / →
        .overlay(alignment: .bottom) {
            HStack(spacing: Spacing.md) {
                detailNavButton(systemName: "chevron.left", help: "上一张 (←)") {
                    onPrev()
                }
                .disabled(!canPrev)
                .opacity(canPrev ? 0.9 : 0.3)

                if totalCount > 0 {
                    Text("\(currentIndex) / \(totalCount)")
                        .font(Typography.captionMono)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        // V4.21.0: 撤回 .glassEffect——macOS 26 单 view 视觉副作用
                        .background(.ultraThinMaterial, in: Capsule())
                }

                detailNavButton(systemName: "chevron.right", help: "下一张 (→)") {
                    onNext()
                }
                .disabled(!canNext)
                .opacity(canNext ? 0.9 : 0.3)
            }
            .padding(Spacing.sm)
        }
    }

    /// 详情导航按钮（← / →）
    private func detailNavButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                // V4.21.0: 撤回 .glassEffect——macOS 26 单 view 视觉副作用
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// 2️⃣ 信息卡（文件名 + 元数据）
    private var infoCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // 文件名（标题级 + 重命名按钮）
                // V4.5.0: 字号 .title3.semibold → .headline（13pt semibold，窄 panel 不换行）
                //         重命名按钮 .plain → .borderless（hover 出系统圆角灰底，可识别为按钮）
                HStack(spacing: Spacing.sm) {
                    Text(photo.filename)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        newFileName = photo.filename
                        showingRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .help("重命名")
                }

                Divider().opacity(0.5)

                // 元数据 grid（2 列：图标 + 内容）
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let folder = photo.folder {
                        infoRow(icon: "folder", text: folder.name)
                    }
                    if photo.width > 0 && photo.height > 0 {
                        let dim = "\(photo.width) × \(photo.height)"
                        infoRow(icon: "ruler", text: dim, mono: true)
                    }
                    infoRow(icon: "doc", text: formatFileSize(photo.fileSize), mono: true)
                    infoRow(icon: "calendar", text: formatDate(photo.importedAt), mono: true)
                }
            }
        }
    }

    /// 信息行（图标 + 文字）
    private func infoRow(icon: String, text: String, mono: Bool = false) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            if mono {
                Text(text)
                    .font(Typography.captionMono)
                    .foregroundStyle(.primary)
            } else {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
    }

    /// 4️⃣ 标签卡
    private var tagsCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("标签")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        newTagName = ""
                        showingAddTagAlert = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.callout)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .help("添加标签")
                }

                if photo.tags.isEmpty {
                    HStack {
                        Image(systemName: "tag")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("点击 + 添加标签")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Spacing.xs)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(photo.tags) { tag in
                            TagChip(tag: tag) {
                                removeTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 5️⃣ 操作卡
    private var operationsCard: some View {
        detailCard {
            // V4.5.0: 加 .controlSize(.large) 让按钮更舒展（同 MultiSelectDetailView V4.4.7）
            //   旧 .bordered + frame infinity 默认高度 ~26pt，内容占按钮 30% 宽，比例失衡
            //   .controlSize(.large) → 32pt 高 + 字号自动适配 → 与容器框比例协调
            // V4.16.0: 加 "在 Finder 中显示" 按钮（3 按钮等宽，V4.5.0 注释的 2 按钮
            //   扩为 3 按钮——detail panel 宽度足以容纳）
            HStack(spacing: Spacing.md) {
                // 收藏切换
                Button {
                    photo.isFavorite.toggle()
                    modelContext.saveWithLog()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: photo.isFavorite ? "star.fill" : "star")
                        Text(photo.isFavorite ? "已收藏" : "收藏")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(photo.isFavorite ? .yellow : .accentColor)

                // V4.16.0: 在 Finder 中显示——macOS Photos 标配
                //   NSWorkspace.activateFileViewerSelecting(_:) 高亮选中文件
                //   并打开 Finder（如果已开则前置）
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("在 Finder 中显示")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                // 删除
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }


    // ─── 移除标签（V3.5 Phase 2：支持撤销）───
    private func removeTag(_ tag: Tag) {
        undoManager?.registerAction(
            description: "移除标签 \(tag.name)"
        ) {
            photo.tags.removeAll { $0.id == tag.id }
            modelContext.saveWithLog()
        } undo: {
            photo.tags.append(tag)
            modelContext.saveWithLog()
        }
    }

    // ─── 重命名（V3.5 Phase 2：支持撤销 + 同步文件磁盘）───
    private func renamePhoto() {
        let trimmed = newFileName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != photo.filename else { return }

        // 快照：旧文件名 + 旧 URL
        let oldFilename = photo.filename
        let oldURL = photo.fileURL
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(trimmed)

        // 避免重名：若新 URL 已存在，放弃
        if FileManager.default.fileExists(atPath: newURL.path) && newURL != oldURL {
            return
        }

        undoManager?.registerAction(
            description: "重命名为 \(trimmed)"
        ) {
            // 执行：磁盘重命名 + SwiftData 更新
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
            photo.filename = trimmed
            photo.fileURL = newURL
            modelContext.saveWithLog()
        } undo: {
            // 撤销：磁盘重命名回 + SwiftData 回滚
            try? FileManager.default.moveItem(at: newURL, to: oldURL)
            photo.filename = oldFilename
            photo.fileURL = oldURL
            modelContext.saveWithLog()
        }
    }

    // ─── 创建并添加标签（V3.5 Phase 2：支持撤销）───
    private func createAndAddTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // 先确定要添加的 tag（已存在的 or 新建的）
        let tagToAdd: Tag
        if let existing = allTags.first(where: { $0.name == trimmed }) {
            if photo.tags.contains(where: { $0.id == existing.id }) {
                return  // 已经加过了
            }
            tagToAdd = existing
        } else {
            let randomColor = TagColors.presets.randomElement() ?? "#5B8FF9"
            let newTag = Tag(name: trimmed, colorHex: randomColor)
            modelContext.insert(newTag)
            tagToAdd = newTag
        }

        // V3.5 Phase 2：注册撤销
        undoManager?.registerAction(
            description: "添加标签 \(tagToAdd.name)"
        ) {
            photo.tags.append(tagToAdd)
            modelContext.saveWithLog()
        } undo: {
            photo.tags.removeAll { $0.id == tagToAdd.id }
            modelContext.saveWithLog()
        }
    }

    // ─── 删除图片（V3.6：走 RecycleBinService.recycle，移到回收站）───
    private func deletePhoto() {
        RecycleBinService(storage: .shared, modelContext: modelContext).recycle(photo)
        onDelete()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// ─── 标签 chip ───
struct TagChip: View {
    let tag: Tag
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 8, height: 8)
            Text(tag.name)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Palette.chipBackground)
        .cornerRadius(Radius.lg)
    }
}

// ─── 流式布局 ───
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth {
                totalHeight += currentRowHeight + spacing
                currentRowWidth = size.width + spacing
                currentRowHeight = size.height
            } else {
                currentRowWidth += size.width + spacing
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        totalHeight += currentRowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

#Preview {
    DetailView(
        photo: Photo(
            filename: "示例.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/x.jpg"),
            fileSize: 3_200_000,
            width: 4032,
            height: 3024
        ),
        onDelete: {},
        onPrev: {},
        onNext: {},
        canPrev: true,
        canNext: true,
        currentIndex: 3,
        totalCount: 24
    )
    .frame(width: 300, height: 600)
}
