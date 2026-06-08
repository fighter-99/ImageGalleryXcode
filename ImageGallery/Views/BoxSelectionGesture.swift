//
//  BoxSelectionGesture.swift
//  ImageGallery
//
//  ⌥+拖动 框选手势。
//  V3.5.17：从 ContentView.swift 拆出（V1 简化：框选 = 全选当前可见）。
//  V3.6.28 撤回：V2 改写破坏 drag 系统，本文件回到 V1 简化版本。
//  V3.6.28+: 框选 V2 实现（BoxSelectionMath + PreferenceKey）已写好但暂不接线，
//  等待下一步排查出根因后再启用。
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
