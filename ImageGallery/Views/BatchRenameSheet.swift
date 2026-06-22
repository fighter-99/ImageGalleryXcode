//
//  BatchRenameSheet.swift
//  ImageGallery
//
//  P4.2 批量重命名 sheet — Photos.app 范式
//
//  UX:
//  - Title: "重命名 N 张照片"
//  - 模板输入: TextField + 提示可用占位符
//  - 实时 preview: 前 3 张 + "等 N 个"
//  - Within-batch conflict 警告 (auto-suffix 时不警告, V1 简化)
//  - Apply / Cancel 按钮
//
//  Live preview: 每次 keystroke 同步 re-render 前 3 张 (template 短, < 1ms)
//  V1 不做 on-disk 探查 (IO), 真正冲突 apply 时由 ContentViewModel.batchRename 处理
//
//

import SwiftUI
import SwiftData

struct BatchRenameSheet: View {
    let photos: [Photo]
    /// 闭包: caller 负责实际执行 batchRename + 关闭 sheet
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var template: String = ""

    // MARK: - 派生

    private var trimmed: String {
        template.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !trimmed.isEmpty
    }

    /// Live preview: 前 3 张渲染结果 (basename.ext 形式)
    private var previews: [(index: Int, name: String)] {
        guard isValid, !photos.isEmpty else { return [] }
        return photos.prefix(3).enumerated().compactMap { (i, photo) -> (Int, String)? in
            let originalBase = photo.fileURL.deletingPathExtension().lastPathComponent
            let ext = photo.fileURL.pathExtension
            guard let rendered = try? BatchRenameTemplate.render(
                template: trimmed, index: i + 1, totalCount: photos.count,
                originalFilename: originalBase
            ) else { return nil }
            let fullName = ext.isEmpty ? rendered : "\(rendered).\(ext)"
            return (i + 1, fullName)
        }
    }

    /// Within-batch collision 检测 (渲染后 dedup)
    private var withinBatchCollisionCount: Int {
        let rendered = previews.map(\.name)
        return rendered.count - Set(rendered).count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            Text(Copy.batchRenameSheetTitle(photos.count))
                .font(.headline)

            // 模板输入
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.batchRenameTemplateTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(Copy.batchRenameTemplatePlaceholder, text: $template)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyIfValid()
                    }
                Text(Copy.batchRenameTokenHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Preview 区
            if !previews.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(Copy.batchRenamePreviewTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if photos.count > 3 {
                            Text(Copy.batchRenamePreviewSuffix(photos.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(previews, id: \.index) { item in
                        HStack(spacing: 6) {
                            Text("\(item.index).")
                                .font(Typography.bodyMono)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(item.name)
                                .font(Typography.bodyMono)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            // Within-batch collision 警告
            if withinBatchCollisionCount > 0 {
                Label(
                    Copy.batchRenameCollisionWarning(withinBatchCollisionCount),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Spacer()

            // 操作栏
            HStack {
                Button(Copy.cancel, role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(Copy.apply) {
                    applyIfValid()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 440, height: 360)
    }

    private func applyIfValid() {
        guard isValid else { return }
        let t = trimmed
        // 关闭 sheet 前 caller 先执行 (caller 负责 dismiss, 避免双重关闭)
        onApply(t)
        dismiss()
    }
}

// MARK: - Preview (canvas only)

#Preview {
    // Preview 需要 in-memory ModelContainer
    // V6.67 (Q1 force unwrap cleanup): try! 在 Preview 宏里是 idiomatic Swift 范式
    //   - 失败时 Preview 不渲染 (vs app 崩), dev-only 副作用
    //   - 真 production init 路径走 ImageGalleryApp.modelContainer (do/catch + 自动重置)
    let container = try! ModelContainer(
        for: Photo.self, Folder.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let p1 = Photo(filename: "IMG_001.jpg", fileURL: URL(fileURLWithPath: "/tmp/preview1.jpg"),
                   fileSize: 100, width: 10, height: 10)
    let p2 = Photo(filename: "IMG_002.jpg", fileURL: URL(fileURLWithPath: "/tmp/preview2.jpg"),
                   fileSize: 100, width: 10, height: 10)
    let p3 = Photo(filename: "IMG_003.jpg", fileURL: URL(fileURLWithPath: "/tmp/preview3.jpg"),
                   fileSize: 100, width: 10, height: 10)
    let _ = container.mainContext.insert(p1)
    let _ = container.mainContext.insert(p2)
    let _ = container.mainContext.insert(p3)

    BatchRenameSheet(photos: [p1, p2, p3]) { _ in }
}
