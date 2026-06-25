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
    @Environment(\.modelContext) var modelContext
    @Environment(\.undoManager) var undoManager  // V3.5 Phase 2

    // 所有标签
    @Query(sort: \Tag.createdAt, order: .forward) var allTags: [Tag]

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
    // V6.XX: 搜索结果高亮——接收搜索文本，文件名匹配时用 accent 色标记
    var searchText: String = ""
    // V6.111.4: 沉浸式 drawer 模式 — 隐藏 bigImageCard (大图跟 immersive 左侧大图 100% 重复)
    //   Photos.app Sonoma+ 真版: immersive drawer 只显示元数据 (文件名/EXIF/评分/标签/操作)
    //   不再显示缩略图 — 视觉锤"看图用左侧大图, info 用右侧 drawer"明确分工
    //   默认 false 保留 grid 详情面板的现有行为 (大图 60% + 元数据 40%)
    var hideBigImage: Bool = false

    // 弹窗控制
    @State var showingAddTagAlert = false

    // V4.9.5: 大图 async 加载——避免同步 IO 阻塞主线程
    //   .task(id: photo.id) 自动取消旧任务，photo 变化时重载
    @State var bigImage: NSImage?
    @State var bigImageLoadFailed: Bool = false
    @State var showingDeleteConfirm = false
    @State var showingRenameAlert = false
    @State var newTagName = ""
    @State var newFileName = ""
    // V6.58 (audit P1.3): renameTarget 在 alert-open 时 capture 当前 photo,
    //   避免 ← → 切换 photo 后 newFileName 还指向旧照片导致 rename 错照片
    @State var renameTarget: Photo? = nil

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
        // V6.52 (design polish): 删 3 个内 Divider — V4.24.0 注释说 "sections 间 Divider 分隔",
        //   实际造成 4 个 section 看起来像平级. Photos 真版无内 Divider, 靠 Spacing.lg 自然分组
        //   现在: 大图 (60%) + spacing.lg + [info+tags+operations] 1 个 VStack 内部 spacing.md
        VStack(alignment: .leading, spacing: 0) {
            // 1️⃣ 大图区（layoutPriority 让图片占满可用空间，元数据区自然高度）
            // V6.111.4: immersive drawer 模式跳过 bigImageCard — 跟左侧 immersive 大图 100% 重复
            //   Photos.app Sonoma+ 真版: drawer 只显示元数据, 不重复图片
            if !hideBigImage {
                bigImageCard
                    .layoutPriority(1)
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                // 2️⃣ 信息区（文件名 + 元数据）
                infoCard

                // 3️⃣ 标签区
                tagsCard

                // 4️⃣ 操作区
                operationsCard
            }
            // V6.111.4: immersive drawer 模式无大图, 不需要 .padding(.top) 给 bigImage 留空间
            //   之前 .padding(.top, Spacing.lg) 是因为大图下方紧贴元数据, 需要呼吸空间
            //   现在无大图, 元数据直接顶到 drawer 顶部 — 视觉上元数据成为 drawer 主内容
            .padding(.top, hideBigImage ? 0 : Spacing.lg)
            // V6.111.4: immersive drawer 模式元数据需要更多水平 padding — Photos 风格 16pt
            //   grid 主视图 detail panel 已经有 V4.x 系列 padding 处理, 不用动
            .padding(.horizontal, hideBigImage ? Spacing.lg : 0)
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
    func detailCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
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

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        // V6.52 (i18n bug fix): 之前 hardcode "zh_CN" 让英文用户看中文日期格式
        //   现在用 .autoupdatingCurrent 走系统 locale — en/zh-Hans/zh-Hant 都正确
        formatter.locale = .autoupdatingCurrent
        return formatter.string(from: date)
    }

    func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
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
