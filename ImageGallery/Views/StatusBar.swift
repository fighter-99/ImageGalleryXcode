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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(viewTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(viewSubtitle)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Spacing.md)

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

}
