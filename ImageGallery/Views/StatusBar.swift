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
    let selectedCount: Int
    // V5.15: 导入进度——nil 表示未在导入
    let importProgress: ImportProgress?
    // V5.60-7: 缩略图大小 (CGFloat) + active filter count (Int)——Photos 风格 status bar 增强
    let thumbnailSize: CGFloat
    let activeFilterCount: Int

    var body: some View {
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

            // 选中数（仅在有选中时显示，更突出）
            if selectedCount > 0 {
                separator
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text(Copy.selectedCount(selectedCount))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 0)

            // V5.60-7: active filter count (条件) — 当 filterState.activeCount > 0 显示
            if activeFilterCount > 0 {
                separator
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text(Copy.activeFilterBadge(activeFilterCount))
                        .foregroundStyle(Color.accentColor)
                }
            }

            // V5.15: 导入进度——右侧显示"导入中 8/15 · 1 失败"
            //   比原"current/total"更准确（含 inserted/failureCount）
            if let progress = importProgress, progress.isImporting {
                separator
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text(progress.displayText)
                        .foregroundStyle(Color.accentColor)
                }
            }
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
