//
//  BoxSelectionMathTests.swift
//  ImageGalleryTests
//
//  V3.6.28：框选 V2 纯函数测试。
//
//  验证 BoxSelectionMath.computeHits 的边界：
//  - 完全在内 / 完全在外 / 部分相交（擦角）
//  - 空 rect / 空 frames 防御
//  - visibleIDs 过滤（防御性：cell frame 上报后 visiblePhotos 已变）
//  - 多 cell 命中
//
//  V3.6.28 重要：computeHits 签名是 (selectionRect, cellFrames, visibleIDs: Set<UUID>)，
//  完全不依赖 Photo / SwiftData——避免 Swift Testing 并行 @MainActor 测试时
//  SwiftData in-memory 容器共享状态冲突（实测 RecycleBinServiceIntegrationTests 同症状）。
//
//  测试模式：参考 DragReorderMathTests——纯函数，零依赖。
//

import Foundation
import CoreGraphics   // V3.6.28: CGRect 定义在 CoreGraphics
import Testing
@testable import ImageGallery

/// V3.6.28：不标 @MainActor——这个 struct 完全不碰 SwiftData / mainContext。
/// 这样 Swift Testing 可以随便并行执行，零冲突。
struct BoxSelectionMathTests {

    // MARK: - 命中

    @Test func cellFullyInsideSelectionRect() {
        // selectionRect 完全包住一个 cell
        let photoID = UUID()
        let cellFrames: [UUID: CGRect] = [
            photoID: CGRect(x: 50, y: 50, width: 100, height: 100)
        ]
        let selectionRect = CGRect(x: 0, y: 0, width: 300, height: 300)

        let hits = BoxSelectionMath.computeHits(
            selectionRect: selectionRect,
            cellFrames: cellFrames,
            visibleIDs: [photoID]
        )
        #expect(hits == [photoID])
    }

    @Test func cellFullyOutsideSelectionRect() {
        let photoID = UUID()
        let cellFrames: [UUID: CGRect] = [
            photoID: CGRect(x: 500, y: 500, width: 100, height: 100)
        ]
        let selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)

        let hits = BoxSelectionMath.computeHits(
            selectionRect: selectionRect,
            cellFrames: cellFrames,
            visibleIDs: [photoID]
        )
        #expect(hits.isEmpty)
    }

    @Test func cellPartiallyIntersectsSelectionRect() {
        // cell 与 selectionRect 擦边（相交但不完全包含）—— 应当命中
        // 这是 V1 简化（全选）vs V2 真实相交的关键差异
        let photoID = UUID()
        let cellFrames: [UUID: CGRect] = [
            // cell 在右下角,左上角 10×10 进入 selectionRect
            photoID: CGRect(x: 190, y: 190, width: 100, height: 100)
        ]
        let selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)

        let hits = BoxSelectionMath.computeHits(
            selectionRect: selectionRect,
            cellFrames: cellFrames,
            visibleIDs: [photoID]
        )
        #expect(hits == [photoID], "擦角应命中——macOS Finder / Photos.app 框选惯例")
    }

    @Test func multipleCellsSomeHitSomeMiss() {
        // 5 个 cell,3 个在 selectionRect 内,2 个在外
        let p1 = UUID(), p2 = UUID(), p3 = UUID(), p4 = UUID(), p5 = UUID()
        let cellFrames: [UUID: CGRect] = [
            p1: CGRect(x: 10, y: 10, width: 50, height: 50),    // in
            p2: CGRect(x: 80, y: 10, width: 50, height: 50),    // in
            p3: CGRect(x: 10, y: 80, width: 50, height: 50),    // in
            p4: CGRect(x: 300, y: 10, width: 50, height: 50),   // out
            p5: CGRect(x: 10, y: 300, width: 50, height: 50)    // out
        ]
        let selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)

        let hits = BoxSelectionMath.computeHits(
            selectionRect: selectionRect,
            cellFrames: cellFrames,
            visibleIDs: [p1, p2, p3, p4, p5]
        )
        #expect(hits == [p1, p2, p3])
    }

    // MARK: - 防御性边界

    @Test func emptySelectionRectReturnsEmpty() {
        // 0×0 rect——用户可能点了一下就松开（minimumDistance 6 没达成）——保守空集
        let photoID = UUID()
        let cellFrames: [UUID: CGRect] = [
            photoID: CGRect(x: 0, y: 0, width: 100, height: 100)
        ]

        let hits = BoxSelectionMath.computeHits(
            selectionRect: .zero,
            cellFrames: cellFrames,
            visibleIDs: [photoID]
        )
        #expect(hits.isEmpty, "0×0 rect 不应命中任何 cell")
    }

    @Test func emptyCellFramesReturnsEmpty() {
        // 没有 cell 上报 frame——视图模式中途切换 / cell 还没 layout
        let photoID = UUID()
        let selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)

        let hits = BoxSelectionMath.computeHits(
            selectionRect: selectionRect,
            cellFrames: [:],
            visibleIDs: [photoID]
        )
        #expect(hits.isEmpty, "无 cell 帧应返回空集")
    }

    @Test func visibleIDsFiltersStaleCellFrame() {
        // 防御性：cell frame 上报了,但 visibleIDs 已经不包含这个 id
        // （比如用户搜索后 cell 还在内存里,但 visiblePhotos 已过滤掉了它）
        // 不应命中——防止"幽灵选中"
        let visiblePhoto = UUID()
        let invisiblePhoto = UUID()  // 已不在 visibleIDs 里
        let cellFrames: [UUID: CGRect] = [
            visiblePhoto: CGRect(x: 10, y: 10, width: 50, height: 50),
            invisiblePhoto: CGRect(x: 10, y: 10, width: 50, height: 50)
        ]
        let selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)

        let hits = BoxSelectionMath.computeHits(
            selectionRect: selectionRect,
            cellFrames: cellFrames,
            visibleIDs: [visiblePhoto]  // invisiblePhoto 不在
        )
        #expect(hits == [visiblePhoto], "不在 visibleIDs 里的 cell 不应被命中")
    }

    @Test func cellIdenticalToSelectionRect() {
        // 边界：cell frame 和 selectionRect 完全相同
        let photoID = UUID()
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        let cellFrames: [UUID: CGRect] = [photoID: rect]

        let hits = BoxSelectionMath.computeHits(
            selectionRect: rect,
            cellFrames: cellFrames,
            visibleIDs: [photoID]
        )
        #expect(hits == [photoID], "cell 与 selectionRect 完全重合应命中")
    }
}
