//
//  MainSplitView.swift
//  ImageGallery
//
//  三列布局：侧栏 / 内容 / 详情。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  V6.62: NavigationSplitView 改造
//   - 用 NavigationSplitView 替代自定义 HStack + ColumnDragHandle
//   - NavigationSplitView 原生管理：
//     * 侧边栏显隐（工具栏 sidebar.leading 按钮 + ⌘⌥S）
//     * 列宽拖拽调整
//     * 侧边栏进出动画
//
//  子视图通过 @ViewBuilder 闭包传入，由 ContentView 在调用处构造。
//

import SwiftUI
import UniformTypeIdentifiers

struct MainSplitView<Sidebar: View, Center: View, Detail: View>: View {
    @Binding var showDetail: Bool
    @Binding var isDropTargeted: Bool
    @Binding var isBoxSelecting: Bool

    let onDrop: ([NSItemProvider]) -> Bool
    let sidebar: Sidebar
    let center: Center
    let detail: Detail

    init(
        showDetail: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        isBoxSelecting: Binding<Bool>,
        onDrop: @escaping ([NSItemProvider]) -> Bool,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder center: () -> Center,
        @ViewBuilder detail: () -> Detail
    ) {
        self._showDetail = showDetail
        self._isDropTargeted = isDropTargeted
        self._isBoxSelecting = isBoxSelecting
        self.onDrop = onDrop
        self.sidebar = sidebar()
        self.center = center()
        self.detail = detail()
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 320)
        } content: {
            center
        } detail: {
            if showDetail {
                detail
                    .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 500)
            }
        }
        .scrollDisabled(isBoxSelecting)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: onDrop)
        .overlay {
            if isDropTargeted {
                dropOverlay
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Material.dropOverlay)
                .opacity(0.95)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 4, dash: [8, 4])
                )
                .padding(Spacing.sm)
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(Typography.emptyStateIconLarge)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(Copy.dropReleaseToImport)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Copy.dropSupportedTypes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }
}
