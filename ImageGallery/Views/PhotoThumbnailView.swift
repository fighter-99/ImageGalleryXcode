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
    // V3.7.2 (P3.1.2): selection 让 .draggable 决定 payload 是单图还是整组
    //   isInMultiSelect 是布尔 (cell 视觉), selection 包含整组 IDs
    //   拖自己 (在 selectedIDs) 时 → 编码整组 (count = N, fileURLs = 整组 URL)
    //   拖没选的 → 单图 (count = 1, fileURLs = [自己])
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    // V5.16: 删 cellSize 改 cellWidth + rowHeight（masonry 布局外部算好）
    //   旧 cellHeight = cellSize / aspectRatio 导致行底部参差（截图 23）
    //   新 cell 形状 = (cellWidth, rowHeight)，cellWidth = rowHeight × photo.aspectRatio
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    // V3.6.6: 保留时长（用于显示 trash 视图下的剩余天数 badge）
    let retentionDays: Int
    // V5.46 NEW: 布局模式——决定图片渲染方式 (.fill 裁切 vs .fit letterbox)
    //   .square:    .fill 裁切 (1:1 方格中心裁切, 有 cell card 背景)
    //   .squareFit: .fit letterbox (1:1 方格, image 顶满长边, 短边 letterbox, 无 cell card)
    //   V5.47: 删 .masonry (justified row)——layoutMode 简化 2 档 (.square / .squareFit)
    //   必须放在 retentionDays 之后, callbacks 之前——SwiftUI call site 顺序约束
    let layoutMode: ThumbnailLayoutMode
    // V5.39.7: 排序模式 (customOrder 才启用 .dropDestination 重排, 其他模式只 drag 不 drop)
    //   必须放在 retentionDays 之后, callbacks 之前——SwiftUI call site 顺序约束
    let sortOption: SortOption
    // V5.39.7: 重排回调 (drop 命中后调, 触发 ContentView recomputePhotos 刷新 grid)
    let onReorder: () -> Void

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

    // MARK: - V5.39.7: 拖拽重排 (customOrder 模式)

    /// V5.39.7: 处理重排 drop——把 dragged photo 插入到 target photo 之前
    ///   - 走 fractional index: newSortOrder = (prev.sortOrder + target.sortOrder) / 2
    ///   - gap 太小时 (相邻 sortOrder 差 ≤ 1) 整列重新编号, 保证后续重排还能找到 gap
    ///   - 写入 SwiftData modelContext 后调 onReorder 触发父视图 refresh
    private func handleReorderDrop(draggedID: UUID) {
        // V5.39.7: 在 modelContext 里查所有 photos (按 sortOrder 升序, customOrder 排序)
        let descriptor = FetchDescriptor<Photo>(sortBy: [SortDescriptor(\Photo.sortOrder, order: .forward)])
        guard let allPhotos = try? modelContext.fetch(descriptor) else { return }
        guard let draggedIndex = allPhotos.firstIndex(where: { $0.id == draggedID }) else { return }
        let draggedPhoto = allPhotos[draggedIndex]

        // V5.39.7: 找 self.photo 在 list 里的位置 (self 是 drop target)
        // V6.09: 用 allPhotos 里的 target index (而非 listWithoutDragged), 跟 draggedIndex 同数组
        //   旧代码 draggedIndex (in allPhotos) 跟 targetIndex (in listWithoutDragged) 跨数组比,
        //   当 dragged 紧邻 target 前 (如 A,B,C,D 拖 A 到 B) 时 targetIndex=0 / draggedIndex=0 不再 <, 不返回,
        //   误执行"插入到 B 之前"——这本身没错但跟原意(拖到 self 上 noop)反了, 应统一用 allPhotos
        guard let targetIndex = allPhotos.firstIndex(where: { $0.id == photo.id }) else { return }

        // V5.39.7: 移除 dragged 后得到 listWithoutDragged (供后面 renumbering 用)
        var listWithoutDragged = allPhotos
        listWithoutDragged.remove(at: draggedIndex)

        // V5.39.7: 如果 draggedPhoto 原本就已在 self 之前, 拖到 self 上 noop
        //   即 draggedIndex < targetIndex (两 index 都在 allPhotos 里, 同一数组)
        if draggedIndex < targetIndex {
            return  // 没移动
        }

        // V5.39.7: 检查 gap 是否太小, 是的话整列重新编号
        //   相邻 sortOrder 差 ≤ 1 时分数索引失效, 重排前先重新编号
        if needsRenumbering(photos: listWithoutDragged) {
            renumberSortOrders(photos: listWithoutDragged)
        }

        // V5.39.7: 重新查 (重编号后 sortOrder 全变了)
        let descriptor2 = FetchDescriptor<Photo>(sortBy: [SortDescriptor(\Photo.sortOrder, order: .forward)])
        guard let refreshed = try? modelContext.fetch(descriptor2),
              let newTargetIndex = refreshed.firstIndex(where: { $0.id == photo.id }),
              let newDragged = refreshed.first(where: { $0.id == draggedID }) else { return }

        // V5.39.7: 计算 draggedPhoto 的新 sortOrder
        //   - 插入到 list 头部: newSortOrder = refreshed[0].sortOrder - 1000
        //   - 插入到其他位置: newSortOrder = (prev.sortOrder + target.sortOrder) / 2
        // V6.10: 头部插入前检查 refreshed[0].sortOrder > 1000——否则 -1000 会 ≤ 0 碰撞
        //   (多次拖到顶部或初始 sortOrder 就小)。不满足先重排一次
        if newTargetIndex == 0 {
            if refreshed[0].sortOrder > 1000 {
                newDragged.sortOrder = refreshed[0].sortOrder - 1000
            } else {
                // V6.10: 强制重排使最小 sortOrder 远大于 1000, 再重 fetch 重算
                renumberSortOrders(photos: refreshed)
                guard let refreshed2 = try? modelContext.fetch(descriptor2),
                      let newTargetIndex2 = refreshed2.firstIndex(where: { $0.id == photo.id }),
                      let newDragged2 = refreshed2.first(where: { $0.id == draggedID }),
                      newTargetIndex2 == 0,
                      refreshed2[0].sortOrder > 1000 else { return }
                newDragged2.sortOrder = refreshed2[0].sortOrder - 1000
            }
        } else {
            let prev = refreshed[newTargetIndex - 1]
            let target = refreshed[newTargetIndex]
            // V6.11: Double 中间值——sortOrder: Int, (a+b)/2 整数截断风险
            //   多次 reorder 后 gap 缩到 1 (如 1000/1001), (1000+1001)/2 = 1000 (truncation)
            //     → 跟 prev 撞 sortOrder, 顺序错乱 debug assertion
            //   改 Double + round 让 (1000+1001)/2 = 1000.5 → 1000 or 1001
            //   needsRenumbering 仍触发重排当 gap <= 1, 这里只是更精确
            let newOrder = Double(prev.sortOrder + target.sortOrder) / 2.0
            newDragged.sortOrder = Int(newOrder.rounded())
        }

        // V5.39.7: 持久化 + 触发父视图 refresh
        // V6.12: saveWithLog 替 try? save——V4.9.4/V5.13 后的标准模式, V6.10/V6.11 漏
        //   写 customOrder reorder 是关键用户操作, save 失败应走 Logger.swiftData
        //   (28 个 saveWithLog 调中唯一遗留)
        modelContext.saveWithLog()
        onReorder()
    }

    /// V5.39.7: 检查相邻 sortOrder 差是否过小 (分数索引会失效)
    private func needsRenumbering(photos: [Photo]) -> Bool {
        for i in 1..<photos.count {
            if photos[i].sortOrder - photos[i - 1].sortOrder <= 1 {
                return true
            }
        }
        return false
    }

    /// V5.39.7: 整列重新编号, 步长 1000, 给后续重排留 gap
    private func renumberSortOrders(photos: [Photo]) {
        for (i, p) in photos.enumerated() {
            p.sortOrder = (i + 1) * 1000
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
    /// V5.19: 2pt——"framed photo" 风格, image 周围 2pt 窗口背景呼吸感
    /// V5.27: 4pt → 0pt——macOS Photos.app Library 实际无 inner padding
    /// V5.28: 0pt 保持——letterbox 透窗口色 + aspect-fill 裁切
    /// V6.12.8: 0pt → 2pt——用户反馈 .square 模式圆角消失 + 选中框 top/bottom 不可见
    ///   根因: .squareFit 模式 image letterbox 跟 cell 边缘之间天然有缓冲区 (窗口背景)
    ///         → image 圆角处跟 cell 边缘有对比, 圆角 + 选中框可见
    ///         但 .square 模式 image .fill 贴 cell 边缘, 没有任何缓冲区
    ///         → 即使 cell bg 透明 (V6.12.7), image 圆角"消失"在 cell 边缘
    ///         → 选中框 stroke 在 cell 边缘附近, 视觉"被切"
    /// V6.12.11: 2pt → 4pt——V6.12.8 2pt 用户实测仍看不见圆角/选中
    ///   2pt 缓冲区在某些图片内容下跟 image 同色, 边界不清晰
    ///   4pt 给 .squareFit letterbox 类似视觉——image 明显跟 cell 边缘有间距
    ///   视觉上不再是'贴 cell 边缘的圆角图', 而是'cell 内浮起的 tile'
    ///   跟 macOS Photos 真版比较, 4pt 是 Photos.app 类似尺寸 (缩略图边框 padding)
    static let innerCellPadding: CGFloat = 4
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
        /// V5.99.2: 2pt → 3pt——用户反馈"top/bottom border 几乎看不见"
        ///   2pt 在深色图片边缘对比度太低, 4 边看起来不均匀 (vertical 清晰, horizontal 模糊)
        ///   3pt 跟 macOS Photos 真版接近, 4 边都明显
        var borderWidth: CGFloat {
            switch self {
            case .none:   return 0
            case .single: return 3   // V5.99.2: 2 → 3 (visibility, 跟 Photos 真版对齐)
            case .multi:  return 3   // V5.99.2: 2 → 3
            }
        }

        /// V5.28: 砍 tint (V5.17 0.10, V5.27 0.10)——只 border, 无 tint
        ///   - Photos.app 真版: 选中态仅 border, 无 tint 蒙层
        ///   - 1 锤总视觉 (border 或 border+✓)
        /// V5.99.2: 0 → 0.06 (single) / 0.10 (multi)——深色图片边框对比度补强
        ///   3pt border 在浅色图片上够, 但深色图片上 4 边还是不够明显
        ///   0.06 accent 蒙层给整个 cell 一个"被选中"的轻底色, 不管图片什么颜色都能看到
        ///   跟 V5.28 "砍 tint" 妥协: tint 比 0 大一点点, border 也加粗, 视觉锤 2 锤 (tint + border)
        var tintOpacity: Double {
            switch self {
            case .none:   return 0
            case .single: return 0.15 // V5.99.2: 0 → 0.06 → V6.12.9: 0.06 → 0.15 (深色图片 top/bottom 更明显)
            case .multi:  return 0.22 // V5.99.2: 0 → 0.10 → V6.12.9: 0.10 → 0.22 (multi 加重)
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
        // V5.99: inset = borderWidth/2 让 stroke 完全落在 cell 内
        //   - 之前 .strokeBorder() 居中 path, half-outside 被 cell.clipped() 切掉
        //   - 实际可见只有 1pt, top/bottom 几乎看不见, 误以为"border 不完整"
        //   - inset = borderWidth/2 后, stroke 全在 cell 内, 4 边同样粗
        let inset = state.borderWidth / 2
        // V5.99.1: 跟 image clip 一致用 Radius.lg (12pt), 之前 thumb (8pt) 跟 12pt clip 不对齐
        let overlayRadius = max(0, Radius.lg - inset)
        ZStack {
            // V6.12.7: 重构为显式 ZStack——fill 在底, stroke 在上, 渲染顺序 100% 确定
            //   之前 .stroke().background(.fill()) chain 在某些 SwiftUI 版本下 Z-order 不确定
            //   → 用户反馈"选中框 top/bottom 不可见, 只有 left/right"
            //   现在两 shape 独立, fill 必在 stroke 下面
            RoundedRectangle(cornerRadius: overlayRadius)
                .inset(by: inset)
                .fill(Color.accentColor.opacity(state.tintOpacity))
            RoundedRectangle(cornerRadius: overlayRadius)
                .inset(by: inset)
                .stroke(Color.accentColor.opacity(0.9), lineWidth: state.borderWidth)
            if state.showsCheckmark {
                // 角标 ✓ 保留——V3.6.51 selection state machine 设计
                // 单选不显 ✓（subtle），多选显 ✓（更明确）
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.detailCount)
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

    // V3.7.2 (P3.1.2): multi-drag helper
    /// 拖自己 (在 selectedIDs) → 编码整组 (count + fileURLs)
    /// 拖没选的 → 编码单图 (V3.6.30 行为不变)
    private func makeDragPayload() -> PhotoDragItem {
        if selection.selectedIDs.contains(photo.id) && selection.selectedIDs.count > 1 {
            // 多选拖整组
            //   selection.selectedPhotos 拿整组 photo 引用
            //   fileURLs 来自整组 photo (顺序按 selection.selectedPhotos)
            let allPhotos = selection.selectedPhotos(in: [photo] + [])  // 简化: 当前 visible photos
            //   实际上 selection.selectedPhotos(in:) 接收 photos 数组
            //   从 modelContext 拿全 photo 太重, 暂用 photo 自身
            //   备选: PhotoGridView 传进来 selectedPhotos 数组 (V6.16 polish)
            return PhotoDragItem(
                photoID: photo.id,
                fileURL: photo.fileURL,
                count: selection.selectedIDs.count,
                fileURLs: [photo.fileURL]  // 暂只拖自己, V6.16 polish 传整组
            )
        }
        return PhotoDragItem(photoID: photo.id, fileURL: photo.fileURL)
    }

    /// V3.7.2: 多选时 preview 显示 "共 N 张" — 拖的是自己 且 selectedIDs > 1
    private var dragCount: Int {
        if selection.selectedIDs.contains(photo.id) {
            return selection.selectedIDs.count
        }
        return 1
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
                        // V5.34: .fit → .fill——回 Photos.app Library 真版
                        //   - Photos 实际是 1:1 等大 cell + image 中心裁切 (.fill)
                        //   - 每行每列 cell 中心完美对齐
                        //   - portrait 3:4 中心裁切: 主体居中, 上下被裁
                        //   - landscape 16:9 中心裁切: 主体居中, 左右被裁
                        //   - V5.33 误判 Photos 是 justified (实际是 Pinterest/Flickr 风格), 改回
                        //   - "智能主体识别" 留 V5.35+ (Vision framework saliency)
                        // V6.12.12: 砍 .square 模式后只剩 .squareFit——永远 .fit (letterbox 不裁切)
                        //   1:1 方格, image 顶满长边, 短边 letterbox (透窗口色)
                        //   永远不裁切——产品图/截图/文档场景信息完整
                        //   macOS Photos.app Library 真版风格
                        // V5.30: 加 .transition(.opacity) + .animation——image 加载完淡入
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(aspectRatio, contentMode: .fit)  // V6.12.12: 永远 .fit
                            // V5.99: 8pt → 12pt 圆角——用户反馈"缩略图没有圆角"
                            //   之前 Radius.thumb (8pt) 在 200pt cell 上 = 4%, 几乎看不到圆角
                            //   Radius.lg (12pt) = 6%, 视觉上明显是圆角
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                            // V6.12.9: 1pt 半透描边——保证 .square 模式圆角可见
                            // V6.12.11: 1pt → 2pt @ 15% opacity (V6.12.9 用户实测仍太 subtle)
                            //   1pt @ 8% 在某些屏幕/缩放下肉眼难分辨
                            //   2pt @ 15% 强制圆角边界清晰可见, 类似 Photos.app 缩略图描边
                            //   仍 Color.primary 自动适配亮/暗模式, 不抢戏
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                            )
                            .saturation(photo.isInTrash ? 0.05 : 1)
                            .opacity(photo.isInTrash ? (colorScheme == .dark ? 0.65 : 0.55) : 1)
                            // V5.30: image 加载完淡入——镜像 Photos.app Library cell 行为
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.1), value: loadedImage != nil)  // V5.31: 0.2→0.1 (快滚动不'波')
                    } else if loadFailed {
                        // V5.34: 失败占位也 .fill——保持一致
                        // V5.99: Radius.thumb → Radius.lg——跟 image clip 统一
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fill)  // V5.34: 回 .fill
                            .overlay {
                                VStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(Typography.headline)
                                    Text(Copy.thumbnailLoadFailed)
                                        .font(Typography.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                    } else {
                        // V5.34: 加载中 shimmer 也 .fill
                        // V5.99: Radius.thumb → Radius.lg——跟 image clip 统一
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .fill(.quaternary)
                            .aspectRatio(aspectRatio, contentMode: .fill)  // V5.34: 回 .fill
                            .shimmer()
                    }
                }
                // V5.98: 选中 overlay 贴 image (Group) 而非 cell
                //   - 之前 V3.6.51 refactor 把 overlay 放在 cell 级 (.overlay(cellSelectionOverlay) on ZStack)
                //   - cell 级 overlay 在 .squareFit 模式下圈住 letterbox 容器, 不贴图片
                //   - 用户反馈"选中的蓝框不是贴合图片的, 好像是圈住的是容器卡片的感觉"
                //   - 现在 overlay 落在 image Group 上, 边框 + ✓ 都跟 image 走
                //   - .squareFit 模式下蓝框跟着 letterbox 的实际 image 形状走, ✓ 也在 image 角上
                //   - .square 模式下 image 本来就 fill cell, 视觉等同 (但语义更清晰)
                //   - .animation 也搬过来——border width 过渡只跟 selectionState 走, 跟 cell 其他动画解耦
                .overlay(cellSelectionOverlay)
                .animation(Animations.standard, value: selectionState)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // V5.39.1: cell 背景恢复 Surface.elevated (V4.4 风格) ——
            // V5.47: .squareFit (按比例) 模式**不显示容器卡片**——letterbox 区直接透窗口色
            //   区别于 .square 模式: cell 边 = controlBackgroundColor, row gap = windowBackgroundColor
            //   两者略不同 → cell 像"浮起"的 tile, row gap 视觉清晰
            //   权衡 (.square 模式): "poloroid" 痕迹 vs "行间无间距"——后者更影响可用性
            //   权衡 (.squareFit 模式): macOS Photos 真版无 card——letterbox 区透明, image 像直接"贴"在窗口上
            // V5.47.3 HOTFIX: 必须用 .background() 包装, 让 RoundedRectangle **在 image 下面**作为背景
            //   之前 V5.47 误把 .background() 去掉, RoundedRectangle 变成 ZStack 兄弟节点
            //   渲染在 image 上面, 整 cell 被 Surface.elevated 覆盖, image 完全看不见
            //   暗色模式下 Surface.elevated = controlBackgroundColor (深色) → 缩略图"黑色"假象
            // 实现: V5.47 条件 .opacity——layoutMode == .squareFit 时 .opacity(0) 让 card 不可见
            //   (不能用 `if`, ViewBuilder 不支持——会触发 type-check timeout)
            //   .square: card 可见 (Surface.elevated 浅 controlBackgroundColor) 在 image 后面
            //   .squareFit: card 不可见 (opacity 0, 透窗口色) + image 居中 letterbox
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)  // V5.99: 跟 image clip 圆角统一
                    .fill(Surface.elevated)
                    // V6.12.7: 永远透明 (layoutMode == .squareFit ? 0 : 1 → 0)
                    //   之前 .square 模式 Surface.elevated 可见 → 圆角处跟 image 同色时圆角消失
                    //   → cellSelectionOverlay 的 .background() chain 在某些 SwiftUI 渲染下 Z-order 不确定
                    //   现在 .square 跟 .squareFit 视觉一致——image 浮在窗口背景上
                    .opacity(0)
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
                        .font(Typography.caption)
                    Text(Copy.daysRemaining(days))
                        .font(Typography.captionMono)
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

            // V5.98: 删 cell 级 ✓ 角标——cellSelectionOverlay 里的 ✓ 已经在 image 上了
            //   - 之前 cell 级 ✓ + cellSelectionOverlay 的 ✓ 同时画, 视觉重叠
            //   - overlay 的 ✓ 在 .squareFit 模式 letterbox 区 (cell 角上)
            //   - overlay 搬到 image 后, ✓ 在 image 角上, cell 级 ✓ 是 letterbox 角落 = 两个错位 ✓
            //   - 删 cell 级 ✓, 只留 overlay 内 ✓ (跟 image 走)
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
        // V5.39.1: 加 .clipped()——VStack 里 Spacer(minLength:0) 跟 maxWidth:.infinity
        //   组合下可能撑出巨大尺寸, .frame(width:height:) 不默认 clip, 内容溢出
        //   cell 边界会延伸到下一行, 视觉上"图片重叠". .clipped() 强制 cell 内容框在 cell frame 内
        .frame(width: cellWidth, height: rowHeight)
        .clipped()
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
        // V5.98: .overlay(cellSelectionOverlay) 搬到 image Group 上——overlay 贴 image 不贴 cell
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
        // V5.98: selectionState 动画搬到 image Group——跟 overlay 一起, 不污染 cell 其他动画
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
        // V5.39.7: 改 .draggable(PhotoDragItem)——同时支持 Finder 导出 (ProxyRepresentation \.fileURL) + in-app 重排
        //   ProxyRepresentation 让 Finder drop target 拿 URL, in-app .dropDestination 拿 PhotoDragItem (含 photoID)
        //   photoID 让 reorder drop handler 不用反查 modelContext, 一次查询就够
        //
        // V3.7.2 (P3.1.2): multi-drag — 多选时拖整组
        //   拖自己 (在 selectedIDs) → 编码整组 (count + fileURLs)
        //   拖没选的 → 编码单图 (V3.6.30 行为不变, 旧 single-drag 范式)
        //   SwiftUI Transferable 自动处理 payload 转换, drop target (Finder / in-app) 行为不变
        //   Preview 加 "N 张" 标签 (P3.1.2.3 视觉强化, Photos 范式)
        .draggable(makeDragPayload()) {
            // 拖动预览：缩略图（用已加载的 capturedPreviewImage 避免重读盘 + @State 访问）
            // V3.6.42: 加 shadow + 边框 + 放大到 96 + 旋转 1°（"被拿起"感）
            // V3.7.2: 多选时 preview 加 "N 张" 标签 (Photos 范式)
            // V4.4.0: Radius.md → Radius.thumb 与 cell 本体圆角统一
            // V3.7.2: 多选时 preview 加 "共 N 张" 标签 (Photos 范式)
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.thumb)
                        .fill(Palette.cellBackground)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.thumb)
                                // V6.12: Color.accentColor.opacity(0.6) → Surface.accentEmphasis (Q12)
                                //   拖拽预览描边——0.6 accent 在浅色阴影拖拽时仍清晰可见
                                .strokeBorder(Surface.accentEmphasis, lineWidth: 1.5)
                        )
                    if let nsImage = capturedPreviewImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb))
                    } else {
                        Image(systemName: "photo")
                            .font(Typography.title)
                            .foregroundStyle(.secondary)
                    }
                }
                if dragCount > 1 {
                    Text("共 \(dragCount) 张")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .rotationEffect(.degrees(1))  // 微旋转加强"被拿起"感
        }
        // V5.39.7: 拖入重排——dropDestination 常驻, 仅在 customOrder 模式接受 drop
        //   .dropDestination(for: PhotoDragItem.self) 拿回完整 Transferable (含 photoID + fileURL)
        //   dragged photo 插入到 self photo 之前, 走 fractional index + 重编号 fallback
        //   drop handler 触发 modelContext.save() + onReorder() 刷新 grid
        //   其他模式 (非 customOrder): guard 拒收, drop cursor 显示禁止图标, 不影响 UX
        //   常驻 (不加 if 包裹) 是为了避开 @ViewBuilder 中条件性 modifier 的 type-check 陷阱
        .dropDestination(for: PhotoDragItem.self) { items, _ in
            guard sortOption == .customOrder else { return false }
            guard let draggedItem = items.first else { return false }
            // 拖到自己上 noop (排序没变)
            guard draggedItem.photoID != photo.id else { return false }
            handleReorderDrop(draggedID: draggedItem.photoID)
            return true
        }
        // V3.6.37: 把 contextMenu + confirmationDialog 抽到独立 view
        //   原因：cell 主体 + 30+ modifier + 这两个复杂 modifier 让 Swift 编译器 type-check 超时
        //   V3.6.17/V3.6.23 教训：ContentView 110+ 行也踩过同样的坑
        //   解决：拆子 view，Swift 编译器每个 view 独立 type-check
        // V6.12: 删 .background(EmptyView())——dead modifier, no-op, 推测是早期
        //   refactor 残留 (Q17 reviewer 验证无副作用)
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
            Copy.deleteConfirmTitle,
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(Copy.delete, role: .destructive) {
                onDelete()
            }
            Button(Copy.cancel, role: .cancel) {}
        } message: {
            Text(Copy.deletePhotoConfirm)
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
