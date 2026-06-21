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
                Text(Copy.keyboardShortcutsTitle)  // V6.12.15: 硬编码英文入库
                    .font(Typography.title2)
                Spacer()
                Button(Copy.done) { dismiss() }  // V6.12.15: 硬编码英文入库
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.lg)
            .background(Surface.panel)

            Divider()

            // V5.60-7: 6 类快捷键 HStack 列表
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    shortcutsSection(
                        title: Copy.shortcutsSectionFile,
                        items: [
                            .init(icon: "square.and.arrow.down", label: Copy.shortcutsImportImage, keys: "⌘O"),
                            .init(icon: "folder.badge.plus", label: Copy.shortcutsNewFolder, keys: "⌘N"),
                            .init(icon: "square.and.arrow.up", label: Copy.shortcutsExportSelected, keys: "⌘E")
                        ]
                    )
                    shortcutsSection(
                        title: Copy.shortcutsSectionEdit,
                        items: [
                            .init(icon: "doc.on.doc", label: Copy.shortcutsCopyToPasteboard, keys: "⌘C"),
                            .init(icon: "arrow.uturn.backward", label: Copy.shortcutsUndo, keys: "⌘Z"),
                            .init(icon: "arrow.uturn.forward", label: Copy.shortcutsRedo, keys: "⌘⇧Z")
                        ]
                    )
                    shortcutsSection(
                        title: Copy.shortcutsSectionView,
                        items: [
                            .init(icon: "square.grid.2x2", label: Copy.shortcutsViewGrid, keys: "⌥1"),
                            .init(icon: "list.bullet", label: Copy.shortcutsViewList, keys: "⌥2"),
                            .init(icon: "calendar", label: Copy.shortcutsViewTimeline, keys: "⌥3"),
                            .init(icon: "eye", label: Copy.shortcutsQuickLook, keys: "⌘Y"),
                            .init(icon: "arrow.up.left.and.arrow.down.right", label: Copy.shortcutsImmersive, keys: "⌘↩")
                        ]
                    )
                    shortcutsSection(
                        title: Copy.shortcutsSectionSidebar,
                        items: [
                            .init(icon: "sidebar.leading", label: Copy.shortcutsToggleSidebar, keys: "⌘\\"),
                            .init(icon: "sidebar.right", label: Copy.shortcutsToggleDetail, keys: "⌃⌘D"),
                            .init(icon: "info.circle", label: Copy.shortcutsToggleInfo, keys: "⌘I")
                        ]
                    )
                    shortcutsSection(
                        title: Copy.shortcutsSectionSortFilter,
                        items: [
                            .init(icon: "arrow.up.arrow.down", label: Copy.shortcutsToggleSort, keys: "⌘⇧S"),
                            .init(icon: "line.3.horizontal.decrease", label: Copy.shortcutsResetFilter, keys: "⌘R"),
                            .init(icon: "magnifyingglass", label: Copy.shortcutsFocusSearch, keys: "⌘F")
                        ]
                    )
                    shortcutsSection(
                        title: Copy.shortcutsSectionNavigation,
                        items: [
                            .init(icon: "arrow.left", label: Copy.shortcutsPrevPhoto, keys: "⌘["),
                            .init(icon: "arrow.right", label: Copy.shortcutsNextPhoto, keys: "⌘]"),
                            .init(icon: "plus.magnifyingglass", label: Copy.shortcutsZoomIn, keys: "⌘+"),
                            .init(icon: "minus.magnifyingglass", label: Copy.shortcutsZoomOut, keys: "⌘-"),
                            .init(icon: "1.magnifyingglass", label: Copy.shortcutsResetZoom, keys: "⌘0"),
                            .init(icon: "gearshape", label: Copy.shortcutsOpenSettings, keys: "⌘,")
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
