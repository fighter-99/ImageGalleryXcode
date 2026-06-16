//
//  PhotoGridEmptyState.swift
//  ImageGallery
//
//  V5.29: 空状态视图——从 PhotoGridView 拆出
//    6 个 empty 场景根据 filter 状态切换 icon/title/hint/CTA
//    V4.9.0: 区分 3 种 empty 场景,提供主 + 次 CTA
//      - 无图片 (首次启动) → 主"导入图片"
//      - 空相册/标签 → 主"导入图片" + 次"查看全部"
//      - 无搜索结果 → 主"清除搜索" + 次"查看全部"
//
//  V5.8: 砍"收藏"空状态——V5.7 砍 .favorites 侧边栏后 dead
//

import SwiftUI

// MARK: - CTA 配置

struct PhotoGridEmptyCTA {
    let label: String
    var systemImage: String? = nil
    let onTap: () -> Void
}

// MARK: - 主视图

struct PhotoGridEmptyState: View {
    let searchText: String
    let folder: Folder?
    let tag: Tag?
    let filterUnfiled: Bool
    let filterDuplicates: Bool
    let filterRecent7Days: Bool
    let filterLargeFiles: Bool
    let filterInTrash: Bool
    let isFilterActive: Bool
    let onImport: () -> Void
    let onClearFilters: () -> Void
    // V6.08: 回收站空状态副提示需要 retentionDays (之前写死 defaultValue=30)
    let retentionDays: Int

    var body: some View {
        EmptyStateView(
            icon: icon,
            title: text,
            subtitle: hint,
            // V6.12: Color.accentColor.opacity(0.6) → Surface.accentEmphasis (Q12)
            //   0.6 是"装饰性 accent"——空状态 icon 居中时饱和度不能拉满
            iconColor: Surface.accentEmphasis,
            primaryAction: primaryAction.map {
                EmptyStateView.Action(
                    label: $0.label,
                    systemImage: $0.systemImage,
                    onTap: $0.onTap
                )
            },
            secondaryAction: secondaryAction.map {
                EmptyStateView.Action(
                    label: $0.label,
                    systemImage: $0.systemImage,
                    onTap: $0.onTap
                )
            }
        )
    }

    // MARK: - CTA 决策

    private var primaryAction: PhotoGridEmptyCTA? {
        // 无搜索结果 → "清除搜索" (通过 onClearFilters 触发: 清 searchText + 切回全部)
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return PhotoGridEmptyCTA(
                label: Copy.clearSearch,
                systemImage: "xmark.circle",
                onTap: { onClearFilters() }
            )
        }
        // 首次启动 (无任何 filter) → "导入图片"
        if showImport {
            return PhotoGridEmptyCTA(
                label: Copy.importAction,
                systemImage: "square.and.arrow.down",
                onTap: onImport
            )
        }
        return nil  // 其他场景无主 CTA (如回收站空、收藏空等)
    }

    private var secondaryAction: PhotoGridEmptyCTA? {
        // 无搜索结果 → "查看全部" (回到全部视图)
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return PhotoGridEmptyCTA(
                label: Copy.viewAll,
                onTap: { onClearFilters() }
            )
        }
        // folder/tag 模式空 → "查看全部"
        if folder != nil || tag != nil {
            return PhotoGridEmptyCTA(
                label: Copy.viewAll,
                onTap: { onClearFilters() }
            )
        }
        return nil
    }

    private var showImport: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty && !filterUnfiled
            && folder == nil && tag == nil && !filterDuplicates
            && !filterInTrash  // V3.6 NEW: 回收站空状态不显示导入按钮
    }

    // MARK: - 文案决策

    private var icon: String {
        // V4.36.x: 工具栏筛选激活 → 漏斗 icon
        if isFilterActive { return "line.3.horizontal.decrease.circle" }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "magnifyingglass" }
        // V5.8: 砍"收藏"图标分支
        if filterUnfiled { return "tray" }
        if folder != nil { return "folder" }
        if tag != nil { return "tag" }
        if filterDuplicates { return "doc.on.doc" }
        if filterRecent7Days { return "clock.arrow.circlepath" }
        if filterLargeFiles { return "large.circle" }
        if filterInTrash { return "trash" }  // V3.6 NEW
        return "photo.on.rectangle.angled"
    }

    private var text: String {
        // V4.36.x: 工具栏筛选激活但无匹配
        if isFilterActive { return Copy.emptyNoMatchFilter }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return Copy.emptyNoMatchSearch }
        // V5.8: 砍"收藏"空状态文本
        if filterUnfiled { return Copy.emptyUnfiled }
        if folder != nil { return Copy.emptyFolder }
        if tag != nil { return Copy.emptyTag }
        if filterDuplicates { return Copy.emptyDuplicates }
        if filterRecent7Days { return Copy.emptyRecent7Days }
        if filterLargeFiles { return Copy.emptyLargeFiles }
        if filterInTrash { return Copy.emptyRecycleBin }  // V3.6 NEW (Copy 已有)
        return Copy.emptyNoPhotosYet
    }

    private var hint: String {
        // V4.36.x: 提示调整筛选条件
        if isFilterActive { return Copy.hintFilterAdjust }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return Copy.hintSearchOther }
        // V5.8: 砍"收藏"空状态提示
        if filterUnfiled { return Copy.hintMoveToFolder }
        if folder != nil { return Copy.hintAutoImportToFolder }
        if tag != nil { return Copy.hintAddTagInDetail }
        if filterDuplicates { return Copy.hintDuplicatesAuto }
        if filterInTrash { return Copy.hintTrashAutoPurge(days: retentionDays) }  // V6.08: 不用 defaultValue
        return Copy.hintStartImport
    }
}
