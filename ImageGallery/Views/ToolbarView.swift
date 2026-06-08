//
//  ToolbarView.swift
//  ImageGallery
//
//  V3.4 重设计：极简 4 元素工具栏。
//
//  元素（按用户指定）：
//  - 🔍 搜索
//  - ⊞ ≡ 📅 视图模式
//  - ▦▦▦ 缩放（缩略图大小）
//  - ↓ 导入
//
//  设计原则：
//  - V3.0：稳定主工具栏（不因选中/筛选而变化）
//  - V3.1：Surface tokens 统一（背景 / 分隔线 / 字体）
//  - V3.2：segments 默认无背景，hover/active 时显示（Photos.app 化）
//  - V3.3：.buttonStyle(.plain) 避免系统黑色背景叠加
//
//  视觉权重：
//  L2 [🔍 搜索]
//  L3 [⊞≡📅] [▦▦▦]
//  L1 [↓ 导入]   ← 主操作
//

import SwiftUI

struct ToolbarView: View {
    // ─── 基础状态 ───
    @Binding var searchText: String
    let onImport: () -> Void

    // ─── 视图模式 + 缩放 + 排序 ───
    @Binding var viewMode: ViewMode
    let thumbnailSize: Binding<CGFloat>
    @Binding var sortOption: SortOption  // V3.5 Phase 1：加回排序

    // V3.5.15：侧栏显隐按钮已移至 title bar（ToolbarItem .navigation）
    // 工具栏内不再重复，保留原生 ⊟ 唯一入口

    // V3.5 Phase 1 Step 3：分享按钮（context-sensitive）
    let onShare: () -> Void
    let hasSelection: Bool

    // V3.5 Phase 1 Step 4：撤销/重做
    let onUndo: () -> Void
    let onRedo: () -> Void
    let canUndo: Bool
    let canRedo: Bool

    // 统一规范
    private let toolbarHeight: CGFloat = 44
    private var currentDensity: ThumbnailDensity {
        ThumbnailDensity.nearest(to: thumbnailSize.wrappedValue)
    }

    // V3.5.5 方向 C2：所有图标统一 SF Symbol weight
    private let iconWeight: Font.Weight = .medium

    // V3.6.23: ⌘F 聚焦搜索框的 @FocusState
    @FocusState private var searchFieldFocused: Bool

