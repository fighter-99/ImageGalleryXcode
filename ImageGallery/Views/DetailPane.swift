//
//  DetailPane.swift
//  ImageGallery
//
//  三列布局的右侧列：详情面板。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  V4.36.4: 加"未选中 → EmptyDetailPlaceholder"分支——V4.36.2 撤回 hasContent 隐藏后
//    detail panel 永远显示, 未选中时显示简单占位（不显示 LibraryOverview 重复内容）
//
//  五种状态（5 个 detail view，含 empty 占位）：
//  1. 存储错误 → EmptyStateView（错误样式）
//  2. 回收站模式 → TrashDetailView
//  3. 重复图模式 → DuplicatesDetailView
//  4. 选中单张图 → DetailView
//  5. 多选模式 → MultiSelectDetailView
//  6. 无选中（普通浏览）→ EmptyDetailPlaceholder（图标 + 提示）
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
    // V5.7: 砍 onBatchToggleFavorite——多选面板的"收藏"按钮移除
    // V5.12: 加 onBatchSetRating——多选面板加"评分"子菜单
    let onBatchSetRating: (Int) -> Void
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
    // V4.9.0: 回收站空时切回"全部"视图（用于 TrashDetailView EmptyStateView 次 CTA）
    let onExitTrash: () -> Void
    // V3.6.15 NEW: 重复图模式操作
    let onKeepNewestPerDuplicateGroup: () -> Void

    // V4.11.0: 存储不可写错误（nil = OK）
    //   PhotoStorage.verifyStorage() 失败时填消息，detail panel 切到错误态
    //   重试按钮触发 onRetryStorage 重新检测
    let storageError: String?
    let onRetryStorage: () -> Void

    var body: some View {
        // V3.6.44: 加 .id(viewKind) 让 SwiftUI 知道是"不同视图"（不是同一 view 内部状态变化）
        //   这样 .transition 才会触发；.animation 驱动 spring 过渡
        //   viewKind 字符串反映当前显示的是哪种详情面板
        let viewKind: String = {
            if storageError != nil { return "storage-error" }
            if sidebarSelection == .recentlyDeleted { return "trash" }
            if sidebarSelection == .duplicates { return "duplicates" }
            if let photo = singleSelectedPhoto { return "photo-\(photo.id)" }
            if isMultiSelect { return "multi" }
            return "empty"  // V4.36.2: unreachable——MainSplitView 已在 hasContent=false 隐藏整个面板
        }()

        return Group {
            // V4.11.0: 存储不可写错误态——盖所有其他分支
            //   用 EmptyStateView 错误样式（exclamationmark.triangle + destructive iconColor + 重试 CTA）
            if let storageError {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "存储不可用",
                    subtitle: storageError,
                    iconColor: .red,
                    primaryAction: EmptyStateView.Action(
                        label: "重试",
                        systemImage: "arrow.clockwise",
                        onTap: onRetryStorage
                    )
                )
            // V3.6: 回收站模式优先于其他（回收站视图里没有"单图操作"概念）
            } else if sidebarSelection == .recentlyDeleted {
                TrashDetailView(
                    count: count,
                    totalSize: totalSize,
                    retentionDays: retentionDays,
                    onRestore: onTrashRestore,
                    onPermanentDelete: onTrashPermanentDelete,
                    onEmptyTrash: onEmptyTrash,
                    onExitTrash: onExitTrash
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
                    // V5.12: 加 onBatchSetRating 传递
                    onBatchSetRating: onBatchSetRating,
                    onExport: onBatchExport,
                    onDelete: onBatchDelete,
                    onClearSelection: onClearSelection
                )
            } else {
                // V4.36.4: 未选中时显示简单占位——引导用户选照片
                //   V4.36.2 撤回 hasContent 隐藏后, detail panel 永远显示
                //   此处必须给占位, 不能用 EmptyView() (会显得 detail panel 是空的/bug)
                EmptyDetailPlaceholder()
            }
        }
        .id(viewKind)  // V3.6.44: 视图类型变化时强制 transition
        .transition(.opacity)
        // V4.20.0: 撤回 .glassEffectID 回归单 view glassEffect（玻璃 effect 限定在 detail panel 边界内）
        // V3.6.46: 用户反馈详情面板"向右翻页"感太重，去掉 .move，只保留 .opacity
        //   切到 .standard（0.2s easeInOut）—— 详情面板切换不需 Q 弹，平滑即可
        .animation(Animations.standard, value: viewKind)
    }
}

// V4.36.4: 未选中时的 detail panel 占位——引导用户选照片
//   V3.5.x 时代是 EmptyDetailView，V4.36.2 撤回时删了，V4.36.4 重建
//   设计：图标 + 主提示 + 次提示（操作快捷键）— 简洁，不与 sidebar/main grid 重复内容
struct EmptyDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(Typography.emptyStateIcon)
                .foregroundStyle(.tertiary)
            Text(Copy.selectAPhoto)
                .foregroundStyle(.secondary)
            Text(Copy.selectAPhotoHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
