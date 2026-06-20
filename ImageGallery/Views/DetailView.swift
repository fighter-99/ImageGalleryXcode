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
    // V6.08: 错误回调 (rename 失败等) — 父视图负责 show toast
    var onError: (String) -> Void = { _ in }

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
        // V4.27.0: ScrollView 改 ScrollViewReader——切换 photo 自动滚到大图顶部
        // V4.35.0: 加顶层 GeometryReader 限 bigImageCard 高度 = visible 60%
        //   V4.30.0 失误: 顶层 GeometryReader 限高 0.55 + image 双方向 fit
        //     → image 撑满 width (500pt) + 高度限 → 拉伸右溢出
        //   V4.32.0 失误: image 内 GeometryReader 嵌套 + HStack + Spacer
        //     → Image 撑满 HStack width → 拉伸右溢出
        //   V4.34.0 失误: 撤回嵌套 + image 单方向 fit (.frame(maxWidth: .infinity))
        //     → image 撑满父 width (detail panel ~500pt)
        //     → 实际 visible width < 500pt → 右溢出被切
        // V4.35.0 修复: 顶层 GeometryReader 限高 bigImageCard 0.60 × visible
        //   + image 内 GeometryReader 读 bigImageCard 实际尺寸
        //   + image maxWidth/Height 按 bigImageCard 实际尺寸 (双方向受约束)
        //   + aspectRatio(.fit) min 缩放
        //   image 不超 detail panel 实际可见 right 边界 + 高度 ≤ bigImageCard 高度
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 1️⃣ 大图区（顶部，0 padding 紧贴 detail panel 边缘）
                        bigImageCard
                            // V4.35.0: 大图 60% × visible height——元数据 + 标签 + 操作 fit 余下
                            //   1080×1503 竖向图在 (500, 450) 容器内:
                            //   min(500, 450) = 450 → image width 324pt, height 450pt (不拉伸)
                            //   元数据 + 标签 + 操作 ≈ 300pt < 余下 300pt (visible - bigImageCard) → 整体 fit
                            .frame(height: geo.size.height * 0.60)

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
                .onChange(of: photo.id) { _, _ in
                    // V4.27.0: photo 切换时滚到大图顶部
                    withAnimation(Animations.quick) {
                        proxy.scrollTo("bigImage", anchor: .top)
                    }
                }
            }
        }
        // V4.1.0d: 改用 .regularMaterial——与侧栏、主工具栏统一
        //   整个控制区 = 半透明毛玻璃；主区 = opaque canvas（照片焦点）
        // V4.21.0: 撤回 V4.18.0 .glassEffect(.regular)——同 SidebarView
        //   macOS 26 单 view glassEffect 视觉副作用未消除
        // V4.35.x 修复: idealWidth 320 + maxWidth 400——和 columnLayout detailMin 340 协调
        //   旧仅 minWidth: 280 → 列宽可能扩到 480 但 detail panel 自身没边界 → 内容溢出
        // V6.12.4: .regularMaterial → .bar——跟 sidebar / statusBar 统一 chrome 强度
        //   4 种强度混用 (.bar/.regularMaterial/.popover/.titlebar) → 现在 3 种 (持久 chrome 全 .bar)
        .background(.bar)
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
        .alert(Copy.newTag, isPresented: $showingAddTagAlert) {
            TextField(Copy.tagNamePlaceholder, text: $newTagName)
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.create) { createAndAddTag() }
        }
        .alert(Copy.renamePhotoTitle, isPresented: $showingRenameAlert) {
            TextField(Copy.newFileNamePlaceholder, text: $newFileName)
            Button(Copy.cancel, role: .cancel) {}
            Button(Copy.confirm) { renamePhoto() }
        } message: {
            Text(Copy.renameHint)
        }
        .confirmationDialog(
            Copy.deleteConfirmTitle,
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(Copy.delete, role: .destructive) { deletePhoto() }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            // V5.51: "图馆" → "图库" typo 修复 + 走 Term.photo + Term.library 字典
            // V6.12.19: 整条 message 也入库（用 %@ 接受 Term 插值）
            Text(Copy.deletePhotoConfirmWithTerms(photo: Term.photo, library: Term.library))
        }
        // V4.16.0: 右击 detail panel 任意位置 → 复制（与 operationsCard 不重复）
        .contextMenu {
            Button {
                // NSPasteboard 复制 photo.fileURL（URL promise——接受方读原文件）
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([photo.fileURL as NSURL])
            } label: {
                Label(Copy.copyAction, systemImage: "doc.on.doc")
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
        // V4.35.x: leading 16pt / trailing 20pt——右侧多 4pt 呼吸空间
        //   旧 .padding(.horizontal, Spacing.lg) 双向 16pt → 内容右侧贴 material 右边缘显局促
        //   改不对称 padding → 内容视觉"靠左内缩"，与 material 右边缘留 4pt 空白
        //   保持 detail panel material 满宽贴窗口边（Photos 风格），仅内容内缩
        content()
            .padding(.leading, Spacing.lg)     // 16pt
            .padding(.trailing, Spacing.xl)    // 20pt
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 1️⃣ 大图卡
    private var bigImageCard: some View {
        Group {
            if let nsImage = bigImage {
                // V4.35.0: 加 GeometryReader 读 bigImageCard section 实际尺寸
                //   V4.34.0 失误: image .frame(maxWidth: .infinity) 单方向 fit
                //   image 撑满父 width (detail panel 可见 width ~500pt)
                //   但 detail panel 实际 visible width < 500pt (被 toolbar / status bar 占)
                //   → image 渲染 width > visible width → 右溢出被切
                // V4.35.0 修复: image 用 GeometryReader 读 bigImageCard section 实际尺寸
                //   .frame(maxWidth: cardGeo.size.width, maxHeight: cardGeo.size.height)
                //   + aspectRatio(.fit) 按 min(width, height) 缩放
                //   bigImageCard section 实际 (detail panel 可见 width, 0.60 × visible height)
                //   1080×1503 竖向图: min(width, height) 按 bigImageCard 实际尺寸算
                //   image 不超 detail panel 右边界 + 不拉伸
                GeometryReader { cardGeo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: cardGeo.size.width, maxHeight: cardGeo.size.height)
                        .id("bigImage")
                }
            } else if bigImageLoadFailed {
                // V4.9.5: 加载失败——显示 photo 占位 + 错误 icon
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Palette.cellFilled)
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .font(Typography.emptyStateIcon)
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
            HStack(spacing: 0) {
                detailNavButton(systemName: "chevron.left", help: Copy.detailPrevHelp) {
                    onPrev()
                }
                .disabled(!canPrev)
                .opacity(canPrev ? 0.9 : 0.3)

                Spacer(minLength: 0)

                if totalCount > 0 {
                    Text(Copy.photoPosition(current: currentIndex, total: totalCount))
                        .font(Typography.captionMono)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        // V4.21.0: 撤回 .glassEffect——macOS 26 单 view 视觉副作用
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer(minLength: 0)

                detailNavButton(systemName: "chevron.right", help: Copy.detailNextHelp) {
                    onNext()
                }
                .disabled(!canNext)
                .opacity(canNext ? 0.9 : 0.3)
            }
            .frame(maxWidth: .infinity)  // 关键: 让 Spacer 撑开,索引居中,左/右按钮贴边
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
                .font(Typography.detailLabel)
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
                        .font(Typography.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        newFileName = photo.filename
                        showingRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(Typography.body)
                    }
                    .buttonStyle(.borderless)
                    .help(Copy.renamePhotoTitle)
                    .fixedSize()  // 不被 Spacer 挤压
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
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            if mono {
                Text(text)
                    .font(Typography.captionMono)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(Typography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 4️⃣ 标签卡
    private var tagsCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(Copy.tagLabel)
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        newTagName = ""
                        showingAddTagAlert = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(Typography.body)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .help(Copy.addTag)
                }

                if photo.tags.isEmpty {
                    HStack {
                        Image(systemName: "tag")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                        Text(Copy.addTagHint)
                            .font(Typography.caption)
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
    /// V5.8: 加 5 颗 ⭐ 点选条——单张照片视图直接评分
    ///   - 取代 V5.7 砍掉的"收藏"按钮——收藏 = 评分 ≥ 5
    ///   - 点击第 N 颗 → photo.rating = N；再点同一颗 → photo.rating = 0
    ///   - 视觉：实心 N 颗（systemYellow）+ 空心 (5-N) 颗（secondaryLabelColor）
    ///   - 比右键菜单 → 评分 → 1 星 快捷 3 步
    /// V5.7: 砍"收藏"和"在 Finder 中显示"两个按钮
    ///   只保留"删除"——最关键的危险操作必须显眼
    private var operationsCard: some View {
        detailCard {
            VStack(spacing: Spacing.md) {
                // V5.8: 5 颗 ⭐ 点选条
                ratingPickerRow
                // V5.7: 3 按钮 → 1 按钮（删除）——单按钮 fullWidth 占满
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(Copy.delete)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// V5.11 升级: 5 颗 ⭐ 点选条 macOS Photos 风格——hover 预览 + 视觉分层
    ///   - 实心 N 颗 (systemYellow) + 空心 (5-N) 颗 (Color.secondary.opacity(0.5))
    ///   - hover 预览: 鼠标悬停 N 颗 → 这 N 颗也显示填充（预览将要设置的评分）
    ///   - 整体高度增加 6pt: padding(.vertical, 4) → padding(.vertical, 8)——更舒展
    ///   - star 字号 22pt medium weight——比 .title2 略重，与按钮视觉一致
    ///   - label 字号 .callout → .caption2——更 subtle
    ///   仿 Photos.app 评分 popover 视觉锤
    private var ratingPickerRow: some View {
        HStack(spacing: Spacing.sm) {
            RatingStarsView(
                rating: photo.rating,
                onSet: { newRating in
                    photo.rating = newRating
                    modelContext.saveWithLog()
                }
            )
            Spacer()
            Text(photo.rating > 0 ? Copy.ratingStars(photo.rating) : Copy.detailNoRating)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }


    // ─── 移除标签（V3.5 Phase 2：支持撤销）───
    private func removeTag(_ tag: Tag) {
        undoManager?.registerAction(
            description: Copy.undoRemoveTag(tag.name)
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
            description: Copy.undoRename(trimmed)
        ) {
            // V6.08: 文件 rename 失败不能静默——之前 try? + 写 SwiftData → 孤儿文件
            //   失败: 不更新 photo.filename/fileURL, 弹 toast 通知用户
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                photo.filename = trimmed
                photo.fileURL = newURL
                modelContext.saveWithLog()
            } catch {
                onError(Copy.renameFailed(trimmed))
            }
        } undo: {
            // 撤销：磁盘重命名回 + SwiftData 回滚
            do {
                try FileManager.default.moveItem(at: newURL, to: oldURL)
                photo.filename = oldFilename
                photo.fileURL = oldURL
                modelContext.saveWithLog()
            } catch {
                // 撤销失败: 文件状态跟 SwiftData 不一致——只能提示用户
                onError(Copy.renameFailed(oldFilename))
            }
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
            description: Copy.undoAddTag(tagToAdd.name)
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

// MARK: - V5.11: RatingStarsView 5 颗 ⭐ hover 预览组件

/// V5.11: 5 颗 ⭐ 点选条私有组件——macOS Photos 风格 hover 预览
///   - 5 颗 22pt medium weight ⭐ 横向排列
///   - hover 预览: @State 追踪鼠标位置——hover 到的星也显示填充（预览）— macOS Photos 同款
///   - 视觉:
///     - 实心 N 颗 (systemYellow) = max(rating, hoverRating) 之内的星
///     - 空心 (5-N) 颗 = Color.secondary.opacity(0.5)——比 V5.8 浅，更不抢眼
///   - 点击: 切换 rating——同星再点归 0（清除）
///   - 性能: @State 局部，hoverRating 变化只触发本 view 重绘
private struct RatingStarsView: View {
    let rating: Int
    let onSet: (Int) -> Void

    @State private var hoverRating: Int = 0
    // V6.32.2: 暗色模式感知 — unfilled star opacity
    @Environment(\.colorScheme) private var colorScheme

    /// V6.32.2: 暗色下 unfilled star 用 0.65 (跟 filled yellow 形成对比)
    /// 浅色 0.5 (跟 Color.secondary 拉开)
    private var unfilledStarColor: Color {
        colorScheme == .dark ? Color.secondary.opacity(0.65) : Color.secondary.opacity(0.5)
    }

    /// 显示的填充范围——max(rating, hoverRating)
    /// hover 时 hoverRating > rating，星星被"推"过去，预览效果
    /// V5.13：抽到 RatingStarsMath.displayedRating 便于纯函数测试
    private var displayedRating: Int {
        RatingStarsMath.displayedRating(current: rating, hover: hoverRating)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    // 同星再点归 0（清除）——V5.8 行为不变
                    // V5.13：抽到 RatingStarsMath.nextRating 便于纯函数测试
                    onSet(RatingStarsMath.nextRating(after: n, current: rating))
                } label: {
                    Image(systemName: n <= displayedRating ? "star.fill" : "star")
                        .font(Typography.detailCount)
                        .foregroundStyle(n <= displayedRating ? Color.yellow : unfilledStarColor)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    // 鼠标进入该星 → hoverRating = n（覆盖至 N）
                    // 鼠标离开该星 → hoverRating = 0（恢复 actual rating）
                    hoverRating = isHovered ? n : 0
                }
                .help(n <= rating ? Copy.ratingCurrent(n) : Copy.ratingSetTo(n))
            }
        }
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
                .font(Typography.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(Typography.caption)
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
