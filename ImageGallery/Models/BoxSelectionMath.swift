//
//  BoxSelectionMath.swift
//  ImageGallery
//
//  V3.6.28：框选 V2 的纯函数 seam。
//
//  V1 简化（V3.5.17 拆出时）：框选 = 全选当前 visiblePhotos。体感是"框选无差别命中"，
//  实际是把 selectionRect 完全无视。
//
//  V2 真实实现：cell 用 PreferenceKey 上报自己的 frame 到 [UUID: CGRect]，
//  拖动结束时用 `selectionRect.intersects(cellFrame)` 判定命中。
//  本文件就是这个判定函数——纯函数，零依赖，可单测。
//
//  设计约束：
//  - 坐标系：selectionRect 和 cellFrames 必须在同一坐标系（MainSplitView 的 .named("boxSelectSpace")）
//  - visiblePhotos 过滤：防御性。只框选当前 sidebar/搜索条件下能看到的 cell，
//    防止 cell frame 上报后 visiblePhotos 已变（比如搜索改了）导致的"幽灵命中"
//

import CoreGraphics
import Foundation

/// V3.6.28：框选 V2 命中计算。
///
/// 零依赖、纯函数。可直接被单元测试，不需要 SwiftData / SwiftUI。
enum BoxSelectionMath {

    /// 计算框选命中的 photo ID 集合。
    ///
    /// - Parameters:
    ///   - selectionRect: 拖动产生的框选矩形（坐标系：调用方所在的命名坐标系）
    ///   - cellFrames: 当前可见 cell 的 `[photoID: frame]`，坐标系与 `selectionRect` 相同
    ///   - visibleIDs: 防御性过滤——只框选在当前可见集合里的 cell。
    ///                 这是防止"幽灵命中"的最后一道防线（搜索/筛选切换后 cell frame 可能仍上报）
    /// - Returns: 命中的 photo ID 集合
    ///
    /// V3.6.28: 接受 `Set<UUID>` 而非 `[Photo]`，零 SwiftData 依赖——便于单测，
    /// 也避免 Swift Testing 并行执行 @MainActor 测试时 SwiftData in-memory 容器冲突。
    static func computeHits(
        selectionRect: CGRect,
        cellFrames: [UUID: CGRect],
        visibleIDs: Set<UUID>
    ) -> Set<UUID> {
        // 空 rect：用户可能点了一下就松开（minimumDistance 6 没达成）——保守返回空集
        guard !selectionRect.isEmpty else { return [] }
        // 没有 cell 帧数据：手势中途切换了视图模式或 cell 还没上报——保守返回空集
        guard !cellFrames.isEmpty else { return [] }

        return Set(
            cellFrames
                .filter { visibleIDs.contains($0.key) && selectionRect.intersects($0.value) }
                .keys
        )
    }
}
