//
//  MainSplitView.swift
//  ImageGallery
//
//  三列布局：侧栏 / 内容 / 详情。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  V4.36.4: 撤销 V4.36.2 的 hasContent 隐藏行为——detail panel 永远显示
//    V4.36.2 加 hasContent 条件: 未选中时整体隐藏 detail panel
//    用户反馈: detail panel 进/出动画打扰浏览节奏 + 选/未选时 main grid 列数变化视觉不稳定
//    撤回方案: 恢复 showDetail 一刀切, 未选中时 DetailPane 内显示简单占位
//
//  包含：
//  - 条件显示侧栏和详情（受 showSidebar / showDetail 控制）
//  - 三列之间的可拖拽分隔条（ColumnDragHandle）
//  - 拖入文件的 drop target 和"松开导入" overlay
//  - onAppear 从 AppStorage 恢复列宽
//
//  子视图通过 @ViewBuilder 闭包传入，由 ContentView 在调用处构造。
//

import SwiftUI
import UniformTypeIdentifiers

struct MainSplitView<Sidebar: View, Center: View, Detail: View>: View {
    let layout: ColumnLayoutState

    @Binding var showSidebar: Bool
    @Binding var showDetail: Bool
    @Binding var isDropTargeted: Bool
    @Binding var isBoxSelecting: Bool

    let onDrop: ([NSItemProvider]) -> Bool

    let sidebar: Sidebar
    let center: Center
    let detail: Detail

    init(
        layout: ColumnLayoutState,
        showSidebar: Binding<Bool>,
        showDetail: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        isBoxSelecting: Binding<Bool>,
        onDrop: @escaping ([NSItemProvider]) -> Bool,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder center: () -> Center,
        @ViewBuilder detail: () -> Detail
    ) {
        self.layout = layout
        self._showSidebar = showSidebar
        self._showDetail = showDetail
        self._isDropTargeted = isDropTargeted
        self._isBoxSelecting = isBoxSelecting
        self.onDrop = onDrop
        self.sidebar = sidebar()
        self.center = center()
        self.detail = detail()
    }

    var body: some View {
        HStack(spacing: 0) {
            // 侧栏
            if showSidebar {
                // V3.5.17：侧栏和 drag handle 一起滑动进出
                Group {
                    sidebar
                        .frame(width: layout.sidebarColumnWidth.wrappedValue)

                    ColumnDragHandle(
                        dragStartWidth: layout.sidebarDragStartWidth,
                        currentWidth: layout.sidebarColumnWidth,
                        minWidth: layout.sidebarMinWidth,
                        maxWidth: layout.sidebarMaxWidth,
                        isRightEdge: true,  // 侧栏在左，拖动影响右边缘
                        onEnd: layout.onSidebarDragEnd
                    )
                }
                // V3.5.17：滑动 + 淡入淡出过渡（与 withAnimation 配合）
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // 中间内容（自动占满剩余空间）
            center
                .frame(maxWidth: .infinity)

            // 详情
            // V4.36.4: 撤销 hasContent 条件，detail panel 永远显示（用户偏好稳定布局）
            //   未选中时 DetailPane 内显示 EmptyDetailPlaceholder（无 LibraryOverview 重复内容）
            if showDetail {
                ColumnDragHandle(
                    dragStartWidth: layout.detailDragStartWidth,
                    currentWidth: layout.detailColumnWidth,
                    minWidth: layout.detailMinWidth,
                    maxWidth: layout.detailMaxWidth,
                    isRightEdge: false,  // 详情在右，拖动影响左边缘
                    onEnd: layout.onDetailDragEnd
                )

                detail
                    .frame(width: layout.detailColumnWidth.wrappedValue)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear(perform: layout.restoreFromStorage)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: onDrop)
        .overlay {
            if isDropTargeted {
                ZStack {
                    // V4.0.0: 改用 .regularMaterial 替代纯 accent 染色
                    //   让 drop overlay 自动适配暗色 + 透出后面内容（半透明）
                    Rectangle()
                        .fill(Material.dropOverlay)
                        .opacity(0.95)
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
                .transition(.opacity)
            }
        }
        .scrollDisabled(isBoxSelecting)
    }
}
