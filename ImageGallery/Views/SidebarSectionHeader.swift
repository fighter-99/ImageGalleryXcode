//
//  SidebarSectionHeader.swift
//  ImageGallery
//
//  V3.5.8 侧栏精修：自定义 section header。
//  V3.5.14 Photos.app 风格：small caps + tertiary 色 + 较小字号
//  V3.6.21 强化：加可选 SF Symbol 小图标，每个 section 视觉锚点更明确
//  V4.1.0 NEW: 加可折叠 chevron——整个 header 区域可点击切换展开/折叠
//              折叠状态用 @AppStorage 持久化（用户偏好）
//  V4.6.0: token 化——所有视觉常量改用 SidebarStyle.* token
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
    /// V6.13.4 NEW: section item 总数（"我的文件夹" / "标签" 用，nil = 不显示）
    ///   Photos.app 范式: section header 显示括号内数字, 跟 item 末 count badge 区分
    ///   (item badge 是单 row 计数, header count 是 section 总数)
    var count: Int? = nil

    /// V4.1.0 NEW: 折叠状态 binding
    @Binding var isExpanded: Bool

    /// P4.1.1 NEW: header 右侧 "+" 按钮 (跟 section 主题一致, e.g. 智能文件夹创建)
    ///   V1: nil = 不显示按钮 (向后兼容现有 4 个 caller)
    /// V6.23 (回滚): 移除 addAction — 改成 chevron 模式 (menuItems), 跟智能文件夹创建入口统一
    ///   现在 header 创建入口靠 menuItems (chevron 点击出 menu), 不再有 + button
    var addAction: (() -> Void)? = nil
    /// P4.1.1 NEW: "+" 按钮的可访问性标签 + help tooltip
    var addAccessibilityLabel: String = "新建"

    /// V6.23 NEW: chevron menu 模式 — 提供菜单项数组后, 点击 chevron 出 menu (不再 toggle 展开)
    ///   用于智能文件夹 section: 菜单 = [新建智能文件夹, 展开/折叠]
    ///   设计理由: smart folder 创建是 power user 动作, 走 menu 降低误触 (跟 Photos Smart Albums 一致)
    ///   nil 或空数组 = 标准 toggle 模式 (默认所有 section)
    var menuItems: [HeaderMenuItem] = []

    /// V6.23 NEW: menu item 数据 — 标题 + SF Symbol + 回调
    /// V6.23.1: 改 enum 支持 `.divider` case — action 跟 toggle 视觉分层
    ///   enum 比 struct + flag 更清晰 (Swift 模式匹配自然)
    enum HeaderMenuItem: Identifiable {
        case action(label: String, systemImage: String? = nil, action: () -> Void)
        case divider

        var id: String {
            switch self {
            case .action: return "action-\(UUID().uuidString)"
            case .divider: return "divider-\(UUID().uuidString)"
            }
        }
    }

    // V6.21.3 (Phase 1.4 UX polish): hover state — 整个 header 区域轻微 background tint
    //   之前整个 header 区域可点击切换折叠 (V4.1.0) 但 hover 无视觉反馈, 跟 SidebarRow 不一致
    //   现在 hover 时 chevron + "+" button + icon 颜色加深 + 轻微 background tint
    @State private var isHovered = false

    init(
        _ title: String,
        icon: String? = nil,
        count: Int? = nil,
        isExpanded: Binding<Bool> = .constant(true),
        addAction: (() -> Void)? = nil,
        addAccessibilityLabel: String = "新建",
        // V6.23 NEW: chevron menu 模式 (智能文件夹 section 用)
        //   非空时 chevron 点击出 menu, 不再 toggle 展开
        menuItems: [HeaderMenuItem] = []
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self._isExpanded = isExpanded
        self.addAction = addAction
        self.addAccessibilityLabel = addAccessibilityLabel
        self.menuItems = menuItems
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
        HStack(spacing: SidebarStyle.headerIconSpacing) {
            if let icon {
                Image(systemName: icon)
                    .font(SidebarStyle.headerFont)
                    // V6.21.3: hover 时从 secondary → primary, 视觉锤
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            Text(title)
                .font(SidebarStyle.headerFont)
                // V6.21.3: hover 时从 headerColor → primary, 视觉锤
                .foregroundStyle(isHovered ? .primary : SidebarStyle.headerColor)
                .textCase(.uppercase)  // ⭐ Photos.app 风格：small caps

            // V6.13.4 NEW: section item 总数 (括号样式, Photos.app 范式)
            if let count {
                Text("(\(count))")
                    .font(SidebarStyle.headerFont)
                    .foregroundStyle(isHovered ? .primary : SidebarStyle.headerColor)
            }

            Spacer()

            // P4.1.1 NEW: header "+" 按钮 (Library section 用, 触发 smart folder 创建 sheet)
            //   位置: Spacer 后, chevron 前 — 视觉跟 title 距离更近, 跟 Folders section 已有 "+" 一致
            if let addAction {
                Button(action: addAction) {
                    Image(systemName: "plus")
                        .font(SidebarStyle.headerFont)
                        // V6.21.3: hover 时 plus button 颜色加深
                        .foregroundStyle(isHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(addAccessibilityLabel)
                .accessibilityLabel(addAccessibilityLabel)
            }

            // V4.1.0 NEW: chevron（▶ → ▼ 旋转）
            // V6.23: menu 模式 — 提供 menuItems 时点击 chevron 出 menu (不再 toggle 展开)
            //   智能文件夹 section 用这模式: 菜单 [新建智能文件夹, 展开/折叠]
            if menuItems.isEmpty {
                // 标准模式: 点击 chevron toggle 展开
                Image(systemName: "chevron.right")
                    .font(SidebarStyle.headerFont)
                    .foregroundStyle(isHovered ? .primary : SidebarStyle.headerColor)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(Animations.interactive, value: isExpanded)
            } else {
                // Menu 模式: 点击 chevron 出 menu
                // V6.23.1: icon 改 ellipsis.circle — 跟标准 chevron (toggle) 视觉区分
                //   删 rotationEffect (menu 模式点击不是 toggle, 旋转动画误导用户)
                //   .menuIndicator(.hidden) 隐藏 menu 自带的小箭头 (不想要 menu 暗示 chevron 还能 toggle)
                Menu {
                    ForEach(menuItems) { item in
                        switch item {
                        case .divider:
                            Divider()
                        case let .action(label, systemImage, action):
                            Button {
                                action()
                            } label: {
                                if let systemImage {
                                    Label(label, systemImage: systemImage)
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(SidebarStyle.headerFont)
                        .foregroundStyle(isHovered ? .primary : SidebarStyle.headerColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SidebarStyle.headerPaddingHorizontal)
        .padding(.top, SidebarStyle.headerPaddingTop)
        .padding(.bottom, SidebarStyle.headerPaddingBottom)
        // V6.21.3: hover 时轻微 background tint (跟 SidebarRow hoverBackground 风格一致)
        .background(
            isHovered
                ? SidebarStyle.hoverBackground.opacity(0.5)  // 比 row 轻 (header 不该抢戏)
                : Color.clear
        )
        .contentShape(Rectangle())  // 让整个 header 区域可点击
        .onTapGesture {
            // V4.1.0: 点击切换折叠
            // V6.23: menu 模式下不 toggle (chevron 自己处理点击)
            if menuItems.isEmpty {
                isExpanded.toggle()
            }
        }
        // V6.22.2 (P2 #8): VoiceOver 标签 — section header hint
        //   hint 描述折叠状态 + 操作 ("单击切换折叠, 当前已展开 / 已折叠")
        .accessibilityLabel(title)
        .accessibilityHint(isExpanded ? "单击折叠" : "单击展开")
        .accessibilityAddTraits(isExpanded ? [] : [.isHeader])
        // V6.21.3: hover 检测 — onHover 跟 SidebarRow 同 pattern
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(Animations.springGentle, value: isHovered)
    }
}
