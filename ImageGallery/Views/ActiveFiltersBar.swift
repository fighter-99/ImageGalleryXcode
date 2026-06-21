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
//  V5.61-2: 同类合并——5 folder → 1 个 "folder · 5" chip + Menu 展开 5 个 × 按钮
//    Photos 风格紧凑化——节省横向 ~200pt
//    4 维处理:
//      - folder 5+: Menu 合并 (数量易爆, 合并收益大)
//      - tag 4+:   Menu 合并
//      - shape 1-3: 保留独立 chip (数量稳定, 合并无收益)
//      - rating 1:  保留独立 chip (单值)
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
                    // V5.61-2: folder 同类合并——5 个 → 1 个 "folder · 5" chip + Menu 展开
                    if !filterState.folders.isEmpty {
                        groupedFilterMenu(
                            icon: "folder",
                            count: filterState.folders.count,
                            label: "folder"
                        ) {
                            ForEach(Array(filterState.folders), id: \.self) { id in
                                Button {
                                    filterState.remove(.folder(id))
                                } label: {
                                    Label(
                                        folderName(for: id) ?? Copy.unknownFolder,
                                        systemImage: IconNames.folder
                                    )
                                }
                            }
                        }
                    }
                    // V5.61-2: tag 同类合并
                    if !filterState.tags.isEmpty {
                        groupedFilterMenu(
                            icon: "tag",
                            count: filterState.tags.count,
                            label: "tag"
                        ) {
                            ForEach(Array(filterState.tags), id: \.self) { id in
                                Button {
                                    filterState.remove(.tag(id))
                                } label: {
                                    Label(
                                        "#\(tagName(for: id) ?? Copy.unknownTag)",
                                        systemImage: IconNames.tag
                                    )
                                }
                            }
                        }
                    }
                    // V5.61-2: shape 保留独立 chip——数量稳定 (1-3), 合并无收益
                    ForEach(Array(filterState.shapes), id: \.self) { s in
                        chip(
                            icon: s.icon,
                            label: s.label,
                            onRemove: { filterState.remove(.shape(s)) }
                        )
                    }
                    // rating 保留独立 chip——单值
                    if filterState.minRating > 0 {
                        chip(
                            icon: "star.fill",
                            label: Copy.minRatingStars(filterState.minRating),
                            onRemove: { filterState.remove(.rating) }
                        )
                    }
                    // Clear all
                    Button {
                        filterState = .empty
                    } label: {
                        Text(Copy.clearAllFilters)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help(Copy.activeFiltersClearAllTooltip)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)
                // V4.56.0: filterState 变化时驱动 chip × 删除动画
                //   仿 V3.6.38 多选 ✓ 圆点动画模式——.animation + .transition 配对
                //   删 chip 时渐出（scale 0.8 + opacity 0）+ springGentle
                .animation(Animations.springGentle, value: filterState)
            }
            .background(.bar)
        }
    }

    /// V5.61-2: 同类合并 chip——外部显示 "icon label · count", 点击 Menu 展开各 item
    ///   - macOS Menu 自动渲染 popup (类似 right-click menu)——比 popover 紧凑
    ///   - 内嵌 Button 列表——点击单项触发 onTap callback
    @ViewBuilder
    private func groupedFilterMenu<Content: View>(
        icon: String,
        count: Int,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(Copy.activeFilterChip(label: label, count: count))
                    .font(.caption)
                // V5.61-2: chevron 暗示"可展开"——macOS 标准 Menu 视觉
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // V6.52 (design polish): .quaternary 容器色 — 跟单 chip 的 accent 实色区分
            //   视觉: 单 chip = "已激活", grouped menu = "容器 (可展开)"
            //   Photos 真版 .quaternary 是 popover/segmented container 标准
            //   之前用 Color.accentColor.opacity(0.15) 跟单 chip 同色 — 视觉"都是已激活"失分层
            .background(.quaternary, in: Capsule())
        }
        .menuStyle(.borderlessButton)  // V5.61-2: 去掉 Menu 默认边框, 视觉与 chip 一致
        .menuIndicator(.hidden)  // V5.61-2: 隐藏默认 chevron (我们手动加了)
        // V4.56.0: 渐出过渡——filterState 变化时 chip 从 ForEach 移除触发
        .transition(.scale(scale: 0.8).combined(with: .opacity))
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
            .help(Copy.activeFiltersRemoveFilterTooltip)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // V6.52 (design polish): 单 chip 保留 accent.opacity(0.15) — "已激活" 视觉锤
        //   跟 grouped menu 的 .quaternary 容器色形成对比:
        //   - 单 chip = "已激活" (accent 实色暗示激活状态)
        //   - grouped menu = "容器 (可展开)" (.quaternary 暗示中性容器)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
        // V4.56.0: chip 渐出过渡——filterState 变化时（chip 从 ForEach 移除）触发
        //   仿 V3.6.38 多选 ✓ 圆点 .transition(.scale.combined(with: .opacity))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
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
