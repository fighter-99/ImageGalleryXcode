//
//  SelectionMiniToolbar.swift
//  ImageGallery
//
//  P3.1.3: 选完 mini toolbar
//  - macOS Photos / Finder 范式: 选非空时浮在 content 顶部
//  - 4 action: Tag (popover picker) / Move (menu) / Export (直接) / Delete (确认弹窗)
//  - regular material + accent color, 跟系统级 toolbar 视觉一致
//  - 跟 P3.1.1 (框选) + P3.1.2 (multi-drag) 配套, P3.1 选区体验收官
//

import SwiftUI
import SwiftData

/// P3.1.3: 选完动作条 — 选 N 张图时浮出, 5 个 batch action
///   - Tag: 弹 tag picker popover (用 model.allTags)
///   - Move: 弹 folder picker menu (用 model.folders)
///   - Rename (P4.2): 弹 batch rename sheet
///   - Export: 直接调 batchExport() (已有 file panel)
///   - Delete: 弹确认 dialog (showingBatchDeleteConfirm)
struct SelectionMiniToolbar: View {
    @Bindable var model: ContentViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTagPicker = false
    @State private var showMovePicker = false

    var body: some View {
        HStack(spacing: 4) {
            // 选中 N 张提示 — V6.28: selection 在 model.grid
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("\(model.grid.selection.selectedIDs.count) 张已选")
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().frame(height: 18)

            // Tag — popover picker
            Button {
                showTagPicker.toggle()
            } label: {
                Label("标签", systemImage: "tag")
            }
            .help("给选中照片加标签")
            .popover(isPresented: $showTagPicker, arrowEdge: .bottom) {
                TagPickerPopover(model: model)
            }

            // Move — menu picker (V6.28: folders + batchMove 在 model.grid)
            Menu {
                Button("未整理") {
                    model.grid.batchMove(to: nil)
                }
                Divider()
                ForEach(model.grid.folders) { folder in
                    Button(folder.name) {
                        model.grid.batchMove(to: folder)
                    }
                }
            } label: {
                Label("移动", systemImage: "folder")
            }
            .help("移动到文件夹")

            // P4.2: Rename — sheet (模板批量重命名, V6.28: grid 业务)
            Button {
                model.grid.showingBatchRenameSheet = true
            } label: {
                Label(Copy.batchRenameTitle, systemImage: "pencil.and.list.clipboard")
            }
            .help("按模板批量重命名 (⌘⇧R)")

            // Export — 直接调 (内部 file panel, V6.28: grid)
            Button {
                model.grid.batchExport()
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("导出选中照片")

            // Delete — 弹确认 dialog (V6.28: grid)
            Button(role: .destructive) {
                model.grid.showingBatchDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .help("移到回收站")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                // V6.16.1: 暗色模式阴影加强 — 0.1 黑阴影在深灰底上几乎不可见
                //   浅色: 0.15 黑 (柔和, 提一下就好)
                //   暗色: 0.5 黑 (明显抬起, 否则浮层感丢失)
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15),
                    radius: colorScheme == .dark ? 8 : 4,
                    x: 0,
                    y: colorScheme == .dark ? 3 : 2
                )
        )
    }
}

/// P3.1.3: Tag picker popover — 列出 model.allTags, 选一个就 batchAddTag
private struct TagPickerPopover: View {
    @Bindable var model: ContentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newTagName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("加标签")
                .font(.headline)
                .padding(.bottom, 4)

            // V6.28: allTags + batchAddTag 在 model.grid
            if model.grid.allTags.isEmpty {
                Text("还没有标签")
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
                TextField("新标签", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createAndAdd() }
                Button("创建") {
                    createAndAdd()
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(minWidth: 200)
    }

    private func createAndAdd() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let modelContext = model.modelContext else { return }
        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        try? modelContext.save()
        model.grid.batchAddTag(tag)
        dismiss()
    }
}
