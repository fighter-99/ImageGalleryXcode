//
//  TrashDetailView.swift
//  ImageGallery
//
//  V3.6 NEW: 回收站详情面板。
//  仿 MultiSelectDetailView 模式：状态区 + 操作区 + 危险操作区。
//  3 个动作：恢复选中的 / 永久删除选中的 / 清空回收站。
//

import SwiftUI

struct TrashDetailView: View {
    let count: Int
    let totalSize: Int64
    let retentionDays: Int

    // 选中项的操作（按 selectedIDs 调）
    let onRestore: () -> Void
    let onPermanentDelete: () -> Void
    // 全回收站操作（无需选中）
    let onEmptyTrash: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // ─── 状态区 ───
            VStack(spacing: Spacing.xs) {
                Image(systemName: "trash")
                    .font(Typography.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("回收站有 \(count) 张")
                    .font(Typography.title2)
                    .foregroundStyle(Surface.textPrimary)
                Text(totalSizeText)
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
                Text("\(retentionDays) 天后自动永久清除")
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
            }
            .padding(.top, Spacing.lg)

            Divider()

            // ─── 选中项操作区 ───
            VStack(spacing: Spacing.sm) {
                Button {
                    onRestore()
                } label: {
                    Label("恢复选中", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(count == 0)

                Button(role: .destructive) {
                    onPermanentDelete()
                } label: {
                    Label("永久删除选中", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Palette.destructive)
                .disabled(count == 0)
            }

            Spacer()

            // ─── 危险操作区 ───
            VStack(spacing: Spacing.sm) {
                Button(role: .destructive) {
                    onEmptyTrash()
                } label: {
                    Label("清空回收站", systemImage: "trash.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .tint(Palette.destructive)
                .disabled(count == 0)
                // V3.6.6: 危险操作加 help tooltip 提醒
                .help("永久删除回收站里所有照片（无法恢复）")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    private var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

#Preview {
    TrashDetailView(
        count: 8,
        totalSize: 25_165_824,
        retentionDays: 30,
        onRestore: {},
        onPermanentDelete: {},
        onEmptyTrash: {}
    )
    .frame(width: 320, height: 600)
}
