//
//  ContextualSelectionBar.swift
//  ImageGallery
//
//  V6.38.2 (Phase 2): 选中 contextual bar — 取代 floating SelectionMiniToolbar
//  - 位置: toolbar 下方一行 (跟 grid 顶贴齐), 占 layout 空间 (grid 内容自动下移)
//  - 出现/消失: 选中数 0 → 1 触发 .transition (.move + .opacity)
//  - 视觉: 44pt 标准 toolbar 高度 + bottom divider 跟 grid 分隔
//  - 范式: Photos.app 选中 contextual bar (选中时 toolbar 下方滑出)
//  - 之前: SelectionMiniToolbar .overlay 浮层 (Phase 1 之前的产物, 跟 grid 内容重叠风险)
//

import SwiftUI
import SwiftData

/// V6.38.2: 选中 contextual bar — 嵌在 gridPane 顶部 VStack
///  - 选中数 > 0: 显示 (layout shift 让 grid 内容下移)
///  - 选中数 == 0: 整行隐藏 (grid 内容上移)
///  - 5 actions: Tag / Move / Rename / Export / Delete (跟 Photos.app 一致)
///  - 高度 44pt 跟 NSToolbar 对齐, 视觉连贯
struct ContextualSelectionBar: View {
    @Bindable var model: ContentViewModel
    @State private var showTagPicker = false
    @State private var showMovePicker = false

    private static let barHeight: CGFloat = 44

