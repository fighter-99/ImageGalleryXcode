//
//  MultiSelectDetailView.swift
//  ImageGallery
//
//  多选时的详情面板。
//  V3.5.19 改造：从"提示信息"变成"完整操作中心"——
//  替代原 PhotoGridView 的 multiSelectTopBar（已被移除）。
//
//  功能：
//  - 状态信息（已选 N 张 + 总大小）
//  - 5 个批量动作（移动到 / 加标签 / 收藏切换 / 导出 / 删除）
//  - 取消多选按钮
//

import SwiftUI
import AppKit

struct MultiSelectDetailView: View {
    let count: Int
    let totalSize: Int64
    let folders: [Folder]
    let allTags: [Tag]

    // 5 个 batch 动作
    let onMove: (Folder?) -> Void
    let onAddTag: (Tag) -> Void
    let onToggleFavorite: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // ─── 状态区 ───
            VStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("已选 \(count) 张")
                    .font(Typography.title2)
                    .foregroundStyle(Surface.textPrimary)
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(Typography.caption)
                    .foregroundStyle(Surface.textSecondary)
            }
            .padding(.top, Spacing.lg)

            Divider()

            // ─── 批量操作区 ───
            VStack(spacing: Spacing.sm) {
                // 移动到文件夹
                if !folders.isEmpty {
                    Menu {
                        Button {
                            onMove(nil)
                        } label: {
                            Label("移出文件夹", systemImage: "tray")
                        }
                        Divider()
                        ForEach(folders) { folder in
                            Button {
                                onMove(folder)
                            } label: {
                                Label(folder.name, systemImage: folder.icon)
                            }
                        }
                    } label: {
                        Label("移动到", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // 加标签
                if !allTags.isEmpty {
                    Menu {
                        ForEach(allTags) { tag in
                            Button {
                                onAddTag(tag)
                            } label: {
                                Label(tag.name, systemImage: "tag.fill")
                            }
                        }
                    } label: {
                        Label("加标签", systemImage: "tag")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // 收藏切换
                Button {
                    onToggleFavorite()
                } label: {
                    Label("收藏切换", systemImage: "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // 导出
                Button {
                    onExport()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // ─── 危险 + 取消区 ───
            VStack(spacing: Spacing.sm) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Palette.destructive)

                Button {
                    onClearSelection()
                } label: {
                    Label("取消多选 (Esc)", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }
}

#Preview {
    MultiSelectDetailView(
        count: 12,
        totalSize: 12_582_912,
        folders: [Folder(name: "旅行", icon: "airplane")],
        allTags: [Tag(name: "🌅 风景", colorHex: "#FF9500")],
        onMove: { _ in },
        onAddTag: { _ in },
        onToggleFavorite: { },
        onExport: { },
        onDelete: { },
        onClearSelection: { }
    )
    .frame(width: 320, height: 600)
}
