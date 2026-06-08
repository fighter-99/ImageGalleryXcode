//
//  DetailPane.swift
//  ImageGallery
//
//  三列布局的右侧列：详情面板。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  三种状态：
//  1. 选中单张图 → DetailView（带元数据、标签、EXIF、上一张/下一张）
//  2. 多选模式 → MultiSelectDetailView（提示批量操作快捷键）
//  3. 无选中 → EmptyDetailView（提示选择图片）
//

import SwiftUI

struct DetailPane: View {
    let singleSelectedPhoto: Photo?
    let isMultiSelect: Bool
    let count: Int
    let totalSize: Int64
    let folders: [Folder]
    let allTags: [Tag]
    // 单图操作
    let onDelete: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let canPrev: Bool
    let canNext: Bool
    let currentIndex: Int
    let totalCount: Int
    // 多选操作（V3.5.19：从 mainLayout 接过来）
    let onBatchMove: (Folder?) -> Void
    let onBatchAddTag: (Tag) -> Void
    let onBatchToggleFavorite: () -> Void
    let onBatchExport: () -> Void
    let onBatchDelete: () -> Void
    let onClearSelection: () -> Void
    // V3.6 NEW: 回收站模式（nil = 非回收站）
    let sidebarSelection: SidebarSelection?
    let retentionDays: Int
    // 回收站操作
    let onTrashRestore: () -> Void
    let onTrashPermanentDelete: () -> Void
    let onEmptyTrash: () -> Void
    // V3.6.15 NEW: 重复图模式操作
    let onKeepNewestPerDuplicateGroup: () -> Void

    var body: some View {
        // V3.6.44: 加 .id(viewKind) 让 SwiftUI 知道是"不同视图"（不是同一 view 内部状态变化）
        //   这样 .transition 才会触发；.animation 驱动 spring 过渡
        //   viewKind 字符串反映当前显示的是哪种详情面板
        let viewKind: String = {
            if sidebarSelection == .recentlyDeleted { return "trash" }
            if sidebarSelection == .duplicates { return "duplicates" }
            if let photo = singleSelectedPhoto { return "photo-\(photo.id)" }
            if isMultiSelect { return "multi" }
            return "empty"
        }()

        return Group {
            // V3.6: 回收站模式优先于其他（回收站视图里没有"单图操作"概念）
            if sidebarSelection == .recentlyDeleted {
                TrashDetailView(
                    count: count,
                    totalSize: totalSize,
                    retentionDays: retentionDays,
                    onRestore: onTrashRestore,
                    onPermanentDelete: onTrashPermanentDelete,
                    onEmptyTrash: onEmptyTrash
                )
            // V3.6.15: 重复图模式（仿 TrashDetailView 的"操作中心"模式）
            } else if sidebarSelection == .duplicates {
                DuplicatesDetailView(
                    duplicateGroupCount: count,
                    purgeableCount: count,
                    purgeableSize: totalSize,
                    onKeepNewestPerGroup: onKeepNewestPerDuplicateGroup
                )
            } else if let photo = singleSelectedPhoto {
                DetailView(
                    photo: photo,
                    onDelete: onDelete,
                    onPrev: onPrev,
                    onNext: onNext,
                    canPrev: canPrev,
                    canNext: canNext,
                    currentIndex: currentIndex,
                    totalCount: totalCount
                )
            } else if isMultiSelect {
                MultiSelectDetailView(
                    count: count,
                    totalSize: totalSize,
                    folders: folders,
                    allTags: allTags,
                    onMove: onBatchMove,
                    onAddTag: onBatchAddTag,
                    onToggleFavorite: onBatchToggleFavorite,
                    onExport: onBatchExport,
                    onDelete: onBatchDelete,
                    onClearSelection: onClearSelection
                )
            } else {
                EmptyDetailView()
            }
        }
        .id(viewKind)  // V3.6.44: 视图类型变化时强制 transition
        .transition(.opacity)
        // V3.6.46: 用户反馈详情面板"向右翻页"感太重，去掉 .move，只保留 .opacity
        //   切到 .standard（0.2s easeInOut）—— 详情面板切换不需 Q 弹，平滑即可
        .animation(Animations.standard, value: viewKind)
    }
}
