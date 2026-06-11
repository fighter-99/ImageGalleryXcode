//
//  ViewOptionsPopover.swift
//  ImageGallery
//
//  V4.3.0 抽出——从原 ToolbarViewOptionsButton.viewOptionsPopover 抽离
//  V4.40.0: 文件重命名 ToolbarView.swift → ViewOptionsPopover.swift
//    - V4.8.0 NSToolbar 接管后 ToolbarView 整体清仓（V4.15.0 删 7 个自绘 struct 共 400 行）
//    - V4.15.0 进一步删 ToolbarSearchField struct
//    - 本文件 193 行只剩 ViewOptionsPopover 1 个组件——文件名应匹配内容
//
//  V4.9.1 进化：ContentView 用 NSPopover + NSHostingController 包本 View
//    仿 V4.36.x Filter popover 模式——状态在 ContentView 通过 @Binding 双向改
//
//  3 段：视图模式 / 缩放 / 排序
//  popover 内部仍用自绘 segment（popover 是封闭空间，segmented control 内 active
//    满色填充是 macOS 标准；这里 OK，不算"toolbar 自绘"问题）
//
//  旧 ToolbarView.swift 留下的 6 个自绘 struct（V4.15.0 已删）历史：
//    V4.0.0.3 引入 Arc 块状语言（每个 item 自绘 Capsule 底）
//    V4.2.0 → V4.2.4 在自绘方向上反复调（5 轮 opacity/material/形状），始终不"原生"
//    V4.3.0 承认根本错误：自绘 buttonStyle 永远比不上系统 NSToolbarItem
//           删 ToolbarIconButton / ToolbarSidebarToggle / ToolbarImportButton /
//             ToolbarSegmentItem / ToolbarSortMenu / ToolbarViewModeSegment /
//             ToolbarDensitySegment 共 7 个自绘 struct（约 400 行）
//           ContentView.toolbarContent 改用 SwiftUI 原生 Button + Label，
//             让系统接管 hover / focus / pressed / 深浅模式 / vibrancy /
//             disabled 颜色 / Symbol 字重 / VoiceOver
//           Import 用 .buttonStyle(.borderedProminent) 系统 CTA
//
//  V4.8.0 + V4.8.1 进化：Search field 用 NSSearchToolbarItem (AppKit 原生) 替代 SwiftUI 自绘
//    旧 ToolbarSearchField（V4.8.1 删）已 dead——NSToolbar.search item 完全接管
//

import SwiftUI

// MARK: - 视图选项 Popover（V4.3.0 抽出独立 struct）
//
// 从原 ToolbarViewOptionsButton.viewOptionsPopover 抽离。
// ContentView.toolbarContent 用原生 Button + .popover { ViewOptionsPopover(...) } 调用。
struct ViewOptionsPopover: View {
    @Binding var viewMode: ViewMode
    @Binding var thumbnailSize: CGFloat
    @Binding var sortOption: SortOption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 段 1: 视图模式
            popoverSection(title: "视图", icon: "square.grid.2x2") {
                HStack(spacing: PopoverStyle.segmentGap) {
                    ForEach(ViewMode.allCases) { mode in
                        PopoverSegmentItem(
                            isActive: viewMode == mode,
                            iconName: mode.icon,
                            label: mode.label,
                            help: mode.label
                        ) {
                            viewMode = mode
                        }
                    }
                }
            }

            Divider().padding(.vertical, 8)

            // 段 2: 缩放
            popoverSection(title: "缩放", icon: "square.grid.3x3") {
                HStack(spacing: PopoverStyle.segmentGap) {
                    ForEach(ThumbnailDensity.allCases) { density in
                        PopoverSegmentItem(
                            isActive: ThumbnailDensity.nearest(to: thumbnailSize) == density,
                            iconName: density.icon,
                            label: density.label,
                            help: "\(Int(density.size))pt"
                        ) {
                            thumbnailSize = density.size
                        }
                    }
                }
            }

            Divider().padding(.vertical, 8)

