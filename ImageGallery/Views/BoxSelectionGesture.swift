//
//  BoxSelectionGesture.swift
//  ImageGallery
//
//  V6.17.0: 矩形圈选手势 (真 marquee, 跟 Finder / Photos 一致)
//    V6.17.0 首发: 挂 photoGrid (GeometryReader) + .local — BUG: scroll 之后 rect 跟 cellFrames
//      空间对不上 (rect 在可见区, cellFrames 在 content)
//    V6.17.0.1 fix: 改用 NamedCoordinateSpace, 挂 ScrollView inner content (cellFrames 同空间)
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

/// V6.17.0.1: 矩形圈选用的命名 coord space
///   挂 ScrollView 的 inner content, gesture + cellFrames 都用这个 space
///   跟 V6.17.0 .local 区别: 跟 scroll content 同步, scroll 后 hit test 仍准
extension NamedCoordinateSpace {
    static let photoGrid = Self.named("com.iridescent.ImageGallery.photoGrid")
}

/// V6.17.0: 单 cell 的位置 (photoGrid coord space)
///   caller 用 GridLayout + 实际 cellSize 算出来后传入
struct CellFrame: Equatable {
    let id: UUID
    let frame: CGRect  // in photoGrid coordinate space (scroll content)
}

// MARK: - V6.17.1: Photos.app 风格圈选判别
/// V6.17.1: 圈选 vs item drag 判别 (Mac/Photos 标准行为)
/// - Photos.app 范式:
///   - plain left-drag 在 selected cell 上 = item drag (拖到 Finder)
///   - plain left-drag 在 unselected cell / 空白区 = 圈选
/// - V6.17.0.4 之前用 ⌥+drag 避开 .draggable 冲突
/// - V6.17.1 改 plain drag, 用这个判别逻辑

/// V6.17.1: 圈选激活状态 — 通过 @Environment 透传到 cell
///   cell 据此条件禁用 .draggable, 避免圈选时 cell drag preview 干扰
private struct IsMarqueeActiveKey: EnvironmentKey {
    @MainActor static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// V6.17.1: 圈选进行中 — cell 看到这个就禁掉 .draggable
    var isMarqueeActive: Bool {
        get { self[IsMarqueeActiveKey.self] }
        set { self[IsMarqueeActiveKey.self] = newValue }
    }
}

extension CellFrame {
    /// point 是否在 cell frame 内 (用 inset 缩 1pt 边, 避免边缘 cell 误判)
    func contains(_ point: CGPoint) -> Bool {
        return frame.insetBy(dx: 1, dy: 1).contains(point)
    }
}

/// V6.17.1: 纯函数 — start 位置是否在 selected cell 上
/// - 返回 true: 圈选不启动, 让 cell 的 .draggable 处理 (item drag)
/// - 返回 false: 启动圈选
/// - 时间复杂度 O(n) 但 cellFrames < 1000 时纳秒级, OK
func isStartOnSelectedCell(
    startPoint: CGPoint,
    selectedIDs: Set<UUID>,
    cellFrames: [CellFrame]
) -> Bool {
    for cell in cellFrames where cell.contains(startPoint) {
        if selectedIDs.contains(cell.id) {
            return true
        }
        // 在 unselected cell 上 — 圈选 (Photos 范式: 也把这个 cell 加进选区)
        return false
    }
    // 空白区 — 圈选
    return false
}

extension View {
    /// V6.17.1: plain left-drag 矩形圈选 (Mac/Photos 范式, 无 ⌥ 修饰符)
    /// - Parameters:
    ///   - isMarqueeActive: 圈选进行中状态 (用于 UI 锁定滚动 + cell .draggable 条件禁用)
    ///   - marqueeRect: 圈选进行中的 rect — caller 在 overlay 显示
    ///   - selection: 选中状态 binding
    ///     - V6.17.1 加: 用于判别 start 是否在 selected cell (决定 marquee vs item drag)
    ///     - 手势结束时全量替换为 rect 内的 cell
    ///   - cellFrames: 预计算的 cell 位置 (photoGrid coord space)
    func marqueeSelectionGesture(
        isMarqueeActive: Binding<Bool>,
        marqueeRect: Binding<CGRect?>,
        selection: Binding<SelectionState>,
        cellFrames: [CellFrame]
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("com.iridescent.ImageGallery.photoGrid"))
                .onChanged { value in
                    // V6.17.1: 第一次 onChanged 判别
                    //   - 已经在 marquee 中: 更新 rect
                    //   - start 在 selected cell: 不启动 marquee, 让 .draggable 处理 (item drag)
                    //   - 其他 (unselected cell / 空白区): 启动 marquee
                    let alreadyActive = isMarqueeActive.wrappedValue
                    if !alreadyActive {
                        let startOnSelected = isStartOnSelectedCell(
                            startPoint: value.startLocation,
                            selectedIDs: selection.wrappedValue.selectedIDs,
                            cellFrames: cellFrames
                        )
                        if startOnSelected {
                            return  // item drag 模式, 不启动 marquee
                        }
                        isMarqueeActive.wrappedValue = true
                    }
                    // 写 rect 给 caller 显示 (start + current 归一化)
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
