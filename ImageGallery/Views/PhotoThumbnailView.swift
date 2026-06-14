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
    // V5.30: 删 @Environment(\.accessibilityReduceMotion) reduceMotion
    //   - 之前 V4.4.0 加, 配合 currentScale (V5.28-4 已删)
    //   - 唯一消费点 currentScale 删了, reduceMotion 也成 dead
    @State private var showingDeleteConfirm = false
    // V5.30: 删 isHovered state——V5.28-4 砍 hover scale/border/shadow 后, 状态无消费者
    //   之前 V5.23-2 加 isHovered 驱动 1.005 scale + 1pt border
    //   V5.28 "无悬停动效" 后, isHovered 仅被 .onHover 写, 无任何读
    //   纯 dead state, 删——遵循 V4.62.0 代码收敛
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
    /// V5.17: 砍 3pt 粗边框改 Photos.app 风格——cell-wide tint + ✓ 角标
    ///   V4.4.0 教训：之前 16% accent overlay 蒙层被砍"浅框"——降到 0.10 + cell 背景 fill 而非 overlay
    ///   V4.4.1 教训：.strokeBorder 而非 .stroke——本 commit 直接不用 border
    ///   收敛视觉锤：border=0（砍）+ tint 0.10/0.15（1 锤）+ ✓ 角标（多选时 1 锤）= 1-2 锤
    /// V5.19: 内 cell 2pt padding——Photos.app "framed photo" 风格
    /// V5.20: 2pt → 4pt padding——用户反馈"图片没被抱着"，4pt 留白更明显
    /// V5.27: 4pt → 0pt——macOS Photos.app Library 实际无 inner padding
    /// V5.28: 0pt 保持——letterbox 透窗口色 + aspect-fill 裁切
    static let innerCellPadding: CGFloat = 0
    enum CellSelectionState {
        case none       // 默认
        case single     // isActive 单选
        case multi      // isInMultiSelect 多选

        /// V5.17: 0 border 改 subtle tint
        /// V5.26: 1.5pt border 回归——单选态 tint + border = 2 锤视觉
        /// V5.27: 砍 border——误判为 macOS Photos Library 选中无 border
        ///   - 之前我以为 Photos 选中无 border, 实际选中态有蓝色边框
        ///   - V5.28: 加回 border, 单选/multi 都显示 (multi 还多 ✓ 角标)
        ///   - 单选/multi 1 锤 (border) / multi 2 锤 (border + ✓)
        /// V5.28: 砍 tint (0.10/0.15)——只 border + (multi 加 ✓), 极简
        var borderWidth: CGFloat {
            switch self {
            case .none:   return 0
            case .single: return 2   // V5.31: 3 → 2 (subtle, Photos 真版细线)
            case .multi:  return 2   // V5.31: 多选也 2pt (subtle, 加 ✓ 角标变 2 锤)
            }
        }

        /// V5.28: 砍 tint (V5.17 0.10, V5.27 0.10)——只 border, 无 tint
        ///   - Photos.app 真版: 选中态仅 border, 无 tint 蒙层
        ///   - 1 锤总视觉 (border 或 border+✓)
        var tintOpacity: Double {
            switch self {
            case .none:   return 0
            case .single: return 0    // V5.28: 砍 tint, 只留 border
            case .multi:  return 0    // V5.28: 砍 tint, 只留 border + ✓
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
    /// V4.4.3: V5.28 删 hover shadow——"无悬停动效" (Photos 真版)
    //   之前 shadowShowsHover + Elevation.strong 都是 iOS Photos 痕迹
    //   macOS Photos.app Library cell hover 无任何视觉反馈
    // V3.6.35: 当前缩放比例（按压 scale 撤销，hover > 选中 > 默认）
    /// V3.6.47: scale priority 修——选中 1.025 > hover 1.02
    /// V4.4.0: Reduced Motion 时所有 scale 强制 1.0（accessibility）
    /// V5.17: 砍 hover scale 1.01 / 选中 1.015（V4.62.0 教训"3 重视觉锤 = 累赘"）
    /// V5.23: hover scale 1.005 回归（V5.17 砍后 cell 鼠标划过无反应）
    /// V5.28: 砍 hover scale + hover border——"无悬停动效" (Photos 真版)
    ///   - macOS Photos.app Library hover 完全无视觉反馈
    ///   - 选 1 张图 = 仅 border, hover 任何 cell = 无任何变化
    ///   - 删除 currentScale 属性 + .scaleEffect + .animation(.springGentle, value: isHovered)
    // V5.28: currentScale 整段删——hover 无视觉反馈

    /// V3.6.51: cell 选中视觉的单一 overlay（之前散在 3 个 overlay modifier）
    /// V5.17: 砍 3pt 粗边框（state.borderWidth 0）改 cell-wide tint
    ///   RoundedRectangle.fill(Color.accentColor.opacity(state.tintOpacity))
    ///   0.10 (single) / 0.15 (multi) 系统 accent 自适应
    ///   V4.4.0 教训：之前 16% accent overlay 蒙层被砍"浅框"——降到 0.10 + cell 背景 fill 而非 overlay
    ///   V4.4.1 教训：.strokeBorder 而非 .stroke——本 commit 直接不用 border
    ///   视觉锤收敛：tint（1 锤）+ ✓ 角标（多选时 1 锤）= 1-2 锤
    /// V5.26: 加 1.5pt accent border 单选态——更明确的选中视觉
    ///   之前仅 tint (0.10 opacity) + ✓ (多选)——单选视觉过 subtle
    ///   1.5pt border 0.6 opacity + tint 0.10 = 2 锤 (单选) / 1 锤 (multi tint 0.15 取代 0.10)
    ///   V4.62.0 教训"3 重视觉锤 = 累赘"——本次 2 锤仍守
    ///   互斥 hover border (cellHoverOverlay)——1 锤不超 3 锤
    @ViewBuilder
    private var cellSelectionOverlay: some View {
        let state = selectionState
        ZStack {
            // V5.28: 砍 tint, 加 3pt accent border——"仅显示蓝色边框" (Photos 真版)
            //   - 之前 V5.27 砍 border 是误判, 实际 Photos 选中态有边框
            //   - tint 0 → 只 border, 极简
            RoundedRectangle(cornerRadius: Radius.thumb)
                .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: state.borderWidth)
                .background(
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .fill(Color.accentColor.opacity(state.tintOpacity))  // V5.28: 始终 0
                )
            if state.showsCheckmark {
                // 角标 ✓ 保留——V3.6.51 selection state machine 设计
                // 单选不显 ✓（subtle），多选显 ✓（更明确）
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

    /// V5.23: Hover 视觉反馈——subtle 1.005 scale
    /// V5.27: 砍 hover border——macOS Photos Library hover 无 border
    ///   - 仅留 1.005 scale（V5.23-2 加的）作为 hover 唯一视觉锤
    ///   - V4.62.0 教训"3 重视觉锤 = 累赘"：单选 1 锤（tint）/ hover 1 锤（scale）/ multi 2 锤（tint + ✓）
    ///   - Photos.app 真版：hover 也有轻微反馈但无 border——这里保留 scale 妥协
    // V5.27: cellHoverOverlay 整段删——hover border 不再需要

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
                        // V5.34: .fit → .fill——回 Photos.app Library 真版
                        //   - Photos 实际是 1:1 等大 cell + image 中心裁切 (.fill)
                        //   - 每行每列 cell 中心完美对齐
                        //   - portrait 3:4 中心裁切: 主体居中, 上下被裁
                        //   - landscape 16:9 中心裁切: 主体居中, 左右被裁
                        //   - V5.33 误判 Photos 是 justified (实际是 Pinterest/Flickr 风格), 改回
                        //   - "智能主体识别" 留 V5.35+ (Vision framework saliency)
                        // V5.30: 加 .transition(.opacity) + .animation——image 加载完淡入
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(aspectRatio, contentMode: .fill)  // V5.34: 回 .fill (中心裁切)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                            .saturation(photo.isInTrash ? 0.05 : 1)
                            .opacity(photo.isInTrash ? (colorScheme == .dark ? 0.65 : 0.55) : 1)
                            // V5.30: image 加载完淡入——镜像 Photos.app Library cell 行为
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.1), value: loadedImage != nil)  // V5.31: 0.2→0.1 (快滚动不'波')
                    } else if loadFailed {
                        // V5.34: 失败占位也 .fill——保持一致
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fill)  // V5.34: 回 .fill
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
                        // V5.34: 加载中 shimmer 也 .fill
                        RoundedRectangle(cornerRadius: Radius.thumb)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fill)  // V5.34: 回 .fill
                            .shimmer()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // V5.27: cell 背景透明——实现 macOS Photos Library "letterbox 透窗口色" 视觉
            //   - 之前 V5.21 加 4% 白色 tint 是 iOS Photos "poloroid" 痕迹
            //   - macOS Photos.app 实际：cell 与窗口同背景，letterbox 区就是窗口色
            //   - V4.4.5 教训：cell 背景不能比窗口背景浅一档（"浅框"幽灵）——clear 最安全
            //   - letterbox 透窗口色 + image 居中 = "漂浮的图片" 视觉 = Photos Library 真版
            .background(
                RoundedRectangle(cornerRadius: Radius.thumb)
                    .fill(Color.clear)  // V5.27: V5.21 加的 0.04 white tint → clear
            )
            // V3.6.26: 异步加载缩略图（缓存命中立即返回；未命中后台线程解码）
            // V4.4.0: 加载失败时 set loadFailed=true（loadImageAsync 返回 nil 视为失败）
            // V5.17: 600→1200 retina 优化（HiDPI 屏 200pt cell 锐化）
            //   1200px 源 = 3x 下采样仍锐（Photos.app 内部 1000-2000px 缓存）
            // V5.32: 1200 → 600——4x 内存节省, 4x 解码加速
            //   - 200pt cell × 2x retina = 400 实际像素 (1x 渲染) / 800 像素 (2x 安全渲染)
            //   - 600 留 50% headroom (4x retina 屏仍清晰)
            //   - 单图 600²×4 = 1.44MB (vs 1200²×4 = 5.76MB)
            //   - NSCache 400MB: 280 images (vs 70) — 滚动更顺, LRU 命中率更高
            //   - 解码耗时: 1200px ~20-40ms, 600px ~5-10ms (1/4 耗时)
            //   - 1 张 4K 原图 (4032×3024) 缩到 600 仍锐; 1.5x 缩放足以覆盖 1.5x zoom
            //   - V5.17 设 1200 是'HiDPI 优化'——但 1200 远超 grid 实际需要
            .task(id: photo.id) {
                loadFailed = false
                let img = await ImageLoader.loadImageAsync(
                    at: photo.fileURL,
                    maxPixelSize: 600  // V5.32: 1200 → 600 (grid 200pt × 2x retina = 400px)
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
        .frame(maxWidth: .infinity)
        // V5.19: 内 cell 2pt padding——Photos.app "framed photo" 风格
        //   之前 image 完全 fill cell——视觉紧贴边界
        //   2pt padding 让 image 周围有 2pt 窗口背景呼吸感（cellSpacing 20pt 之外再加一点）
        //   镜像 iOS Photos.app / Finder thumbnail 视觉——像被"框"住的图
        .padding(Self.innerCellPadding)
        // V5.16: cell 形状 = (cellWidth, rowHeight)——外部 MasonryRow 算好传入
        //   cellWidth = rowHeight × photo.aspectRatio → cell frame 大小
        //   行内所有 cell 高齐 rowHeight（行底部无 jagged）
        //   V5.19: image 在 cell 内缩 4pt (2pt × 2) —— padding 不影响 cell frame
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
        // V5.27: 删 .overlay(cellHoverOverlay)——hover border 砍了，cellHoverOverlay 整段删
        // V5.17: 砍 hover scale 1.01 / 选中 1.015（V4.62.0 教训"3 重视觉锤 = 累赘"）
        //   之前 isActive 1.015 / hover 1.01 / ✓ 角标——3 锤叠加
        //   Photos.app / Finder 无 hover scale——只 accent tint + ✓ 角标
        //   currentScale 保留属性（1.0 兜底）以防误加回
        // V4.4.2: 删除 resting shadow——这就是「浅框」幽灵的真正源头
        //   V3.1 引入「始终浮起感」: resting Elevation.subtle (radius=2, y=1, opacity=0.08)
        //   但 shadow 在 cell 四周扩散 2pt，在浅色 grid 间距上呈现为"一圈淡色光晕"
        //   = 用户感知的「浅框」（每个 cell 都有，无论选中与否）
        //
        // V4.4.3: 删 V5.28 hover shadow——用户 spec "无悬停动效" (Photos 真版)
        //   - V3.1 引入 resting shadow + V4.4.3 hover shadow 都是 iOS Photos 痕迹
        //   - 镜像 macOS Photos.app: cell hover 无 shadow 反馈
        //   - 选中态仅 border 视觉锤——不需要 shadow 配合
        // V3.6.51: 单一 .animation 驱动所有选中状态过渡
        .animation(Animations.standard, value: selectionState)
        .animation(Animations.springGentle, value: isFocused)
        // V5.30: 删 .onHover 整段——isHovered state 已删, hook 失效
        //   之前 V5.28-4 保留为"未来 hook", 但 dead code 违反 V4.62.0 收敛原则
        //   若未来加 hover 反馈, 重新加回 .onHover + state 即可
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
        // V5.28: 删 .scaleEffect(currentScale) + .animation(value: isHovered)
        //   - 之前 V5.23 加 1.005 scale + V5.23-2 加 1pt border = hover 2 锤
        //   - V5.28: hover 0 锤——"无悬停动效" (Photos 真版)
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
