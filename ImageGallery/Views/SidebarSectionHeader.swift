//
//  SidebarSectionHeader.swift
//  ImageGallery
//
//  V3.5.8 侧栏精修：自定义 section header。
//  V3.5.14 Photos.app 风格：small caps + tertiary 色 + 较小字号
//  V3.6.21 强化：加可选 SF Symbol 小图标，每个 section 视觉锚点更明确
//  V4.1.0 NEW: 加可折叠 chevron——整个 header 区域可点击切换展开/折叠
//              折叠状态用 @AppStorage 持久化（用户偏好）
//
//  Photos.app 风格：
//  - small caps + caption2 + semibold + tertiary 色
//  - 上下 padding 留出视觉分组空间
//  - chevron ▶ / ▼ 旋转动画（spring）
//

import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    /// V3.6.21 NEW: 可选 SF Symbol 小图标（跟 title 在同一行）
    var icon: String? = nil

    /// V4.1.0 NEW: 折叠状态 binding
    @Binding var isExpanded: Bool

    init(_ title: String, icon: String? = nil, isExpanded: Binding<Bool> = .constant(true)) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
    }

    /// V4.1.0 便利构造：可折叠 + 自动持久化（推荐用这个）
    /// - storageKey 唯一标识 section（用于 UserDefaults 持久化）
    /// - 默认展开 = true
    init(_ title: String, icon: String? = nil, storageKey: String) {
        self.title = title
        self.icon = icon
        self._isExpanded = Binding(
            get: { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: storageKey) }
        )
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

            Spacer()

            // V4.1.0 NEW: chevron（▶ → ▼ 旋转）
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(Animations.interactive, value: isExpanded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())  // 让整个 header 区域可点击
        .onTapGesture {
            // V4.1.0: 点击切换折叠
            isExpanded.toggle()
        }
    }
}
