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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // 总数
            Text("\(totalCount) 张照片")

            separator

            // 占用空间
            Text(totalSize)

            // 选中数（仅在有选中时显示，更突出）
            if selectedCount > 0 {
                separator
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text("已选 \(selectedCount) 张")
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .font(Typography.captionMono)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.md)
        .frame(height: 24)
        .background(Surface.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Surface.separator)
                .frame(height: 0.5)
        }
    }

    /// 中点分隔符
    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }
}
