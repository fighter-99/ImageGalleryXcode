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
    // V6.52: viewTitle + viewSubtitle 加回来 — V6.38.1 简化过头让 StatusBar 太空
    //   决策: A 加内容 (用户选) — viewTitle 给当前视图语义 (所有照片/folder name/#tag),
    //   viewSubtitle 给 N 张 · X MB, 后跟缩略图档位
    let viewTitle: String
    let viewSubtitle: String
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
        // V6.52: 加 viewTitle + viewSubtitle — V6.38.1 简化过头让 StatusBar 太空 (3 项 + 2 分隔符)
        //   现在 4 段: [viewTitle] · [viewSubtitle] · [thumbnail tier], 中间用 caption 分隔符 (不等宽),
        //   数字部分仍用 captionMono (等宽)
        HStack(spacing: Spacing.sm) {
            // 视图标题 — 所有照片 / folder 名 / #tag / 智能文件夹名 / 最近删除
            // V6.52: 用 .font(.callout.weight(.medium)) + .primary — 比其他项略重 + 更深,
            //   视觉锤 "当前在看哪个视图"
            Text(viewTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            // 视图副标题 — N 张 · X MB (+ 已筛选 N 跟 toolbar 同步)
            // V6.52: captionMono 等宽数字 + caption 不等宽文字混合节奏
            //   " · " 用 caption 不等宽避免视觉拥挤
            Text(viewSubtitle)
                .font(Typography.captionMono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Spacing.md)

            // V5.60-7: 缩略图档位 ("中 200pt" / "大 250pt")——Photos 风格
            //   跟 .controlSize 档位 (compact/small/medium/large) 映射
            Text(thumbnailSizeLabel)
                .font(Typography.caption)
                .foregroundStyle(.tertiary)
        }
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
}
