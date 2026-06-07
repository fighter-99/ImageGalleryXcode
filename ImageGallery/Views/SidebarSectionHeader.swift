//
//  SidebarSectionHeader.swift
//  ImageGallery
//
//  V3.5.8 侧栏精修：自定义 section header。
//  V3.5.14 Photos.app 风格：small caps + tertiary 色 + 较小字号
//  V3.6.21 强化：加可选 SF Symbol 小图标，每个 section 视觉锚点更明确
//
//  Photos.app 风格：
//  - small caps + caption2 + semibold + tertiary 色
//  - 上下 padding 留出视觉分组空间
//

import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    /// V3.6.21 NEW: 可选 SF Symbol 小图标（跟 title 在同一行）
    var icon: String? = nil

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)  // ⭐ Photos.app 风格：small caps
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
