//
//  BoxSelectionGesture.swift
//  ImageGallery
//
//  ⌥+拖动 框选手势。
//  V3.5.17：从 ContentView.swift 拆出（V1 简化：框选 = 全选当前可见）。
//  V3.6.28：升级 V2——rect 真正相交（BoxSelectionMath.computeHits）。
//
//  流程：
//  1. ⌥+拖动期间：onChanged 实时更新 selectionRect（用于 overlay 绘制框）
//  2. 拖动结束：onEnded 调用 BoxSelectionMath.computeHits 算命中
//  3. ⇧+⌥+拖 = 加选到现有 selectedIDs；⌥+拖 = 替换
//

import SwiftUI
import AppKit

extension View {
    /// ⌥+拖动 框选手势（V3.6.28 V2 真实 rect 相交）
    /// - Parameters:
    ///   - isBoxSelecting: 框选进行中状态（用于 UI 锁定滚动等）
    ///   - selectionRect: 拖动产生的矩形（用于绘制框选 overlay + 传给 BoxSelectionMath）
    ///   - cellFrames: 当前可见 cell 的 [UUID: CGRect]，由父视图 onPreferenceChange 收集
    ///   - selectedIDs: 选中项 ID 集合（手势结束时替换或加选）
    ///   - lastSelectedID: 上次选中 ID（重置为 nil，让后续 ⇧+点击从这次框选末尾开始）
    ///   - visiblePhotos: 当前可见图片（防御性过滤）
    ///   - isShiftHeld: ⇧ 是否按住（⇧+⌥ = 加选；⌥ = 替换）
    func boxSelectionGesture(
        isBoxSelecting: Binding<Bool>,
        selectionRect: Binding<CGRect>,
        cellFrames: [UUID: CGRect],
        selectedIDs: Binding<Set<UUID>>,
        lastSelectedID: Binding<UUID?>,
        visiblePhotos: [Photo],
        isShiftHeld: Bool = false
    ) -> some View {
        simultaneousGesture(
            // V3.6.28: 用 .named("boxSelectSpace") 命名坐标系，
            // 确保 DragGesture 的 startLocation/endLocation 和 cell 上报的 frame 在同一空间。
            // 命名空间由 MainSplitView 的 .coordinateSpace(name: "boxSelectSpace") 设置。
            DragGesture(minimumDistance: 6, coordinateSpace: .named("boxSelectSpace"))
                .onChanged { value in
                    // 必须按住 ⌥ 键（macOS Photos.app / Finder 惯例）
                    guard NSEvent.modifierFlags.contains(.option) else { return }
                    isBoxSelecting.wrappedValue = true
                    selectionRect.wrappedValue = normalizedRect(
                        from: value.startLocation,
                        to: value.location
                    )
                }
                .onEnded { value in
                    // 没按下 ⌥：忽略（其他 modifier 触发的拖动不属于框选）
                    guard isBoxSelecting.wrappedValue else {
                        isBoxSelecting.wrappedValue = false
                        return
                    }
                    let rect = normalizedRect(from: value.startLocation, to: value.location)
                    let hits = BoxSelectionMath.computeHits(
                        selectionRect: rect,
                        cellFrames: cellFrames,
                        visibleIDs: Set(visiblePhotos.map { $0.id })
                    )
                    // ⇧+⌥ = 加选到现有 selectedIDs；⌥ = 替换
                    if isShiftHeld {
                        selectedIDs.wrappedValue.formUnion(hits)
                    } else {
                        selectedIDs.wrappedValue = hits
                    }
                    lastSelectedID.wrappedValue = nil
                    isBoxSelecting.wrappedValue = false
                    selectionRect.wrappedValue = .zero
                }
        )
    }
}

// MARK: - 私有辅助

/// V3.6.28：规范化矩形（start/end 是两个对角点，需要算出规范的 left/top/width/height）。
/// 用于 overlay 绘制和命中计算——两者都需要规范化后的 CGRect。
private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    )
}
