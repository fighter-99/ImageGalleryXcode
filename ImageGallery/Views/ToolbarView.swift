//
//  ToolbarView.swift
//  ImageGallery
//
//  V4.3.0: 彻底重构——从「自绘 buttonStyle 系统」到「纯系统 Button + Label」
//
//  历史背景（git blame 友好）：
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
//  本文件 V4.3.0 保留 2 个组件：
//    - ToolbarSearchField：自绘搜索框（项目无 NavigationStack，.searchable 不可用）
//      简化为基础 TextField + 系统 .background(.quaternary, in: RoundedRectangle)
//    - ViewOptionsPopover：视图选项 popover 内容（独立 View，被 ContentView toolbar
//      的 Button.popover modifier 引用）
//

import SwiftUI

// MARK: - 视图选项 Popover（V4.3.0 抽出独立 struct）
//
// 从原 ToolbarViewOptionsButton.viewOptionsPopover 抽离。
// ContentView.toolbarContent 用原生 Button + .popover { ViewOptionsPopover(...) } 调用。
//
// 3 段：视图模式 / 缩放 / 排序
// popover 内部仍用自绘 segment（popover 是封闭空间，segmented control 内 active
//   满色填充是 macOS 标准；这里 OK，不算"toolbar 自绘"问题）
struct ViewOptionsPopover: View {
    @Binding var viewMode: ViewMode
    @Binding var thumbnailSize: CGFloat
    @Binding var sortOption: SortOption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 段 1: 视图模式
            popoverSection(title: "视图", icon: "square.grid.2x2") {
                HStack(spacing: 4) {
                    ForEach(ViewMode.allCases) { mode in
                        popoverSegmentItem(
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
                HStack(spacing: 4) {
                    ForEach(ThumbnailDensity.allCases) { density in
                        popoverSegmentItem(
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
                        popoverSortItem(
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
        .padding(Spacing.md)
        .frame(width: 240)
    }

    /// 段标题（icon + 小标题，Photos.app 风格）
    @ViewBuilder
    private func popoverSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content()
        }
    }

    /// popover 内的 segment item（封闭空间，accent 满色填充 OK）
    @ViewBuilder
    private func popoverSegmentItem(
        isActive: Bool,
        iconName: String,
        label: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(isActive ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isActive ? Color.accentColor : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// popover 内的 sort item（带 checkmark + direction icon）
    @ViewBuilder
    private func popoverSortItem(
        isActive: Bool,
        label: String,
        directionIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: directionIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? .white : .secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isActive ? .white : .primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
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
