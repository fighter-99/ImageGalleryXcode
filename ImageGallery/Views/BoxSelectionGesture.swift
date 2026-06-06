//
//  BoxSelectionGesture.swift
//  ImageGallery
//
//  ⌥+拖动 框选手势。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  ⚠️ V1 简化实现：框选 = 全选当前可见图。
//  真实实现需要 GeometryReader 测量每个 cell 的 frame 然后判断与 rect 是否相交。
//  那是另一个 feature，本重构不实现。
//

import SwiftUI
import AppKit

extension View {
    /// ⌥+拖动 框选手势（V1 简化：全选当前可见图）
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
                    // 真实实现：根据 rect 与每个 cell frame 的相交判断
                    selectedIDs.wrappedValue = Set(visiblePhotos.map { $0.id })
                    lastSelectedID.wrappedValue = nil
                    isBoxSelecting.wrappedValue = false
                }
        )
    }
}
