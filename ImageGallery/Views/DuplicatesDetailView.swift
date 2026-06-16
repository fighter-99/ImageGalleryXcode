//
//  DuplicatesDetailView.swift
//  ImageGallery
//
//  V3.6.15 NEW: 重复图详情面板（仿 TrashDetailView 的"操作中心"模式）。
//  在 sidebar 切到「重复图」时显示：
//  - 状态区：找到 N 组重复，M 张可清理
//  - 操作区："保留每组最新" 按钮
//  - 危险操作：暂留空（重复图本身不危险）
//

import SwiftUI

struct DuplicatesDetailView: View {
    let duplicateGroupCount: Int
    let purgeableCount: Int
    let purgeableSize: Int64
    // V6.09: 透传 model.settings.trashRetentionDays——之前 hardcode `TrashRetentionDays.defaultValue.rawValue`
    //   跟用户在 Settings 设的天数脱节（V6.08 #5 在 PhotoGridEmptyState 修过同类问题）
    let retentionDays: Int
    let onKeepNewestPerGroup: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // ─── 状态区 ───
            VStack(spacing: Spacing.xs) {
                Image(systemName: "doc.on.doc")
                    .font(Typography.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                Text(Copy.duplicatesFoundGroups(duplicateGroupCount))
                    .font(Typography.title2)
                    .foregroundStyle(Surface.textPrimary)
                if purgeableCount > 0 {
                    Text(Copy.duplicatesCleanable(purgeableCount, size: formattedSize))
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                } else {
                    Text(Copy.duplicatesNone)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                }
            }
            .padding(.top, Spacing.lg)

            Divider()

            // ─── 操作区 ───
            VStack(spacing: Spacing.sm) {
                Button {
                    onKeepNewestPerGroup()
                } label: {
                    Label(Copy.keepNewestPerGroup, systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonStyle(.pressable)
                .disabled(purgeableCount == 0)

                Text(Copy.duplicatesExplanation(retentionDays: retentionDays))
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: purgeableSize, countStyle: .file)
    }
}

#Preview {
    DuplicatesDetailView(
        duplicateGroupCount: 3,
        purgeableCount: 7,
        purgeableSize: 25_165_824,
        retentionDays: 30,
        onKeepNewestPerGroup: {}
    )
    .frame(width: 320, height: 600)
}
