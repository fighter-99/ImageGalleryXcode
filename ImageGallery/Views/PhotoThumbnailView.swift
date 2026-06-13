//
//  PhotoThumbnailView.swift
//  ImageGallery
//
//  V4.36.0: 接受 cellSize (column width) + 内部按 photoAspectRatio 算 cellHeight
//    旧 cellHeight 固定 170pt → 竖向照片上下留白 / 横向照片左右留白
//    新 cellHeight = cellSize / aspectRatio → image 完全填满 cell 无留白
//
//  V5.16: 改 cellSize → cellWidth + rowHeight（masonry 外部算好）
//    旧公式 cellHeight = cellSize / aspectRatio → 行底部参差（截图 23）
//    新 row 高度统一 = rowHeight，cell 宽度 = rowHeight × photo.aspectRatio
//    MasonryRow 算好每行 cell 宽传入——行内 cell 高齐
//
//  V4.39.0: 从 PhotoGridView.swift 拆出独立文件
//    PhotoGridView 1180 → 580 行（V4.10.0 ContentView 拆分模式延续）
//    PBXFileSystemSynchronizedRootGroup 自动同步——无需改 pbxproj
//
//  整个文件是单个缩略图 cell 的完整渲染：图片 + 选中视觉 + 收藏星标 +
//  回收站天数 badge + 多选 ✓ + contextMenu + 拖拽 + tooltip + hover 缩放
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// ─── 单个缩略图 ───
struct PhotoThumbnailView: View {
    let photo: Photo
    let isInMultiSelect: Bool  // 是否在多选集合中
    let isActive: Bool          // 是否是当前单选激活（蓝色边框）
    let folders: [Folder]
    let allTags: [Tag]
    // V5.16: 删 cellSize 改 cellWidth + rowHeight（masonry 布局外部算好）
    //   旧 cellHeight = cellSize / aspectRatio 导致行底部参差（截图 23）
    //   新 cell 形状 = (cellWidth, rowHeight)，cellWidth = rowHeight × photo.aspectRatio
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    // V3.6.6: 保留时长（用于显示 trash 视图下的剩余天数 badge）
    let retentionDays: Int

    let onDelete: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme  // V3.6.14: 暗色适配 trash opacity
    // V4.4.0 NEW: Reduced Motion 适配——禁用 hover scale / 选中 scale 等动画
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeleteConfirm = false
    @State private var isHovered = false
    // V3.6.10: 键盘聚焦状态（SwiftUI 默认 focus ring，但 macOS 上系统不显示时手动加）
    @FocusState private var isFocused: Bool
    // V3.6.26: 异步缩略图加载状态（避免主线程阻塞）
    @State private var loadedImage: NSImage?
    // V4.4.0 NEW: 加载失败标记——区分"还在加载"vs"加载失败"
    @State private var loadFailed = false

    /// V3.6.6: 距离永久删除的剩余天数（nil = 未在回收站）
    private var daysLeft: Int? {
        PhotoStats.daysUntilPurge(trashedAt: photo.trashedAt, retentionDays: retentionDays)
    }

    /// V4.1.0 NEW: 剩余天数 badge 颜色编码
    /// - ≤3 天：红色（危险，永久删除迫近）
    /// - 4-7 天：橙色（提醒）
    /// - 8-14 天：黄色（注意）
    /// - >14 天：灰色（正常）
    private struct BadgeColor {
        let foreground: Color
        let background: Color
    }

    private func daysLeftBadgeColor(days: Int) -> BadgeColor {
        if days <= 3 {
            // V4.22.0: 暗色模式审计——badge 红/黄/橙硬编码改 token
            //   .red → Palette.destructive (已有 Surface.destructive 桥接)
            //   .orange → 保留 (无 token, 一次性使用)
            //   .yellow → Surface.favorite (已有 token)
            return BadgeColor(foreground: .white, background: Palette.destructive)
        } else if days <= 7 {
            // V4.22.0: 暗色模式审计——badge 颜色 token 化
            //   警告色保留 Color.orange (无 token, 一次性使用)
            return BadgeColor(foreground: .white, background: Color.orange)
        } else if days <= 14 {
            return BadgeColor(foreground: .primary, background: Surface.favorite.opacity(0.85))
        } else {
            // V4.22.0: 暗色模式审计——背景已用 .controlBackgroundColor 系统色
            //   自动适配亮/暗模式——保留
            return BadgeColor(foreground: .primary,
                              background: Color(nsColor: .controlBackgroundColor).opacity(0.9))
        }
    }

