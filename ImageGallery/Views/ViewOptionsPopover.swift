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
    // V5.17: 缩略图布局模式 3 选项（方格 / 按比例 / 按比例满行）
    //   紧跟缩放段——两者都是 grid cell 维度控制，逻辑分组相邻
    @Binding var thumbnailLayoutMode: ThumbnailLayoutMode
    @Binding var sortOption: SortOption

    var body: some View {
        // V4.78.0: 删 3 段头（视图/缩放/排序）+ 段头 icon + 1pt 分隔线
        //   仿 V4.61.0 FilterPopover 删段头——macOS Photos 扁平 menu 风格
        //   段间靠 10pt sectionSpacing 留白过渡（与 FilterPopover 一致）
        //
        // V5.3: 顶部加 "视图选项" header——跟 FilterTopPopover "筛选" header 视觉一致
        //   之前无 header——用户截图 16 比对筛选下拉后反馈"风格不一致"
        //   头部没标签→ 视觉上像孤儿弹窗；筛选有"筛选"两字作锚
        //   仿 V4.84.0 FilterTopPopoverViewController 范式：
        //     - 13pt semibold + labelColor（与"筛选"完全一致）
        //     - leading 对齐 padding 12pt
        //     - 上下用 sectionSpacing 10pt 与首段分隔
        VStack(alignment: .leading, spacing: PopoverStyle.sectionSpacing) {
            // V5.3: 顶部 header——对齐 Filter 范式
            Text("视图选项")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 段 1: 视图模式
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

            // 段 2: 缩放
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

            // 段 3: 布局（V5.17 新增）—— 方格 / 按比例 / 按比例满行 3 选项
            //   与缩放同段型：3 个 icon segment 横排
            //   紧跟缩放：两者都是 grid cell 维度控制，逻辑分组相邻
            HStack(spacing: PopoverStyle.segmentGap) {
                ForEach(ThumbnailLayoutMode.allCases) { mode in
                    PopoverSegmentItem(
                        isActive: thumbnailLayoutMode == mode,
                        iconName: mode.icon,
                        label: mode.displayName,
                        help: mode.displayName
                    ) {
                        thumbnailLayoutMode = mode
                    }
                }
            }

            // 段 4: 排序
            // V5.3: spacing 2 → 4pt 跟 Filter 段间呼吸感更对齐
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(PopoverStyle.padding)
        .frame(width: PopoverStyle.width)
    }

    /// 段标题（icon + 小标题，Photos.app 风格）
    /// V4.78.0: 砍 3 段头——body 内直接 HStack/VStack
    ///   仿 V4.61.0 FilterPopover 删段头范式
    @available(*, unavailable, message: "V4.78.0 砍 3 段头——body 内直接布局")
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
            // V4.62.0: 砍 1.015 scale + 15% white inner stroke 三重视觉锤
            //   macOS Photos 实际只用 1 锤（accent bg + tint icon）——见截图2
            //   砍 V4.52.0 strokeBorder——避免 transl 上 '凸起' 错觉
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
                // V5.3: minHeight 24 → 32pt——跟 FilterTop 32pt categoryRowHeight 对齐
                //   之前 24pt + 6pt padding × 2 = 36pt 跟 Filter 32pt 差 4pt——视觉不齐
                //   改用 categoryRowHeight——明确"这是 row 类不是 item 类"
                //   注：segment item 仍用 24pt+padding（icon+text 竖排需更高），与 sort 不同
                .frame(maxWidth: .infinity, minHeight: PopoverStyle.categoryRowHeight, alignment: .leading)
                .background(
                    bg,
                    in: RoundedRectangle(cornerRadius: PopoverStyle.itemCornerRadius, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            // V4.62.0: 砍 V4.51.0 active 1.015 scale 视觉锤——macOS Photos 实际只用 1 锤
            //   重复的 .animation 也合并掉
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
    @Previewable @State var layoutMode: ThumbnailLayoutMode = .square  // V5.34: .masonry → .square (跟默认)
    @Previewable @State var sort: SortOption = .importedAtDesc
    return ViewOptionsPopover(
        viewMode: $viewMode,
        thumbnailSize: $density,
        thumbnailLayoutMode: $layoutMode,  // V5.17
        sortOption: $sort
    )
}
