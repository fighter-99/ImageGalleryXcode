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

    var body: some View {
        EmptyStateView(
            icon: icon,
            title: text,
            subtitle: hint,
            iconColor: Color.accentColor.opacity(0.6),
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
                label: "清除搜索",
                systemImage: "xmark.circle",
                onTap: { onClearFilters() }
            )
        }
        // 首次启动 (无任何 filter) → "导入图片"
        if showImport {
            return PhotoGridEmptyCTA(
                label: "导入图片",
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
                label: "查看全部",
                onTap: { onClearFilters() }
            )
        }
        // folder/tag 模式空 → "查看全部"
        if folder != nil || tag != nil {
            return PhotoGridEmptyCTA(
                label: "查看全部",
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
        if isFilterActive { return "没有匹配筛选的图片" }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "没有匹配的图片" }
        // V5.8: 砍"收藏"空状态文本
        if filterUnfiled { return "没有待整理的图片" }
        if folder != nil { return "这个文件夹是空的" }
        if tag != nil { return "没有带此标签的图片" }
        if filterDuplicates { return "没有重复的图片" }
        if filterRecent7Days { return "最近 7 天没有新图" }
        if filterLargeFiles { return "没有大于 5 MB 的图" }
        if filterInTrash { return "回收站是空的" }  // V3.6 NEW
        return "还没有图片"
    }

    private var hint: String {
        // V4.36.x: 提示调整筛选条件
        if isFilterActive { return "尝试减少筛选条件或调整侧边栏" }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "试试其他关键词" }
        // V5.8: 砍"收藏"空状态提示
        if filterUnfiled { return "把图片移动到文件夹来整理" }
        if folder != nil { return "导入图片后会自动放到此文件夹" }
        if tag != nil { return "在详情中添加此标签" }
        if filterDuplicates { return "重复图会自动出现在这里" }
        if filterInTrash { return "删除的图片会出现在这里，\(TrashRetentionDays.defaultValue.rawValue) 天后自动永久清除" }  // V3.6 NEW
        return "拖入图片，或点击“导入图片”开始添加"
    }
}
