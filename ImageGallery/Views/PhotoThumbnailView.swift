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
//  V6.17.2: 抽 cell 主体 (body + state + env + helpers) 到 PhotoCellContent sub-view
//    解决 V6.17.1 known limitation: 圈选时 cell .draggable 跟 marquee rect 同时显示
//    sub-view 单独 type-check, 加 @Environment(\.isMarqueeActive), 圈选时 .draggable 返 nil
//    视觉冲突彻底修
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - V6.17.2: 抽 cell 主体到 PhotoCellContent sub-view
//
//  解 V6.17.1 known limitation (圈选时 cell .draggable 跟 marquee rect 同时显示)
//  之前: body 377 行 + 多个 modifier chain → SwiftUI type-check timeout
//  之前: 不能加 @Environment(\.isMarqueeActive) (V6.17.1 注释 line 64-67)
//  现在: 主体 377 行移到独立 private struct, 单独 type-check 不超时
//  现在: sub-view 加 @Environment(\.isMarqueeActive), 圈选时 .draggable 返 nil
//
//  调用方: PhotoThumbnailView 退化为 17 行纯转发
//  Env 传播: PhotoGridView 2 个 layout 注入 .environment(\.isMarqueeActive, ...)
//  行为变化: 圈选时 cell 不再 .draggable (visual conflict 消失)
// MARK: - V6.17.2: nested types 提升到 file-scope (供 PhotoCellContent 引用)
//   之前 nested in PhotoThumbnailView, 跨 sub-view 不行

/// V4.1.0: 剩余天数 badge 颜色 (V3.6.51 重构后)
struct BadgeColor {
    let foreground: Color
    let background: Color
}

/// V3.6.51: 重构——选中状态机 (V5.17 border=0 → V5.26 1.5pt → V5.27 0 → V5.28 1.5pt → V5.99.2 3pt)
enum CellSelectionState {
    case none
    case single
    case multi

    /// 2pt——比 3pt 更干净，减少对照片内容的视觉干扰
    var borderWidth: CGFloat {
        switch self {
        case .none:   return 0
        case .single: return 2
        case .multi:  return 2
        }
    }

    /// V5.99.2: 0.15/0.22 — 深色图片选中态可见
    var tintOpacity: Double {
        switch self {
        case .none:   return 0
        case .single: return 0.10
        case .multi:  return 0.18
        }
    }

    var showsCheckmark: Bool {
        self == .multi
    }
}

// MARK: - PhotoThumbnailView 公开 API (退化为 17 行纯转发)
//   V6.17.2: 之前 800 行 (含 377 行 body), 现在 body 退化为 1 行转发
//   保留所有 stored properties + @Binding (call site 兼容) + 4 个 @Environment
//   V5.28 dead state (currentScale) 已删
struct PhotoThumbnailView: View {
    let photo: Photo
    let isInMultiSelect: Bool
    let isActive: Bool
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let retentionDays: Int
    let layoutMode: ThumbnailLayoutMode
    let sortOption: SortOption
    let onReorder: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    // V6.22.1 (P2 #2): 旋转闭包 — ContentView 传 { model.rotateSelected(clockwise:) }
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void
    // V6.94.1 (P0 #3): 标注闭包 — ContentView 传 { NotificationCenter.default.post(name: .markupRequested) }
    //   context menu "标注..." 项触发, 走 NotificationCenter
    let onMarkup: () -> Void
    // V6.97.1 (P0 #5): 裁剪回调 — caller 透传同 onMarkup
    let onCrop: (Photo) -> Void
    // V6.97.1.1 (Bug fix C3): isSingle — 单选 gate, 多选 disable 裁剪... button
    let isSingle: Bool
    // V6.38.1 (Phase 1): onDelete 移除 — 删除从 cell 入口搬走, 走 ⌘⌫ → handleDelete()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    // V6.17.2: 之前 line 64-67 注释 "V6.17.2 留" 已实现, @Environment 加在 sub-view
    //   wrapper 不需要 isMarqueeActive (它不消费, 只是转发)

    var body: some View {
        PhotoCellContent(
            photo: photo,
            isInMultiSelect: isInMultiSelect,
            isActive: isActive,
            selection: selection,
            folders: folders,
            allTags: allTags,
            cellWidth: cellWidth,
            rowHeight: rowHeight,
            retentionDays: retentionDays,
            layoutMode: layoutMode,
            sortOption: sortOption,
            onReorder: onReorder,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            // V6.22.1 (P2 #2): 旋转闭包 (cell 自己没 model, 转发到 caller)
            onRotateLeft: onRotateLeft,
            onRotateRight: onRotateRight,
            // V6.94.1 (P0 #3): 标注闭包 (context menu "标注..." 项)
            onMarkup: onMarkup,
            onCrop: onCrop,
            isSingle: isSingle
        )
    }
}

// V6.22.8: 条件 .draggable modifier — Photos.app 范式
//   只在 cell 已选中时启用 .draggable (item drag 到 Finder / sidebar folder)
//   未选 cell 拖 = 让父 VStack 的 marqueeSelectionGesture 接管 (selection 替换)
//   之前无条件 .draggable → AppKit NSItemProvider 抢父 simultaneousGesture 的 DragGesture.onEnded
//   → marquee 选区不应用 (selection 不变)
//   SwiftUI .draggable 不直接支持 Optional payload, 用 ViewModifier 包装实现条件应用
struct ConditionalDraggableModifier<Preview: View>: ViewModifier {
    let isDraggable: Bool  // cell 是否已选中
    let payload: PhotoDragItem
    @ViewBuilder let preview: () -> Preview

    func body(content: Content) -> some View {
        if isDraggable {
            content.draggable(payload) { preview() }
        } else {
            content
        }
    }
}