    /// V3.6.10: 缩略图 hover 时显示的 tooltip（文件名 + 尺寸 + 文件大小）
    private var tooltipText: String {
        var parts: [String] = [photo.filename]
        if photo.width > 0 && photo.height > 0 {
            parts.append("\(photo.width) × \(photo.height)")
        }
        if photo.fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: photo.fileSize, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    /// V3.6.51: 重构——选中状态机
    /// 之前 isActive 和 isInMultiSelect 两个独立 bool 各自驱动 3-4 个 modifier，
    /// 多个独立动画叠加产生'双层边框'错觉（用户多次反馈'先浅框再深蓝'）
    /// 现在统一为单一 CellSelectionState enum，单一来源
    enum CellSelectionState {
        case none       // 默认
        case single     // isActive 单选
        case multi      // isInMultiSelect 多选

        var borderWidth: CGFloat {
            switch self {
            case .none:   return 0      // 一直绘制 lineWidth=0 时不显示
            case .single, .multi: return 3  // 单选和多选都用 3pt（视觉一致）
            }
        }

        var borderColor: Color {
            switch self {
            case .none:   return .clear
            case .single, .multi: return Palette.selectionBorder
            }
        }

        var showsCheckmark: Bool {
            self == .multi
        }
    }

    private var selectionState: CellSelectionState {
        if isActive { return .single }
        if isInMultiSelect { return .multi }
        return .none
    }

    /// V4.4.3: 选中态时 hover shadow 让位（避免选中后 shadow 形成「浅框」）
    ///   hover shadow（Elevation.strong, radius 12pt）只在 hover-未选中时显示
    ///   选中态已用 accent 边框指示，无需 shadow 再"喊一遍"
    private var shadowShowsHover: Bool {
        isHovered && !isActive && !isInMultiSelect
    }

    /// V3.6.35: 当前缩放比例（按压 scale 撤销，hover > 选中 > 默认）
    /// V3.6.47: scale priority 修——选中 1.025 > hover 1.02
    ///   之前选中 1.015 < hover 1.02，点击 cell 反而变小（反 UX）
    /// V4.4.0: Reduced Motion 时所有 scale 强制 1.0（accessibility）
    private var currentScale: CGFloat {
        if reduceMotion { return 1.0 }            // V4.4.0: accessibility
        // V4.1.0 C: hover 从 1.025 → 1.01（更微妙——"凸起"而非"放大"）
        if isActive { return 1.015 }              // 单选：放大 1.5%（之前 2.5%）
        if isHovered && !isInMultiSelect { return 1.01 }  // hover：放大 1%
        return 1.0
    }

    /// V3.6.51: cell 选中视觉的单一 overlay（之前散在 3 个 overlay modifier）
    /// - 边框（单选 + 多选共用 lineWidth=3、Palette.selectionBorder，opacity 0/1）
    /// - ✓ checkmark（仅 multi）
    /// 不再有多选时的 selectionOverlayMulti 染色（V3.6.50 之前反复被误读为"淡色框"）
    /// V4.4.0: cornerRadius 从 Radius.md (8pt) → Radius.thumb (6pt)
    /// V4.4.1: `.stroke` → `.strokeBorder` 修「浅框」幽灵
    ///   `.stroke(lineWidth: 3)` 是 center-aligned——外侧 1.5pt 飞出 cell 圆角范围
    ///   在直线段 vs 圆角处厚度不一致（圆角处变薄、直线段变厚），且飞出部分
    ///   在 grid spacing 上显成"细蓝边"。
    ///   `.strokeBorder` 完全在 path 内绘制 → 边框完全在 cell 内，无飞出无几何错位
    @ViewBuilder
    private var cellSelectionOverlay: some View {
        let state = selectionState
        ZStack {
            RoundedRectangle(cornerRadius: Radius.thumb)
                .strokeBorder(state.borderColor, lineWidth: state.borderWidth)
            if state.showsCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.background).padding(3))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    private var aspectRatio: CGFloat {
        if photo.width > 0 && photo.height > 0 {
            return CGFloat(photo.width) / CGFloat(photo.height)
        }
        return 1.0
    }

    var body: some View {
        // V3.6.34: capture @Model 属性到 local（避免 payload 闭包在 background thread 访问）
        //   详见 .draggable 注释
        let capturedFileURL = photo.fileURL
        let capturedPreviewImage = loadedImage
        return ZStack(alignment: .topTrailing) {
            // V4.4.4: 删除 CheckerboardBackground——这就是「浅框」幽灵的真正源头
            //   V4.4.0 引入 checker 想"为透明 PNG 提供视觉边界"，但 99% 图片是 JPG
            //   不透明 → 图片 fit 留白处显示 checker → 每张图周围一圈棋盘格
            //   远看时棋盘格平均化变成浅灰色 = 用户感知的「浅框」（每张图都有）
            //   Mac Photos.app / Finder 都不显示 checker，透明区显示 cell 背景色即可
            //   ThumbnailEffects.CheckerboardBackground 仍保留，未来若做透明检测可重用

            // 图片（垂直居中 + 按原比例）
            // V3.6.8: trash 视图下加灰度 + 降低不透明度，让"已删除"感更强
            // V3.6.14: 暗色下 opacity 0.65（暗背景下半透明不会"黑掉"）
            // V3.6.26: 改用 .task + 异步加载，主线程不阻塞
            // V4.4.0: 三态 → 加载中 (shimmer 骨架) / 加载失败 (exclamationmark) / 已加载 (Image)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if let nsImage = loadedImage {
                        // V4.23.0: 完整 Photos 风格——image 加 .clipShape 圆角
                        //   之前 cell .cornerRadius 是无意义修饰（image 自身无圆角）
                        //   现在圆角仅给 image clip，cell 自身完全透明
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                            .saturation(photo.isInTrash ? 0.05 : 1)
                            .opacity(photo.isInTrash ? (colorScheme == .dark ? 0.65 : 0.55) : 1)
                    } else if loadFailed {
                        // V4.4.0: 加载失败——明确指示 + 灰底
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.title3)
                                    Text("加载失败")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                    } else {
                        // V4.4.0: 加载中——shimmer 骨架替静态 photo icon
                        //   滚动到新位置时不再"灰图标闪烁"
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .shimmer()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // V3.6.26: 异步加载缩略图（缓存命中立即返回；未命中后台线程解码）
            // V4.4.0: 加载失败时 set loadFailed=true（loadImageAsync 返回 nil 视为失败）
            // V5.17: 600→1200 retina 优化（HiDPI 屏 200pt cell 锐化）
            //   1200px 源 = 3x 下采样仍锐（Photos.app 内部 1000-2000px 缓存）
            //   内存 1200²×4 = 5.76MB/cell；NSCache 400MB (V5.17 ↑) + LRU 自动驱逐
            .task(id: photo.id) {
                loadFailed = false
                let img = await ImageLoader.loadImageAsync(
                    at: photo.fileURL,
                    maxPixelSize: 1200
                )
                if img == nil {
                    loadFailed = true
                } else {
                    loadedImage = img
                }
            }

            // V4.4.0: 删除 isInMultiSelect 时的 16% accent 蒙层
            //   V3.6.51 注释说"删了"但代码仍在；选中状态靠 cellSelectionOverlay
            //   的 3pt accent 边框 + checkmark 角标已足够，无需整图染色

            // V5.7: 砍收藏星标 badge——收藏 = 评分 ≥ 5 走筛选 popover
            //   缩略图左上角不再显示 ⭐——视觉更纯净，评分通过筛选可达

            // V3.6.6: 回收站剩余天数 badge（仅 trash 视图下显示）
            // V4.1.0: 颜色编码——≤3 红 / 4-7 橙 / 8-14 黄 / >14 灰
            // topLeading 不与右上角的多选 ✓ / 左上角的 star 冲突
            if let days = daysLeft, photo.isInTrash {
                let badgeColor = daysLeftBadgeColor(days: days)
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(days)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(badgeColor.foreground)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(badgeColor.background)
                )
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // 多选 ✓ 圆点
            // V3.6.38: 加 .animation 触发 transition（之前 transition 写了但没 animation 所以不生效）
            if isInMultiSelect {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(
                        Circle().fill(.background).padding(3)
                    )
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // V3.6.45: 选中（isInMultiSelect）用 standard（0.2s easeInOut）——springGentle 0.35s 太慢
        //   多选点击是高频操作，spring 反弹感在选择场景下反而像'卡顿'
        .animation(Animations.standard, value: isInMultiSelect)
        .frame(maxWidth: .infinity)
        // V5.16: cell 形状 = (cellWidth, rowHeight)——外部 MasonryRow 算好传入
        //   cellWidth = rowHeight × photo.aspectRatio → image 完全 fill cell 无留白
        //   行内所有 cell 高齐 rowHeight（行底部无 jagged）
        .frame(width: cellWidth, height: rowHeight)
        // V4.4.5: cell 背景 controlBackgroundColor → windowBackgroundColor
        //   ↑ 终于找到「浅框」真正源头——cell 背景比窗口背景浅一档
        //   旧 Palette.cellBackground = Surface.elevated = controlBackgroundColor ≈ #2C2C2C
        //   窗口背景 windowBackgroundColor ≈ #1E1E1E
        //   每个 cell 在深窗口上 = 浅灰圆角矩形 = 用户感知的「浅框」
        //   现在 cell 与窗口同色，cell 容器感完全消失，只剩"漂浮的图片"
        //   视觉分隔靠 grid spacing（间距本身）+ cornerRadius clip（图片圆角）
        //   这是 Mac Photos.app 标准做法
        //
        // V4.23.0: 完整 Photos 风格——删 cell 背景 + 删 cell 圆角
        //   ↑ 进一步推到 Photos.app 真正的"无背景卡片"风格
        //   cell 完全透明——无 background、无 cornerRadius（image 自身圆角已够）
        //   视觉分隔仅靠 grid spacing (Spacing.sm 8pt) + image clip 圆角 (Radius.thumb 6pt)
        //   对比 V4.4.5 半 Photos 风格：V4.4.5 cell 仍与窗口同色"圆角矩形"
        //   V4.23.0 cell 完全透明——只剩"漂浮的圆角图片"
        //   删 .clipped() (原为与 .cornerRadius 配合)——image 自身 clip 足够
        // V3.6.51: 重构——单一 cellSelectionOverlay 取代之前散在 3 个 overlay modifier
        //   之前：3pt 单选 border（独立 modifier） + 2pt 多选 border（独立 modifier）
        //        + 多选 selectionOverlayMulti 染色（用户多次反馈的'淡色框'，V3.6.50 没真删干净）
        //   现在：单一 overlay 由 selectionState enum 驱动，单一 .animation(value: selectionState)
        //   状态切换时所有视觉元素（边框 + ✓）一起淡入淡出，无'先后'错觉
        //   V3.6.51 也彻底删除 selectionOverlayMulti 染色（16% accent 太显眼被读成'浅框'）
        .overlay(cellSelectionOverlay)
        // V3.6.35: 缩放优先级 选中 (1.025) > hover (1.02) > 默认
        //   按压 0.95 scale 撤销（避免跟 .draggable 抢事件）
        .scaleEffect(currentScale)
        // V4.4.2: 删除 resting shadow——这就是「浅框」幽灵的真正源头
        //   V3.1 引入「始终浮起感」: resting Elevation.subtle (radius=2, y=1, opacity=0.08)
        //   但 shadow 在 cell 四周扩散 2pt，在浅色 grid 间距上呈现为"一圈淡色光晕"
        //   = 用户感知的「浅框」（每个 cell 都有，无论选中与否）
        //
        // V4.4.3: hover shadow 与选中态互斥——「选中后的浅框」真凶
        //   用户点击 cell = 必然 hover → 选中后 isHovered=true → Elevation.strong
        //   shadow（12pt radius + 0.20 opacity）在 accent 边框周围扩散 12pt
        //   = 用户感知的「选中后出现的浅框」
        //   设计原则：选中已用 accent 边框明确指示，shadow 是 hover 反馈，
        //   选中时让 shadow 让位（!isActive && !isInMultiSelect 才显示）
        .shadow(
            color: shadowShowsHover ? Elevation.strong.color : .clear,
            radius: shadowShowsHover ? Elevation.strong.radius : 0,
            x: 0,
            y: shadowShowsHover ? Elevation.strong.y : 0
        )
        // V3.6.51: 单一 .animation 驱动所有选中状态过渡（之前 3 个独立 modifier）
        .animation(Animations.standard, value: selectionState)
        .animation(Animations.springGentle, value: isHovered)
        .animation(Animations.springGentle, value: isFocused)
        // hover 检测（仅用于缩放动画）
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())  // 让空白处也响应点击
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        // V3.6.10: 键盘聚焦绑定（方向键导航时高亮）
        // V4.4.6: focusEffectDisabled(false) → true ——「点击后浅框」真凶
        //   旧 V3.6.10 显式启用系统 focus ring 给键盘导航视觉
        //   但鼠标点击也会触发 focus → 系统淡蓝发光环显示在 cell 周围
        //   = 用户看到的「点击后的浅框」
        //   选中状态已用 3pt accent strokeBorder 明确指示，再叠 focus ring 是双重视觉
        //   键盘导航可用 selectionState (selectedIDs/singleSelectedID) 体现，无需系统 ring
        .focused($isFocused)
        .focusable(true)
        .focusEffectDisabled(true)  // V4.4.6: 禁用系统 focus ring
        // V3.6.40: hover 动画升级 .standard → .springGentle（按压更"Q弹"感）
        // scaleEffect(currentScale) 在前面
        // animation 之前是 Animations.standard，现改 spring
        // 删除重复 .animation 块
        // V3.6.10: hover tooltip（文件名 + 尺寸 + 文件大小）
        .help(tooltipText)
        // 拖拽：支持内部文件夹移动 + 拖到 Finder 导出原图
        // V3.6.33: 迁移到 .draggable(URL) 现代 API
        //   - 旧 .onDrag + NSItemProvider 在 macOS 26.5 下行为异常（V3.6.27-V3.6.32 4 种 drag 全部失效）
        //   - .draggable + .dropDestination 是 SwiftUI 13+ 推荐的拖拽 API 对
        //   - URL 自带 Transferable，自动注册 public.file-url，Finder 直接拷原图
        //   - Sidebar 用 .dropDestination(for: URL.self) 接收后按 fileURL 查 photo
        //
        // V3.6.34: 关键修复
        // ─────────────────────────────────────────────────────────
        // .draggable 的 payload 是 @autoclosure @escaping，drag-start 时才求值
        // macOS 26.5 上 drag-start 可能在 background thread，SwiftData @Model
        // 属性访问（photo.fileURL）要求 main thread，会拿到 stale data 或失效
        // 修复：把 SwiftData @Model 属性 capture 到 local let，payload 闭包只
        // 返回已捕获的 URL 值（值类型，thread-safe），不再访问 @Model
        // preview 闭包里的 loadedImage (@State) 同理
        // 验证：用户用 10 行 .draggable 测试 view work，但 ImageGallery 不 work
        // → 区别就是 ImageGallery 用了 SwiftData @Model 属性作 payload
        // ─────────────────────────────────────────────────────────
        //
        // V3.6.30: 拖出语义决策
        // 本 .draggable 编码的是"被拖的那张"原图，**不**展开到整个 selectedIDs。
        // 这与 computeDragReorder 的"展开到整组"语义形成对比——
        // 本路径走 Finder 导出，单图语义与 Photos.app 一致：
        //   多选状态下拖任意一张 = 导出那一张（不是整组一起导出）
        .draggable(capturedFileURL) {
            // 拖动预览：缩略图（用已加载的 capturedPreviewImage 避免重读盘 + @State 访问）
            // V3.6.42: 加 shadow + 边框 + 放大到 96 + 旋转 1°（"被拿起"感）
            // V4.4.0: Radius.md → Radius.thumb 与 cell 本体圆角统一
            ZStack {
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Palette.cellBackground)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    )
                if let nsImage = capturedPreviewImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .rotationEffect(.degrees(1))  // 微旋转加强"被拿起"感
        }
        // V3.6.37: 把 contextMenu + confirmationDialog 抽到独立 view
        //   原因：cell 主体 + 30+ modifier + 这两个复杂 modifier 让 Swift 编译器 type-check 超时
        //   V3.6.17/V3.6.23 教训：ContentView 110+ 行也踩过同样的坑
        //   解决：拆子 view，Swift 编译器每个 view 独立 type-check
        .background(
            EmptyView()
        )
        .modifier(CellContextMenuModifier(
            photo: photo,
            folders: folders,
            allTags: allTags,
            modelContext: modelContext,
            toggleTag: toggleTag,
            showingDeleteConfirm: $showingDeleteConfirm,
            onDelete: onDelete
        ))
        .confirmationDialog(
            "确定要删除这张图片吗？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("图片将从图库中移除，文件也会被永久删除。")
        }
    }

    private func toggleTag(_ tag: Tag, on photo: Photo) {
        if let index = photo.tags.firstIndex(where: { $0.id == tag.id }) {
            photo.tags.remove(at: index)
        } else {
            photo.tags.append(tag)
        }
        modelContext.saveWithLog()
    }
}
