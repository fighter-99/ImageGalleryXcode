//
//  TrashDetailView.swift
//  ImageGallery
//
//  V3.6 NEW: 回收站详情面板。
//  仿 MultiSelectDetailView 模式：状态区 + 操作区 + 危险操作区。
//  3 个动作：恢复选中的 / 永久删除选中的 / 清空回收站。
//
//  V4.9.0: count == 0 时改用 EmptyStateView 统一空状态
//  - 旧：显示完整操作区，所有按钮 disabled
//  - 新：EmptyStateView（trash icon + "回收站是空的" + "查看全部" 切回主视图）
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
    // V4.9.0: 切回"全部"视图（用于空状态次 CTA——回收站空时切回去）
    let onExitTrash: () -> Void

    var body: some View {
        // V4.9.0: count == 0 走空状态分支
        if count == 0 {
            EmptyStateView(
                icon: "trash",
                title: Copy.emptyRecycleBin,
                subtitle: "\(retentionDays) 天后删除的照片会自动永久清除",
                iconColor: Surface.textTertiary,
                primaryAction: EmptyStateView.Action(
                    label: "查看全部",
                    systemImage: "photo.on.rectangle.angled",
                    onTap: onExitTrash
                )
            )
        } else {
            populatedContent
        }
    }

    /// V4.9.0: 非空状态的完整详情面板（抽到 var 避免 body 内分支嵌套）
    private var populatedContent: some View {
        VStack(spacing: Spacing.lg) {
            // ─── 状态区 ───
            VStack(spacing: Spacing.xs) {
                Image(systemName: "trash")
                    .font(Typography.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(Copy.recycleBinCount(count))
                    .font(Typography.title2)
                    .foregroundStyle(Surface.textPrimary)
                Text(totalSizeText)
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
                Text(Copy.autoDeleteAfterDays(retentionDays))
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

#Preview("回收站有照片") {
    TrashDetailView(
        count: 8,
        totalSize: 25_165_824,
        retentionDays: 30,
        onRestore: {},
        onPermanentDelete: {},
        onEmptyTrash: {},
        onExitTrash: {}
    )
    .frame(width: 320, height: 600)
}

#Preview("回收站为空") {
    TrashDetailView(
        count: 0,
        totalSize: 0,
        retentionDays: 30,
        onRestore: {},
        onPermanentDelete: {},
        onEmptyTrash: {},
        onExitTrash: {}
    )
    .frame(width: 320, height: 480)
}
