//
//  BoxSelectionGesture.swift
//  ImageGallery
//
//  V6.17.0: 矩形圈选手势 (真 marquee, 跟 Finder / Photos 一致)
//    之前 V3.5.17 → V3.6.32 5 版迭代都是 "⌥+drag = 全选当前可见" V1 简化版
//    当时 V2 矩形 hit test 跟 cell 的 .draggable (P3.1.2 multi-drag) 抢手势 → 退回 V1
//    现在 cell 布局稳定 + 测试基建齐, 重新接 V2
//
//  仍用 ⌥+drag (跟 V1 兼容, V2 plain drag 见后续)
//
//  跟 cell .draggable 共存策略:
//    - 距离阈值 4pt, 比 .draggable (~10pt) 小, 优先于 item drag 触发
//    - ⌥ 修饰键 = 用户明确意图, 不会跟 plain item drag 冲突
//
//  Hit test: 用 cell 位置 (pre-computed by caller) + rect 包含中心点判断
//    跟 Photos / Finder 一致: rect 包含 cell 中心点 = 选中
//

import SwiftUI
import AppKit

/// V6.17.0: 单 cell 的位置 (grid 局部坐标)
///   caller 用 GridLayout + 实际 cellSize 算出来后传入
struct CellFrame: Equatable {
    let id: UUID
    let frame: CGRect  // in grid local coordinate space
}

extension View {
    /// V6.17.0: ⌥+拖动 矩形圈选 (真 marquee)
    /// - Parameters:
    ///   - isMarqueeActive: 圈选进行中状态（用于 UI 锁定滚动等）
    ///   - marqueeRect: 圈选进行中的 rect (start + current 归一化) — caller 在 overlay 显示
    ///   - selection: 选中状态 binding（手势结束时全量替换为 rect 内的 cell）
    ///   - cellFrames: 预计算的 cell 位置 (grid 局部坐标), 由 caller 算
    ///     e.g. PhotoGridView 的 GridLayout 输出 + cellSize/cellSpacing 算
    func marqueeSelectionGesture(
        isMarqueeActive: Binding<Bool>,
        marqueeRect: Binding<CGRect?>,
        selection: Binding<SelectionState>,
        cellFrames: [CellFrame]
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in
                    // 必须按住 ⌥ 键 (V1: 跟旧版一致; V2 可改 plain drag)
                    guard NSEvent.modifierFlags.contains(.option) else { return }
                    isMarqueeActive.wrappedValue = true
                    // V6.17.0: 写 rect 给 caller 显示 (从 start 到 current 归一化 rect)
                    let start = value.startLocation
                    let current = value.location
                    marqueeRect.wrappedValue = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                }
                .onEnded { _ in
                    guard isMarqueeActive.wrappedValue else {
                        isMarqueeActive.wrappedValue = false
                        marqueeRect.wrappedValue = nil
                        return
                    }
                    // V6.17.0: 真 marquee — rect 包含 cell 中心点 → 选中
                    //   跟 Finder / Photos 一致: 拖框跟 cell 中心相交即选中
                    if let rect = marqueeRect.wrappedValue {
                        let selectedIDs: Set<UUID> = Set(
                            cellFrames
                                .filter { cell in
                                    let centerX = cell.frame.midX
                                    let centerY = cell.frame.midY
                                    return rect.contains(CGPoint(x: centerX, y: centerY))
                                }
                                .map { $0.id }
                        )
                        // 替换 selection (V1 简化, 跟 Photos 一致: marquee 替换, 不 toggle)
                        var newState = SelectionState()
                        newState.selectedIDs = selectedIDs
                        if selectedIDs.count == 1 {
                            newState.selectedPhotoID = selectedIDs.first
                            newState.lastSelectedID = selectedIDs.first
                        } else if let last = cellFrames.last(where: { selectedIDs.contains($0.id) })?.id {
                            newState.lastSelectedID = last
                        }
                        selection.wrappedValue = newState
                    }
                    isMarqueeActive.wrappedValue = false
                    marqueeRect.wrappedValue = nil
                }
        )
    }

    /// V6.17.0: 旧版 boxSelectionGesture — 保留向后兼容 (V1 简化: 全选可见)
    ///   实际不用, 但不让旧 import 报错
    @available(*, deprecated, message: "V6.17.0: 改用 marqueeSelectionGesture + cellFrames 做真矩形")
    func boxSelectionGesture(
        isBoxSelecting: Binding<Bool>,
        boxSelectionRect: Binding<CGRect?>,
        selection: Binding<SelectionState>,
        visiblePhotos: [Photo]
    ) -> some View {
        // 行为跟旧 V1 一致: ⌥+drag = 全选可见
        simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { value in
                    guard NSEvent.modifierFlags.contains(.option) else { return }
                    isBoxSelecting.wrappedValue = true
                    let start = value.startLocation
                    let current = value.location
                    boxSelectionRect.wrappedValue = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                }
                .onEnded { _ in
                    guard isBoxSelecting.wrappedValue else {
                        isBoxSelecting.wrappedValue = false
                        boxSelectionRect.wrappedValue = nil
                        return
                    }
                    selection.wrappedValue = selection.wrappedValue.settingAll(in: visiblePhotos)
                    isBoxSelecting.wrappedValue = false
                    boxSelectionRect.wrappedValue = nil
                }
        )
    }
}
