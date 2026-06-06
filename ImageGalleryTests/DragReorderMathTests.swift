//
//  DragReorderMathTests.swift
//  ImageGalleryTests
//
//  V3.5.D P3：拖拽重排数学测试。
//  验证 PhotoGridView.computeDragReorder 的:
//  - 单项移动(无多选)
//  - 多选展开(source.count == 1 && 在多选中 → 整组拖)
//  - destination 坐标系校正(SwiftUI 原数组 vs Array.move 修改后)
//

import Foundation
import Testing
@testable import ImageGallery

struct DragReorderMathTests {

    // MARK: - 单项移动(无多选)

    @Test func singleItemNoMultiSelectPassesThrough() {
        // 5 张图 [A,B,C,D,E],拖动 C(index 2)到 D 和 E 之间(destination=4)
        // 期望结果 [A,B,D,C,E]:C 在 modified 数组索引 3 处插入
        let result = PhotoGridView.computeDragReorder(
            photoCount: 5,
            source: IndexSet([2]),
            destination: 4,
            isPhotoSelectedAt: { _ in false }
        )
        #expect(result.allSources == IndexSet([2]))
        #expect(result.adjustedDest == 3, "destination=4 在 5 张图里是 D/E 之间,校正后是 modified 数组索引 3")
    }

    // MARK: - 单项移动,但只有那一张被选中(不算多选)

    @Test func singleItemOnlyThatOneSelectedIsNotExpanded() {
        // 5 张图 [A,B,C,D,E],拖动 D(index 3)到末尾(destination=5)
        // 期望 [A,B,C,E,D]:D 在 modified 数组末尾追加
        let result = PhotoGridView.computeDragReorder(
            photoCount: 5,
            source: IndexSet([3]),
            destination: 5,
            isPhotoSelectedAt: { i in i == 3 }
        )
        #expect(result.allSources == IndexSet([3]))
        #expect(result.adjustedDest == 4, "destination=5 是末尾,校正后是 modified 数组索引 4")
    }

    // MARK: - 多选拖拽(整组)

    @Test func draggingSelectedItemExpandsToAllSelected() {
        // 7 张图,选中 [1, 3, 5],拖动索引 3 到末尾
        // 应该展开成 {1, 3, 5} 一起拖
        let selected: Set<Int> = [1, 3, 5]
        let result = PhotoGridView.computeDragReorder(
            photoCount: 7,
            source: IndexSet([3]),
            destination: 7,
            isPhotoSelectedAt: { selected.contains($0) }
        )
        #expect(result.allSources == IndexSet([1, 3, 5]))
    }

    @Test func draggingUnselectedItemIsSingleMove() {
        // 7 张图,选中 [1, 3, 5],但拖动的是索引 6(不在选中)
        // 不展开,就是单张移动
        let selected: Set<Int> = [1, 3, 5]
        let result = PhotoGridView.computeDragReorder(
            photoCount: 7,
            source: IndexSet([6]),
            destination: 1,
            isPhotoSelectedAt: { selected.contains($0) }
        )
        #expect(result.allSources == IndexSet([6]))
        #expect(result.adjustedDest == 1)
    }

    // MARK: - destination 校正

    @Test func destinationCorrectedForMultiItemSource() {
        // 8 张图,选中 [1, 3, 5] (3 个)
        // SwiftUI 给 destination = 6(G 的位置)
        // 校正后:6 - 3(sourcesBeforeDest)= 3
        let selected: Set<Int> = [1, 3, 5]
        let result = PhotoGridView.computeDragReorder(
            photoCount: 8,
            source: IndexSet([1]),
            destination: 6,
            isPhotoSelectedAt: { selected.contains($0) }
        )
        #expect(result.allSources == IndexSet([1, 3, 5]))
        #expect(result.adjustedDest == 3, "destination 应减去 source 中 < dest 的元素数")
    }

    @Test func destinationAtEndAdjustsCorrectly() {
        // 5 张图,选中 [0, 2](2 个)
        // destination = 5(末尾)
        // sourcesBeforeDest = 2(都 < 5)
        // adjustedDest = 5 - 2 = 3
        let selected: Set<Int> = [0, 2]
        let result = PhotoGridView.computeDragReorder(
            photoCount: 5,
            source: IndexSet([0]),
            destination: 5,
            isPhotoSelectedAt: { selected.contains($0) }
        )
        #expect(result.allSources == IndexSet([0, 2]))
        #expect(result.adjustedDest == 3)
    }

    @Test func destinationBeforeAllSourcesAdjustsCorrectly() {
        // 5 张图,选中 [3, 4](都靠后)
        // destination = 1(拖到最前面)
        // sourcesBeforeDest = 0
        // adjustedDest = 1
        let selected: Set<Int> = [3, 4]
        let result = PhotoGridView.computeDragReorder(
            photoCount: 5,
            source: IndexSet([3]),
            destination: 1,
            isPhotoSelectedAt: { selected.contains($0) }
        )
        #expect(result.allSources == IndexSet([3, 4]))
        #expect(result.adjustedDest == 1)
    }

    @Test func destinationBetweenSourceItemsAdjustsCorrectly() {
        // 5 张图,选中 [1, 3]
        // destination = 2(C 的位置,在 B 和 C 之间)
        // sourcesBeforeDest = 1(只有 1 < 2)
        // adjustedDest = 2 - 1 = 1
        let selected: Set<Int> = [1, 3]
        let result = PhotoGridView.computeDragReorder(
            photoCount: 5,
            source: IndexSet([1]),
            destination: 2,
            isPhotoSelectedAt: { selected.contains($0) }
        )
        #expect(result.allSources == IndexSet([1, 3]))
        #expect(result.adjustedDest == 1)
    }

    // MARK: - 边界

    @Test func emptyPhotoCount() {
        // 没有图的情况,虽然不太会发生,但函数应该安全
        let result = PhotoGridView.computeDragReorder(
            photoCount: 0,
            source: IndexSet([]),
            destination: 0,
            isPhotoSelectedAt: { _ in false }
        )
        #expect(result.allSources.isEmpty)
        #expect(result.adjustedDest == 0)
    }

    @Test func destinationClampedToValidRange() {
        // destination 超出范围(防御性)
        let result = PhotoGridView.computeDragReorder(
            photoCount: 3,
            source: IndexSet([1]),
            destination: 100,
            isPhotoSelectedAt: { _ in false }
        )
        // adjustedDest 会被 clamp 到 [0, photoCount - source.count] = [0, 2]
        #expect(result.adjustedDest == 2)
    }
}
