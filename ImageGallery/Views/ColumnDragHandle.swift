//
//  ColumnDragHandle.swift
//  ImageGallery
//
//  三列布局（侧栏 / 内容 / 详情）之间可拖拽调整列宽的细条。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  V4.36.5: 撤销 V4.36.1 分隔线加强——恢复 0.5pt + 8% opacity
//    V4.36.1 加 1pt + 15% opacity (separatorStrong) 试图明确 3 区域边界
//    用户反馈: 1pt 实线太重, 与 Photos.app 简洁风格不符
//    撤回方案: 恢复 Surface.separator (8% opacity) + 0.5pt 宽
//  - 6pt 宽 hit area（中间 0.5pt 可见分隔线）
//  - 拖动时改变 currentWidth（限制在 min/max）
//  - drag 期间显示 resize cursor
//

import SwiftUI
import AppKit

struct ColumnDragHandle: View {
    var dragStartWidth: Binding<CGFloat>
    var currentWidth: Binding<CGFloat>
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let isRightEdge: Bool
    let onEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .overlay {
                Rectangle()
                    .fill(Surface.separator)
                    .frame(width: 0.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartWidth.wrappedValue == 0 || abs(value.translation.width) < 1 {
                            // 第一次回调：记录起始宽度
                            if abs(value.translation.width) < 1 {
                                dragStartWidth.wrappedValue = currentWidth.wrappedValue
                            }
                        }
                        let newWidth: CGFloat
                        if isRightEdge {
                            // 侧栏（左列）：向右拖 = 变宽
                            newWidth = dragStartWidth.wrappedValue + value.translation.width
                        } else {
                            // 详情（右列）：向左拖 = 变宽
                            newWidth = dragStartWidth.wrappedValue - value.translation.width
                        }
                        currentWidth.wrappedValue = min(max(newWidth, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth.wrappedValue = 0
                        NSCursor.pop()
                        onEnd()
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
