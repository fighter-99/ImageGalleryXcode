//
//  BoxSelectionGesture.swift
//  ImageGallery
//
//  ⌥+拖动 框选手势。
//  V3.5.17：从 ContentView.swift 拆出（V1 简化：框选 = 全选当前可见）。
//  V3.6.28 撤回：V2 改写破坏 drag 系统，本文件回到 V1 简化版本。
//  V3.6.28 R2: 重新接入 V2（grid 局部 + .local 坐标系 + onGeometryChange）→ 仍破坏 drag
//  V3.6.32 撤销 R2：完全回到 V1 简化
//  未来想重新接 V2，需要换实现思路（避免跟 cell .onDrag 抢）
//

import SwiftUI
import AppKit

extension View {
    /// ⌥+拖动 框选手势（V1 简化：框选 = 全选当前可见图）
    /// - Parameters:
    ///   - isBoxSelecting: 框选进行中状态（用于 UI 锁定滚动等）
    ///   - selectedIDs: 选中项 ID 集合（手势结束时全量替换）
    ///   - lastSelectedID: 上次选中 ID（重置为 nil）
    ///   - visiblePhotos: 当前可见图片（用于全量选中）
    func boxSelectionGesture(
        isBoxSelecting: Binding<Bool>,
        selectedIDs: Binding<Set<UUID>>,
        lastSelectedID: Binding<UUID?>,
        visiblePhotos: [Photo]
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .onChanged { value in
                    // 必须按住 ⌥ 键
                    guard NSEvent.modifierFlags.contains(.option) else { return }
                    isBoxSelecting.wrappedValue = true
                }
                .onEnded { _ in
                    guard isBoxSelecting.wrappedValue else {
                        isBoxSelecting.wrappedValue = false
                        return
                    }
                    // V1 简化：框选 = 全选当前可见
                    selectedIDs.wrappedValue = Set(visiblePhotos.map { $0.id })
                    lastSelectedID.wrappedValue = nil
                    isBoxSelecting.wrappedValue = false
                }
        )
    }
}
