//
//  MainSplitView.swift
//  ImageGallery
//
//  三列布局：侧栏 / 内容 / 详情。
//  V3.5.17：从 ContentView.swift 拆出。
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
    // V3.6.28: 框选 V2——拖动期间的 selectionRect（用于 overlay 绘制 + 命中计算）
    @Binding var selectionRect: CGRect

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
        // V3.6.28: 框选 V2 新增参数
        selectionRect: Binding<CGRect>,
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
        // V3.6.28
        self._selectionRect = selectionRect
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
                    Palette.selectionOverlayMulti
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.tint)
                        Text("松开导入")
                            .font(.title)
                            .foregroundStyle(.primary)
                        Text("支持图片文件 / 文件夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        // V3.6.28: 框选 V2——拖动期间绘制 selectionRect overlay
        // 放在 drop target overlay 之后，更高层（视觉上盖在拖入提示之上，万一同时触发）
        .overlay {
            if isBoxSelecting && !selectionRect.isEmpty {
                // 蓝色 1pt 边框 + 10% 不透明度填充，模拟 macOS Finder 框选视觉
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1)
                    .background(
                        Rectangle().fill(Color.accentColor.opacity(0.1))
                    )
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .allowsHitTesting(false)  // 不能挡住手势
            }
        }
        // V3.6.28: 命名坐标系 "boxSelectSpace"——DragGesture 和 cell frame 上报共用此空间
        // 必须设在 HStack 这一层（cells 都在 HStack 内），保证 frame 坐标一致
        .coordinateSpace(name: "boxSelectSpace")
        .scrollDisabled(isBoxSelecting)
    }
}
