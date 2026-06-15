//
//  KeyboardShortcutsSheet.swift
//  ImageGallery
//
//  V5.60-7: ⌘? cheat sheet——列出 23 个快捷键分 6 类
//    file / edit / view / sidebar / sort / navigation
//  macOS System Settings 风格——HStack[描述 + .frame(maxWidth:.infinity, alignment:.trailing) + kbd style 快捷键]
//
//  触发: ImageGalleryApp CommandGroup(replacing: .help) Button → showShortcutsSheet = true
//

import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // V5.60-7: sheet 顶部——标题 + 关闭按钮
            HStack {
                Text("Keyboard Shortcuts")
                    .font(Typography.title2)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.lg)
            .background(Surface.panel)

            Divider()

            // V5.60-7: 6 类快捷键 HStack 列表
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    shortcutsSection(
                        title: "文件",
                        items: [
                            .init(icon: "square.and.arrow.down", label: "导入图片", keys: "⌘O"),
                            .init(icon: "folder.badge.plus", label: "新建文件夹", keys: "⌘N"),
                            .init(icon: "square.and.arrow.up", label: "导出选中", keys: "⌘E")
                        ]
                    )
                    shortcutsSection(
                        title: "编辑",
                        items: [
                            .init(icon: "doc.on.doc", label: "复制到剪贴板", keys: "⌘C"),
                            .init(icon: "arrow.uturn.backward", label: "撤销", keys: "⌘Z"),
                            .init(icon: "arrow.uturn.forward", label: "重做", keys: "⌘⇧Z")
                        ]
                    )
                    shortcutsSection(
                        title: "视图",
                        items: [
                            .init(icon: "square.grid.2x2", label: "网格视图", keys: "⌥1"),
                            .init(icon: "list.bullet", label: "列表视图", keys: "⌥2"),
                            .init(icon: "calendar", label: "时间线视图", keys: "⌥3"),
                            .init(icon: "eye", label: "快速查看", keys: "⌘Y"),
                            .init(icon: "arrow.up.left.and.arrow.down.right", label: "进入沉浸式", keys: "⌘↩")
                        ]
                    )
                    shortcutsSection(
                        title: "侧栏 / 详情",
                        items: [
                            .init(icon: "sidebar.leading", label: "切换侧栏", keys: "⌃⌘S"),
                            .init(icon: "sidebar.right", label: "切换详情面板", keys: "⌃⌘D"),
                            .init(icon: "info.circle", label: "切换信息面板", keys: "⌘I")
                        ]
                    )
                    shortcutsSection(
                        title: "排序 / 筛选",
                        items: [
                            .init(icon: "arrow.up.arrow.down", label: "切换排序方向", keys: "⌘⇧S"),
                            .init(icon: "line.3.horizontal.decrease", label: "重置筛选", keys: "⌘R"),
                            .init(icon: "magnifyingglass", label: "聚焦搜索框", keys: "⌘F")
                        ]
                    )
                    shortcutsSection(
                        title: "导航 / 缩放",
                        items: [
                            .init(icon: "arrow.left", label: "上一张", keys: "⌘["),
                            .init(icon: "arrow.right", label: "下一张", keys: "⌘]"),
                            .init(icon: "plus.magnifyingglass", label: "放大缩略图", keys: "⌘+"),
                            .init(icon: "minus.magnifyingglass", label: "缩小缩略图", keys: "⌘-"),
                            .init(icon: "1.magnifyingglass", label: "重置缩略图大小", keys: "⌘0"),
                            .init(icon: "gearshape", label: "设置", keys: "⌘,")
                        ]
                    )
                }
                .padding(Spacing.xl)
            }
        }
        .frame(width: 540, height: 480)
    }

    /// V5.60-7: 单个 section——title + 列表
    @ViewBuilder
    private func shortcutsSection(title: String, items: [ShortcutItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    ShortcutRow(item: item)
                }
            }
        }
    }
}

/// V5.60-7: 单行快捷键——icon + label + keys (右侧)
private struct ShortcutItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let keys: String
}

private struct ShortcutRow: View {
    let item: ShortcutItem

    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(item.label)
                .font(Typography.body)
            Spacer()
            // V5.60-7: 快捷键显示——单格 monospace Text 模拟 kbd
            Text(item.keys)
                .font(Typography.captionMono)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary.opacity(0.5))
                )
        }
    }
}
