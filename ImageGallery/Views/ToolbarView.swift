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

            // ─── B 组：搜索 + 显示控制（输入 + 视图） ───
            // 组内 8pt
            HStack(spacing: Spacing.sm) {
                searchField
                    .frame(width: 200)  // V3.5.5 C1：搜索框 240 → 200pt
                viewModeSegment
                densitySegment
                sortMenu             // V3.5 Phase 1：排序
            }

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

    /// 搜索框
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("搜索文件名、标签、备注", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
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
        .background(Surface.toolbarControl)
        .cornerRadius(Radius.sm)
    }

    /// 视图模式 3 档（V3.4 极简：完全无背景，仅图标颜色区分 active）
    private var viewModeSegment: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 14, weight: iconWeight))  // V3.5.5 C2：统一 weight
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewMode == mode ? Color.accentColor : Color.secondary)
                .help(mode.label)
            }
        }
        .frame(height: 28)
    }

    /// 缩放（缩略图大小）3 档（同 viewModeSegment 风格）
    private var densitySegment: some View {
        HStack(spacing: 0) {
            ForEach(ThumbnailDensity.allCases) { density in
                Button {
                    thumbnailSize.wrappedValue = density.size
                } label: {
                    Image(systemName: density.icon)
                        .font(.system(size: 14, weight: iconWeight))  // V3.5.5 C2
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentDensity == density ? Color.accentColor : Color.secondary)
                .help("缩略图大小：\(density.label)（\(Int(density.size))pt）")
            }
        }
        .frame(height: 28)
    }

    /// 排序菜单（V3.5 Phase 1：加回；V3.5.5 C3：去掉 chevron 与图标按钮统一）
    /// 显示当前排序方式（方向图标 + 简短文字）
    /// 点击展开 6 种排序选项
    private var sortMenu: some View {
        Menu {
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
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sortOption.directionIcon)
                    .font(.system(size: 14, weight: iconWeight))  // V3.5.5 D3：与其他图标一致
                Text(sortOption.shortLabel)
                    .font(.caption)
            }
            .padding(.horizontal, 6)              // V3.5.5 D3：紧凑 padding
            .frame(height: 22)                     // V3.5.5 D3：与图标按钮 frame 对齐
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .menuStyle(.automatic)
        .menuIndicator(.hidden)
        .help("排序方式：\(sortOption.label)（⌘⇧S 切换方向）")
    }

    /// 撤销按钮（V3.5 Phase 1 Step 4）
    /// macOS 标准位置：工具栏最左
    private var undoButton: some View {
        Button {
            onUndo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: iconWeight))  // V3.5.5 C2
                .frame(width: 26, height: 22)  // V3.5.5 D1
                .foregroundStyle(canUndo ? Color.primary : Color.secondary.opacity(0.4))  // V3.5.5 D2：统一灰显
        }
        .buttonStyle(.plain)
        .disabled(!canUndo)
        .help("撤销 (⌘Z)")
    }

    /// 重做按钮（V3.5 Phase 1 Step 4）
    private var redoButton: some View {
        Button {
            onRedo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 14, weight: iconWeight))  // V3.5.5 C2
                .frame(width: 26, height: 22)  // V3.5.5 D1
                .foregroundStyle(canRedo ? Color.primary : Color.secondary.opacity(0.4))  // V3.5.5 D2
        }
        .buttonStyle(.plain)
        .disabled(!canRedo)
        .help("重做 (⌘⇧Z)")
    }

    /// 分享按钮（V3.5 Phase 1 Step 3）
    /// Context-sensitive：未选中照片时灰显
    /// 当前实现：触发 NSWorkspace 分享面板（系统标准分享）
    private var shareButton: some View {
        Button {
            onShare()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: iconWeight))  // V3.5.5 C2
                .frame(width: 26, height: 22)  // V3.5.5 D1
                .foregroundStyle(hasSelection ? Color.primary : Color.secondary.opacity(0.4))  // V3.5.5 D2
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
        .help(hasSelection ? "分享选中的照片" : "请先选中照片")
    }

    /// 导入按钮（主操作 L1）
    /// V3.5.5 C5：图标用 accent 色 + weight 略大（L1 视觉锚点）
    private var importButton: some View {
        Button {
            onImport()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))  // L1：略重
                Text("导入")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)  // L1：accent 色
        }
        .buttonStyle(.borderless)
        .help("导入图片 (⌘O)")
    }
}