            // 段 3: 排序
            popoverSection(title: "排序", icon: "arrow.up.arrow.down") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SortOption.allCases) { option in
                        PopoverSortItem(
                            isActive: sortOption == option,
                            label: option.label,
                            directionIcon: option.directionIcon
                        ) {
                            sortOption = option
                        }
                    }
                }
            }
        }
        .padding(PopoverStyle.padding)
        .frame(width: PopoverStyle.width)
    }

    /// 段标题（icon + 小标题，Photos.app 风格）
    /// V4.41.0: 全部 token 化（caption2 + uppercase + 4pt icon 间距）——与 FilterPopover 对齐
    /// V4.43.1: 加底边分隔线（0.5pt 6% primary）——段间视觉分组更明确
    @ViewBuilder
    private func popoverSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: PopoverStyle.headerIconSpacing) {
                Image(systemName: icon)
                    .font(.system(size: PopoverStyle.headerIconSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: PopoverStyle.headerFontSize, weight: PopoverStyle.headerWeight))
                    .foregroundStyle(.secondary)
                    .textCase(PopoverStyle.headerUppercased ? .uppercase : nil)
            }
            // V4.43.1: 底边分隔线——macOS Photos 风格
            Rectangle()
                .fill(PopoverStyle.headerSeparatorColor)
                .frame(height: PopoverStyle.headerSeparatorHeight)
            content()
        }
    }

    /// popover 内的 segment item（封闭空间，accent 满色填充 OK）
    /// V4.41.0: itemHeight / cornerRadius / active+inactive colors 全 token 化
    /// V4.42.0: icon 14pt → 16pt + 4pt 垂直 padding——icon 与 item 边界不贴紧
    /// V4.43.0: hover bg——inactive items 鼠标悬停时 10% → 14%
    /// V4.43.0: 抽到独立 View struct（@State 必须在 struct property）—— 8 个独立 hover state
    private struct PopoverSegmentItem: View {
        let isActive: Bool
        let iconName: String
        let label: String
        let help: String
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            let bg: Color = {
                if isActive { return PopoverStyle.activeBackground }
                if isHovered { return PopoverStyle.hoverBackground }
                return PopoverStyle.inactiveBackground
            }()

            return Button(action: action) {
                VStack(spacing: 2) {
                    Image(systemName: iconName)
                        .font(.system(size: PopoverStyle.iconFontSize, weight: .medium))
                    Text(label)
                        .font(.caption2)
                }
                .foregroundStyle(isActive ? PopoverStyle.activeText : PopoverStyle.inactiveText)
                .padding(.vertical, PopoverStyle.itemVerticalPadding)
                .padding(.horizontal, PopoverStyle.itemHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: PopoverStyle.itemHeight)
                .background(
                    bg,
                    in: RoundedRectangle(cornerRadius: PopoverStyle.itemCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            // V4.43.1: 状态变化动画——active/inactive bg 切换 0.15s easeInOut
            //   hover bg 切换不加 .animation——mouse 移动会触发频繁 re-render
            .animation(.easeInOut(duration: PopoverStyle.stateTransitionDuration), value: isActive)
            // V4.52.0: active 状态加 inset shadow——macOS Photos selected button 风格
            //   "按下去"反馈：bg accent + 1.015 scale + inset shadow 三重视觉锤
            //   SwiftUI shadow inset 用 .background + RoundedRectangle stroke 模拟
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: PopoverStyle.itemCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .help(help)
        }
    }

    /// popover 内的 sort item（带 checkmark + direction icon）
    /// V4.41.0: 颜色 + cornerRadius + height 全 token 化
    /// V4.42.0: icon 12pt → 14pt + 4pt 垂直 padding——视觉与 segment item 一致
    /// V4.43.0: hover bg + 字号 13pt → 12pt
    private struct PopoverSortItem: View {
        let isActive: Bool
        let label: String
        let directionIcon: String
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            let bg: Color = {
                if isActive { return PopoverStyle.activeBackground }
                if isHovered { return PopoverStyle.hoverBackground }
                return .clear
            }()

            return Button(action: action) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: PopoverStyle.sortItemFontSize))
                        .foregroundStyle(isActive ? PopoverStyle.activeText : PopoverStyle.inactiveText)
                    Spacer()
                    // V4.51.0: arrow 移到右侧——macOS Photos sort 风格
                    //   之前 arrow 在 label 左边——"label icon"语义
                    //   现在 arrow 在 label 右边——"方向指示"语义（↑↓）
                    Image(systemName: directionIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isActive ? PopoverStyle.activeText : .secondary)
                        .frame(width: 18)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, PopoverStyle.itemVerticalPadding)
                .frame(maxWidth: .infinity, minHeight: PopoverStyle.itemHeight, alignment: .leading)
                .background(
                    bg,
                    in: RoundedRectangle(cornerRadius: PopoverStyle.itemCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            // V4.51.0: active 1.015 scale——V4.17.0 cell pattern 锦上添花
            //   scaleEffect 在 background 之后——active 时 icon+text 微放大
            //   视觉上"被选中"——accent bg 之外第二重视觉锤
            .scaleEffect(isActive ? 1.015 : 1.0)
            .animation(.easeInOut(duration: PopoverStyle.stateTransitionDuration), value: isActive)
            .animation(.easeInOut(duration: PopoverStyle.stateTransitionDuration), value: isActive)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview("ViewOptionsPopover") {
    @Previewable @State var viewMode: ViewMode = .grid
    @Previewable @State var density: CGFloat = 170
    @Previewable @State var sort: SortOption = .importedAtDesc
    return ViewOptionsPopover(
        viewMode: $viewMode,
        thumbnailSize: $density,
        sortOption: $sort
    )
}
