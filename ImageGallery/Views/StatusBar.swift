//
//  StatusBar.swift
//  ImageGallery
//
//  V3.5.6 Finder 化：底部状态栏。
//  类似 macOS Finder 底部的状态信息：总照片数 / 占用空间 / 选中数。
//
//  视觉规范：
//  - 高度 24pt
//  - 浅灰背景（Surface.panel）
//  - 顶部 0.5pt 分隔线
//  - 数字用 Typography.captionMono（等宽数字）
//

import SwiftUI

struct StatusBar: View {
    let totalCount: Int
    let totalSize: String
    // V5.60-7: 缩略图大小 (CGFloat) — 唯一保留的全局 meta
    //   删 (V6.38.1): selectedCount / activeFilterCount / importProgress
    //   理由: 重复 — 选中数/筛选条件数/导入进度都搬到触发按钮附近
    let thumbnailSize: CGFloat

    var body: some View {
        // V6.38.1 (Phase 1): StatusBar 简化 — 只保留全局 meta
        //   删: 选中数 (V5.60-7), 筛选条件数 (V5.60-7), 导入进度 (V5.15)
        //   理由: 3 处跟其他 surface 重复
        //     - 选中数 → SelectionMiniToolbar 已显示 ("X 张已选")
        //     - 筛选条件数 → ToolbarController filter button badge (V6.29.2 红点 + count)
        //     - 导入进度 → Import 按钮 progress ring (Phase 1 同时加)
        //   Photos.app 范式: 底部状态栏只显示全局 meta,临时状态在触发它的按钮附近
        HStack(spacing: Spacing.sm) {
            // 总数
            Text(Copy.totalCount(totalCount))

            separator

            // 占用空间
            Text(totalSize)

            // V5.60-7: 缩略图档位 ("中 200pt" / "大 250pt")——Photos 风格
            //   跟 .controlSize 档位 (compact/small/medium/large) 映射
            separator
            Text(thumbnailSizeLabel)

            Spacer(minLength: 0)
        }
        .font(Typography.captionMono)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
        // V4.0.0: 改用 .regularMaterial 替代 Surface.panel（NSColor.controlBackgroundColor）
        //   半透明 + blur 背景，让 status bar 与主内容区视觉分层
        .background(Material.statusBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Surface.separator)
                .frame(height: 0.5)
        }
    }

    /// V5.60-7: 缩略图档位 label——4 档 (compact/small/medium/large) 映射中文
    ///   70 → 特小, 110 → 小, 200 → 中 (default), 250 → 大
    private var thumbnailSizeLabel: String {
        // V6.12: 走 Copy 字典 (4 档)——之前 hardcoded, i18n 漏改风险
        switch thumbnailSize {
        case ..<80:    return Copy.thumbnailSizeCompact
        case ..<150:   return Copy.thumbnailSizeSmall
        case ..<220:   return Copy.thumbnailSizeMedium
        default:       return Copy.thumbnailSizeLarge
        }
    }

    /// 中点分隔符
    private var separator: some View {
        Text(Copy.statusSeparator)
            .foregroundStyle(.tertiary)
    }
}
