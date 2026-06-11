//
//  FilterStateTests.swift
//  ImageGalleryTests
//
//  V4.36.x: 4 维筛选状态单元测试
//  - isActive / activeCount 计算属性
//  - remove(.folder/tag/shape/rating) 单 chip 删除
//  - removeAll 清空
//  - Equatable + Hashable
//

import Testing
import Foundation
@testable import ImageGallery

struct FilterStateTests {

    // MARK: - empty 状态

    @Test func emptyIsNotActive() {
        #expect(FilterState.empty.isActive == false)
    }

    @Test func emptyActiveCountIsZero() {
        #expect(FilterState.empty.activeCount == 0)
    }

    // MARK: - 添加维度激活

    @Test func addingFolderActivatesAndIncrementsCount() {
        var s = FilterState.empty
        s.folders.insert(UUID())
        #expect(s.isActive)
        #expect(s.activeCount == 1)
    }

    @Test func addingMultipleFoldersAccumulates() {
        var s = FilterState.empty
        s.folders.insert(UUID())
        s.folders.insert(UUID())
        #expect(s.activeCount == 2)
    }

    @Test func minRatingActivatesAsSingleChip() {
        var s = FilterState.empty
        s.minRating = 3
        #expect(s.isActive)
        #expect(s.activeCount == 1)
    }

    @Test func minRatingZeroIsNotActive() {
        var s = FilterState.empty
        s.minRating = 0
        #expect(!s.isActive)
    }

    // MARK: - remove 维度

    @Test func removeFolderDeactivates() {
        var s = FilterState.empty
        let id = UUID()
        s.folders.insert(id)
        s.remove(.folder(id))
        #expect(!s.isActive)
        #expect(s.folders.isEmpty)
    }

    @Test func removeTag() {
        var s = FilterState.empty
        let id = UUID()
        s.tags.insert(id)
        s.remove(.tag(id))
        #expect(s.tags.isEmpty)
    }

    @Test func removeShape() {
        var s = FilterState.empty
        s.shapes.insert(.landscape)
        s.remove(.shape(.landscape))
        #expect(s.shapes.isEmpty)
    }

    @Test func removeRatingResetsToZero() {
        var s = FilterState.empty
        s.minRating = 4
        s.remove(.rating)
        #expect(s.minRating == 0)
    }

    // MARK: - removeAll

    @Test func removeAllClearsEverything() {
        var s = FilterState(
            folders: [UUID(), UUID()],
            tags: [UUID()],
            shapes: [.landscape, .square],
            minRating: 3
        )
        s.removeAll()
        #expect(s == .empty)
    }

    // MARK: - 混合计数

    @Test func mixedDimensionsCountCorrectly() {
        // 2 folders + 3 tags + 1 shape + rating=5 → 7
        let s = FilterState(
            folders: [UUID(), UUID()],
            tags: [UUID(), UUID(), UUID()],
            shapes: [.portrait],
            minRating: 5
        )
        #expect(s.activeCount == 7)
    }

    // MARK: - Equatable + Hashable

    @Test func equalityHolds() {
        let a = FilterState(folders: [UUID()], minRating: 3)
        let b = FilterState(folders: a.folders, minRating: 3)
        #expect(a == b)
    }

    @Test func inequalityOnDifferentRating() {
        let a = FilterState(minRating: 3)
        let b = FilterState(minRating: 4)
        #expect(a != b)
    }

    @Test func hashableIntoSet() {
        let s1 = FilterState(minRating: 3)
        let s2 = FilterState(minRating: 3)
        let set: Set<FilterState> = [s1, s2]
        #expect(set.count == 1)  // hash collision: 相等
    }
}
