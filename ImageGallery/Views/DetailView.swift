//
//  DetailView.swift
//  ImageGallery
//
//  右侧详情面板。显示当前选中图片的大图、元数据、标签管理、删除。
//  顶部带"上一张/下一张"导航，方便连续翻看。
//

import SwiftUI
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
    @State private var showingDeleteConfirm = false
    @State private var showingRenameAlert = false
    @State private var newTagName = ""
    @State private var newFileName = ""

    var body: some View {
        // V3.5.21：详情面板卡片化 — ScrollView + VStack of cards
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // 1️⃣ 大图卡（顶部，占 50% 左右高度）
                bigImageCard

                // 2️⃣ 信息卡（文件名 + 元数据）
                infoCard

                // 3️⃣ 标签卡
                tagsCard

                // 5️⃣ 操作卡
                operationsCard

                Spacer(minLength: Spacing.md)
            }
            .padding(Spacing.lg)
        }
        .background(Surface.canvas)
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
    }

    // MARK: - 卡片组件（V3.5.21）

    /// 通用卡片容器
    private func detailCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Surface.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Surface.cardBorder, lineWidth: 0.5)
            )
    }

    /// 1️⃣ 大图卡
    private var bigImageCard: some View {
        Group {
            if let nsImage = ImageLoader.loadImage(at: photo.fileURL, maxPixelSize: 2000) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Palette.cellFilled)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 360)
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
                HStack(spacing: Spacing.sm) {
                    Text(photo.filename)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        newFileName = photo.filename
                        showingRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
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
            HStack(spacing: Spacing.md) {
                // 收藏切换
                Button {
                    photo.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: photo.isFavorite ? "star.fill" : "star")
                        Text(photo.isFavorite ? "已收藏" : "收藏")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(photo.isFavorite ? .yellow : .accentColor)

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
            }
        }
    }


    // ─── 移除标签（V3.5 Phase 2：支持撤销）───
    private func removeTag(_ tag: Tag) {
        undoManager?.registerAction(
            description: "移除标签 \(tag.name)"
        ) {
            photo.tags.removeAll { $0.id == tag.id }
            try? modelContext.save()
        } undo: {
            photo.tags.append(tag)
            try? modelContext.save()
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
            try? modelContext.save()
        } undo: {
            // 撤销：磁盘重命名回 + SwiftData 回滚
            try? FileManager.default.moveItem(at: newURL, to: oldURL)
            photo.filename = oldFilename
            photo.fileURL = oldURL
            try? modelContext.save()
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
            try? modelContext.save()
        } undo: {
            photo.tags.removeAll { $0.id == tagToAdd.id }
            try? modelContext.save()
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