    var body: some View {
        // 顶 row: 选中数 + 5 action buttons
        HStack(spacing: 8) {
            // 选中数 — "X 张已选" + checkmark icon (跟 StatusBar 风格统一)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(Copy.selectedCount(model.grid.selection.selectedIDs.count))
                    .font(.callout.weight(.medium))
            }
            .padding(.leading, 12)
            // V6.64.1 (A11y): 选中数标签让 VoiceOver 朗读完整 — "已选 X 张"
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.selectedCount(model.grid.selection.selectedIDs.count))

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 4)

            // V6.56 (design polish): 5 actions → ViewThatFits 自动窄窗口退化
            //   之前: 窗口 < 800pt 时按钮挤压文字, 标签被截断或重排
            //   现在:
            //     - Variant 1 (够宽): Tag | Move | Rename | Export | Delete (全 5)
            //     - Variant 2 (窄): Tag | Move | '⋯' menu (Rename + Export) | Delete
            //   - Delete 始终可见 (destructive 操作 Photos 真版不允许藏到 menu)
            //   - Tag/Move 是高频, 保留主 row; Rename/Export 是中频, 折叠到 menu
            //   - ViewThatFits 自动选能 fit 的 variant, 不需 GeometryReader 测量
            ViewThatFits(in: .horizontal) {
                // Variant 1: 全 5 actions (主 row)
                fullActionsRow

                // Variant 2: Tag | Move | ⋯ menu | Delete (窄窗口)
                compactActionsRow
            }

            Spacer(minLength: 0)
        }
        .frame(height: Self.barHeight)
        .padding(.trailing, 12)
        // V6.38.2: 背景跟 main toolbar 协调 — .bar material (跟 sidebar / detail panel 同强度)
        //   跟 NSToolbar 视觉一致, 不再是浮层 material
        .background(.bar)
        // V6.38.2: 底部 divider 跟 grid 分隔 — Photos.app contextual bar 风格
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.5)
        }
    }

    /// V6.56: 全 5 actions (够宽窗口: Tag / Move / Rename / Export / Delete)
    private var fullActionsRow: some View {
        HStack(spacing: 8) {
            tagButton
            moveMenu
            renameButton
            exportButton
            deleteButton
        }
    }

    /// V6.56: 紧凑 3 + '⋯' menu (窄窗口: Tag / Move / [Rename + Export] menu / Delete)
    ///   - 保留 Tag/Move 高频操作在主 row
    ///   - Rename/Export 折叠到 '⋯' menu (中频, 用户主动点 menu 找)
    ///   - Delete 始终主 row 可见 (destructive 操作 Photos 真版不允许藏)
    private var compactActionsRow: some View {
        HStack(spacing: 8) {
            tagButton
            moveMenu

            // ⋯ overflow menu — Rename + Export (中频)
            Menu {
                Button {
                    model.grid.showingBatchRenameSheet = true
                } label: {
                    Label(Copy.batchRenameTitle, systemImage: "pencil.and.list.clipboard")
                }
                Button {
                    model.grid.batchExport()
                } label: {
                    Label(Copy.miniToolbarExport, systemImage: IconNames.squareAndArrowUp)
                }
            } label: {
                Label(Copy.more, systemImage: "ellipsis.circle")
            }
            .help(Copy.miniToolbarMoreHelp)

            deleteButton
        }
    }

    // MARK: - 5 action button sub-views (V6.56: 抽 helper 供 full + compact 复用)

    /// Tag — popover picker
    private var tagButton: some View {
        Button {
            showTagPicker.toggle()
        } label: {
            Label(Copy.tagLabel, systemImage: IconNames.tag)
        }
        .help(Copy.miniToolbarTagHelp)
        // V6.64.1 (A11y): 朗读 "给选中的照片打标签, N 张"
        .accessibilityLabel(Copy.miniToolbarTagHelp)
        .accessibilityHint(model.grid.selection.selectedIDs.count > 0
            ? Copy.a11yActionOnSelectedHint(model.grid.selection.selectedIDs.count)
            : "")
        .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
            TagPickerPopover(model: model)
        }
    }

    /// Move — menu picker (V6.28: folders + batchMove 在 model.grid)
    private var moveMenu: some View {
        Menu {
            Button(Copy.sidebarUnfiled) {
                model.grid.batchMove(to: nil)
            }
            Divider()
            ForEach(model.grid.folders) { folder in
                Button(folder.name) {
                    model.grid.batchMove(to: folder)
                }
            }
        } label: {
            Label(Copy.miniToolbarMove, systemImage: IconNames.folder)
        }
        .help(Copy.miniToolbarMoveHelp)
        // V6.64.1 (A11y): 朗读 "移动选中的照片到文件夹"
        .accessibilityLabel(Copy.miniToolbarMoveHelp)
    }

    /// Rename (P4.2): sheet (模板批量重命名, V6.28: grid 业务)
    private var renameButton: some View {
        Button {
            model.grid.showingBatchRenameSheet = true
        } label: {
            Label(Copy.batchRenameTitle, systemImage: "pencil.and.list.clipboard")
        }
        .help(Copy.miniToolbarRenameHelp)
        // V6.64.1 (A11y)
        .accessibilityLabel(Copy.miniToolbarRenameHelp)
    }

    /// Export — 直接调 (内部 file panel, V6.28: grid 业务)
    private var exportButton: some View {
        Button {
            model.grid.batchExport()
        } label: {
            Label(Copy.miniToolbarExport, systemImage: IconNames.squareAndArrowUp)
        }
        .help(Copy.miniToolbarExportHelp)
        // V6.64.1 (A11y)
        .accessibilityLabel(Copy.miniToolbarExportHelp)
    }

    /// Delete — 弹确认 dialog (Photos.app 范式: 不静默删, 弹 confirm + undo)
    private var deleteButton: some View {
        Button(role: .destructive) {
            model.grid.showingBatchDeleteConfirm = true
        } label: {
            Label(Copy.delete, systemImage: IconNames.trash)
        }
        .help(Copy.miniToolbarDeleteHelp)
        // V6.64.1 (A11y): destructive 标签朗读时强调 "删除" + selected count
        .accessibilityLabel(Copy.miniToolbarDeleteHelp)
        .accessibilityHint(model.grid.selection.selectedIDs.count > 0
            ? Copy.a11yActionOnSelectedHint(model.grid.selection.selectedIDs.count)
            : "")
    }
}

// MARK: - V6.38.2: Tag picker popover (从 SelectionMiniToolbar 搬来)
//  - 列出 model.allTags, 选一个就 batchAddTag
//  - 底部加新 tag 创建 (文本框 + 创建按钮)
//  - Photos.app contextual bar tag popover 风格
struct TagPickerPopover: View {
    @Bindable var model: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newTagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.miniToolbarAddTagTitle)
                .font(.headline)
                .padding(.bottom, 4)

            if model.grid.allTags.isEmpty {
                Text(Copy.miniToolbarEmptyTags)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.grid.allTags) { tag in
                    Button {
                        model.grid.batchAddTag(tag)
                        dismiss()
                    } label: {
                        Label(tag.name, systemImage: "tag.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                TextField(Copy.miniToolbarNewTagPlaceholder, text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createAndAddTag() }
                Button(Copy.create) { createAndAddTag() }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.md)
        .frame(minWidth: 200)
    }

    private func createAndAddTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let modelContext = model.modelContext else { return }
        let tag = Tag(name: trimmed, colorHex: "#5B8FF9")
        modelContext.insert(tag)
        try? modelContext.save()
        model.grid.batchAddTag(tag)
        dismiss()
    }
}