    // V3.6.18: 组之间视觉分隔符（0.5pt × 16pt vertical line，Surface.separator 色）
    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Surface.separator)
            .frame(width: 0.5, height: 16)
    }

    init(
        searchText: Binding<String>,
        onImport: @escaping () -> Void,
        viewMode: Binding<ViewMode>,
        thumbnailSize: Binding<CGFloat>,
        sortOption: Binding<SortOption>,  // V3.5 Phase 1
        onShare: @escaping () -> Void,  // V3.5 Phase 1 Step 3
        hasSelection: Bool,
        onUndo: @escaping () -> Void,  // V3.5 Phase 1 Step 4
        onRedo: @escaping () -> Void,
        canUndo: Bool,
        canRedo: Bool
    ) {
        self._searchText = searchText
        self.onImport = onImport
        self._viewMode = viewMode
        self.thumbnailSize = thumbnailSize
        self._sortOption = sortOption
        self.onShare = onShare
        self.hasSelection = hasSelection
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.canUndo = canUndo
        self.canRedo = canRedo
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {  // V3.5.5 方向 C4：组间距 20pt（之前 12pt）
            // ─── 左右 Spacer：让所有控件整体居中 ───
            Spacer(minLength: 0)

            // ─── A 组：撤销/重做（macOS 标准位置：最左） ───
            // 组内 0pt
            undoButton
            redoButton

            // V3.6.18: A | B 分隔符
            toolbarSeparator

            // ─── B 组：搜索 + 显示控制（输入 + 视图） ───
            // 组内 8pt
            HStack(spacing: Spacing.sm) {
                searchField
                    .frame(width: 200)  // V3.5.5 C1：搜索框 240 → 200pt
                viewModeSegment
                densitySegment
                sortMenu             // V3.5 Phase 1：排序
            }

            // V3.6.18: B | C 分隔符
            toolbarSeparator

            // ─── C 组：工具操作 ───
            // 组内 8pt
            HStack(spacing: Spacing.sm) {
                shareButton          // V3.5 Phase 1 Step 3
                importButton         // 主操作
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: toolbarHeight)
        // V3.4 修复 3：彻底弃用系统 .toolbar 后，给"假工具栏"明确的画布背景
        // 原因：现在 ToolbarView 是普通 View（不是 system toolbar item），
        //      没有系统 chrome 冲突，Surface.canvas 可以安全使用。
        .background(Surface.canvas)
        // 底部分隔线（视觉锚点）
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Surface.separator)
                .frame(height: 0.5)
        }
    }

    // MARK: - 子组件

    /// 搜索框（V3.6.20：容器改 Capsule，跟 viewMode/density/sortMenu 一致）
    /// V3.6.23: 加 .focused($searchFieldFocused)，让 ⌘F 快捷键能聚焦
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("搜索文件名、标签、备注", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($searchFieldFocused)  // V3.6.23: ⌘F focus 目标
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(Surface.toolbarControl, in: Capsule())
        // V3.6.43: 搜索框 focus 时加微阴影，提示当前可输入
        .shadow(color: searchFieldFocused ? Color.accentColor.opacity(0.3) : .clear, radius: 4)
        .animation(Animations.springGentle, value: searchFieldFocused)
        // V3.6.23: 监听 ⌘F notification 设 focus
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            searchFieldFocused = true
        }
    }

    /// 视图模式 3 档（V3.6.18：加 text 标签 — 让用户清楚当前选的是什么）
    private var viewModeSegment: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases) { mode in
                ToolbarSegmentItem(
                    isActive: viewMode == mode,
                    iconName: mode.icon,
                    label: mode.label,
                    help: mode.label
                ) {
                    viewMode = mode
                }
            }
        }
        .frame(height: 28)
        .background(Surface.toolbarControl, in: Capsule())
    }

    /// 缩放（缩略图大小）3 档（V3.6.16：加 segmented Capsule 背景 + hover 反馈）
    private var densitySegment: some View {
        HStack(spacing: 0) {
            ForEach(ThumbnailDensity.allCases) { density in
                ToolbarSegmentItem(
                    isActive: currentDensity == density,
                    iconName: density.icon,
                    help: "缩略图大小：\(density.label)（\(Int(density.size))pt）"
                ) {
                    thumbnailSize.wrappedValue = density.size
                }
            }
        }
        .frame(height: 28)
        .background(Surface.toolbarControl, in: Capsule())
    }

    /// 排序菜单（V3.6.16：加 hover 反馈 + segmented 容器视觉）
    /// 显示当前排序方式（方向图标 + 简短文字）
    /// 点击展开 6 种排序选项
    private var sortMenu: some View {
        ToolbarSortMenu(
            currentLabel: sortOption.shortLabel,
            directionIcon: sortOption.directionIcon,
            fullHelp: "排序方式：\(sortOption.label)（⌘⇧S 切换方向）"
        ) {
            ForEach(SortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.label)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    /// 撤销按钮（V3.6.16：加 hover 反馈）
    private var undoButton: some View {
        ToolbarIconButton(
            systemImage: "arrow.uturn.backward",
            isEnabled: canUndo,
            help: "撤销 (⌘Z)",
            action: onUndo
        )
    }

    /// 重做按钮（V3.6.16：加 hover 反馈）
    private var redoButton: some View {
        ToolbarIconButton(
            systemImage: "arrow.uturn.forward",
            isEnabled: canRedo,
            help: "重做 (⌘⇧Z)",
            action: onRedo
        )
    }

    /// 分享按钮（V3.6.16：加 hover 反馈）
    /// Context-sensitive：未选中照片时灰显
    private var shareButton: some View {
        ToolbarIconButton(
            systemImage: "square.and.arrow.up",
            isEnabled: hasSelection,
            help: hasSelection ? "分享选中的照片" : "请先选中照片",
            action: onShare
        )
    }

    /// 导入按钮（V3.6.19：改 .borderedProminent + accent 色背景，Photos.app 主操作风格）
    private var importButton: some View {
        Button {
            onImport()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                Text("导入")
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(Color.accentColor)
        .help("导入图片 (⌘O)")
    }
}

// MARK: - V3.6.16 NEW: 工具栏 segment + icon 按钮组件
//
// 抽这两个组件是为了让 4 个 segments + 4 个 icon 按钮共享：
// 1. 14pt medium weight SF Symbol（统一 icon 风格）
// 2. 26x22 frame 按钮命中区
// 3. hover 反馈（Surface.hover 圆角背景）
// 4. disabled 灰显（.secondary.opacity(0.4)）
// 5. active 项 accent.opacity(0.15) 高亮（仅 segment）
// 6. accent 色 / secondary 色（仅 segment）

/// 工具栏 segmented item（带 hover + active 背景 + 可选 text 标签）
/// - isActive: 当前选中此项（accent 背景 + accent 色 label）
/// - 非 active + hover: Surface.hover 背景
/// - 非 active + 非 hover: 透明
/// - label: nil = 纯 icon；非 nil = icon + text（text 用 caption 字号）
private struct ToolbarSegmentItem: View {
    let isActive: Bool
    let iconName: String
    var label: String? = nil
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                if let label {
                    Text(label)
                        .font(Typography.caption)
                }
            }
            .padding(.horizontal, label == nil ? 0 : 8)
            .frame(height: 22)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(backgroundColor)
                .padding(2)  // 让 active/hover 圆角背景在 segment 容器内略缩进
        )
        .onHover { hovering in isHovered = hovering }
        .animation(Animations.quick, value: isHovered)
        .animation(Animations.quick, value: isActive)
        .help(help)
    }

    private var backgroundColor: Color {
        if isActive { return Color.accentColor.opacity(0.15) }
        if isHovered { return Surface.hover }
        return .clear
    }
}

/// 工具栏普通 icon 按钮（带 hover 反馈）
private struct ToolbarIconButton: View {
    let systemImage: String
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 22)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(isHovered && isEnabled ? Surface.hover : .clear)
                .padding(2)
        )
        .onHover { hovering in isHovered = hovering }
        .animation(Animations.quick, value: isHovered)
        .disabled(!isEnabled)
        .help(help)
    }
}

/// 工具栏排序 menu 按钮（带 hover 反馈 + segmented 容器视觉）
private struct ToolbarSortMenu<MenuContent: View>: View {
    let currentLabel: String
    let directionIcon: String
    let fullHelp: String
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var isHovered = false

    var body: some View {
        Menu(content: menuContent) {
            HStack(spacing: 4) {
                Image(systemName: directionIcon)
                    .font(.system(size: 14, weight: .medium))
                Text(currentLabel)
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .menuStyle(.automatic)
        .menuIndicator(.hidden)
        .background(
            Capsule()
                .fill(isHovered ? Surface.hover : .clear)
                .padding(2)
        )
        .onHover { hovering in isHovered = hovering }
        .animation(Animations.quick, value: isHovered)
        .help(fullHelp)
    }
}
