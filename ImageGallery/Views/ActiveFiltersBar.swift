//
//  ActiveFiltersBar.swift
//  ImageGallery
//
//  V4.36.x: 已激活筛选的 chip 行
//  - 仅 filterState.isActive 时显示（否则返回 EmptyView）
//  - 横向滚动：folder / tag / shape / rating chip 各 1 个
//  - 每个 chip 有 × 按钮反向删除
//  - 末尾"清除全部"按钮
//
//  渲染位置：MainLayoutView pathBar slot（ContentView.pathBarPane L731-734）
//  视觉层级：NSToolbar → ActiveFiltersBar → Split → StatusBar
//

import SwiftUI

struct ActiveFiltersBar: View {
    @Binding var filterState: FilterState
    let allFolders: [Folder]
    let allTags: [Tag]

    var body: some View {
        if !filterState.isActive {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // folder chips
                    ForEach(Array(filterState.folders), id: \.self) { id in
                        chip(
                            icon: "folder",
                            label: folderName(for: id) ?? "未知文件夹",
                            onRemove: { filterState.remove(.folder(id)) }
                        )
                    }
                    // tag chips
                    ForEach(Array(filterState.tags), id: \.self) { id in
                        chip(
                            icon: "tag",
                            label: "#\(tagName(for: id) ?? "未知标签")",
                            onRemove: { filterState.remove(.tag(id)) }
                        )
                    }
                    // shape chips
                    ForEach(Array(filterState.shapes), id: \.self) { s in
                        chip(
                            icon: s.icon,
                            label: s.label,
                            onRemove: { filterState.remove(.shape(s)) }
                        )
                    }
                    // rating chip
                    if filterState.minRating > 0 {
                        chip(
                            icon: "star.fill",
                            label: "≥ \(filterState.minRating) 星",
                            onRemove: { filterState.remove(.rating) }
                        )
                    }
                    // Clear all
                    Button {
                        filterState = .empty
                    } label: {
                        Text("清除全部")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("清除所有筛选条件")
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private func chip(icon: String, label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("移除此筛选")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - 名称查找 helper

    private func folderName(for id: UUID) -> String? {
        allFolders.first(where: { $0.id == id })?.name
    }
    private func tagName(for id: UUID) -> String? {
        allTags.first(where: { $0.id == id })?.name
    }
}

#Preview {
    @Previewable @State var s = FilterState(
        folders: [UUID()],
        tags: [UUID()],
        shapes: [.landscape, .portrait],
        minRating: 4
    )
    return ActiveFiltersBar(filterState: $s, allFolders: [], allTags: [])
        .frame(width: 600, height: 40)
}
