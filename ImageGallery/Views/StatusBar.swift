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
    // V6.71 (取消 ContextualSelectionBar): 加 selectedCount 参数 — 选中 N 张时
    //   强化状态栏显示 "已选 N 张" + checkmark icon (V6.38.2 之前在此 + V6.64.1 a11y)
    //   替代之前 grid 顶部 44pt ContextualSelectionBar 的视觉提示
    let viewTitle: String
    let viewSubtitle: String
    let totalCount: Int
    let totalSize: String
    var selectedCount: Int = 0  // V6.71: 新参数, 默认 0 (无选中) 保持向后兼容

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

            // V6.71: 选中数指示 — 选中 >0 时在 statusBar 右侧显示 "已选 N 张"
            //   Photos.app Sonoma+ 实测: 选中时 status bar 末尾显示 selectedCount
            //   视觉锤: accent tint + checkmark icon + 中等字号
            if selectedCount > 0 {
                Spacer(minLength: Spacing.md)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(Copy.selectedCount(selectedCount))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Spacer(minLength: Spacing.md)
            }

        }
        // V6.64.1 (A11y): 状态栏整行作为单一 a11y 元素 — VoiceOver 朗读时一次性听到完整信息
        //   "当前视图 [viewTitle], N 张照片, 总大小 X MB" 而不是分两次朗读
        // V6.71: 选中时 a11y label 加 "已选 N 张" 信息
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .animation(Animations.standard, value: selectedCount)
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

    // V6.71: a11y label 拼接 — 选中时附加 selectedCount
    private var accessibilityText: String {
        if selectedCount > 0 {
            return "\(viewTitle), \(viewSubtitle), 已选 \(selectedCount) 张"
        }
        return "\(viewTitle), \(viewSubtitle)"
    }
}
