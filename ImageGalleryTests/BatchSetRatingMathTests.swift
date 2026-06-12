//
//  BatchSetRatingMathTests.swift
//  ImageGalleryTests
//
//  V5.13：BatchSetRatingMath.applyRating 闭包循环测试。
//  抽 closure-based seam 是为测试不需 SwiftData in-memory + Photo 实例。
//

import Testing
@testable import ImageGallery

struct BatchSetRatingMathTests {
    @Test func applyRatingCallsClosureForEachIndex() {
        var calls: [(Int, Int)] = []
        BatchSetRatingMath.applyRating(3, count: 5) { index, rating in
            calls.append((index, rating))
        }
        #expect(calls.count == 5)
        #expect(calls.map(\.0) == [0, 1, 2, 3, 4])  // 索引按 loop 顺序
        #expect(calls.map(\.1) == [3, 3, 3, 3, 3])  // rating 全部传入
    }

    @Test func applyRatingToEmptyListDoesNothing() {
        var calls = 0
        BatchSetRatingMath.applyRating(5, count: 0) { _, _ in calls += 1 }
        #expect(calls == 0)
    }

    @Test func applyRatingZeroClearsRating() {
        var ratings: [Int] = []
        BatchSetRatingMath.applyRating(0, count: 3) { _, r in ratings.append(r) }
        #expect(ratings == [0, 0, 0])
    }

    @Test func applyRatingFiveIsMax() {
        var ratings: [Int] = []
        BatchSetRatingMath.applyRating(5, count: 2) { _, r in ratings.append(r) }
        #expect(ratings == [5, 5])
    }

    @Test func applyRatingIndexMatchesLoopOrder() {
        var indices: [Int] = []
        BatchSetRatingMath.applyRating(1, count: 4) { index, _ in indices.append(index) }
        #expect(indices == [0, 1, 2, 3])
    }

    @Test func applyRatingPassesRatingToEachCall() {
        // 同一 rating 多次传入——closure 必须收到 N 次相同 rating
        var receivedRatings: [Int] = []
        BatchSetRatingMath.applyRating(4, count: 7) { _, r in receivedRatings.append(r) }
        #expect(receivedRatings == [4, 4, 4, 4, 4, 4, 4])
        #expect(receivedRatings.count == 7)
    }

    @Test func applyRatingSinglePhoto() {
        var calls: [(Int, Int)] = []
        BatchSetRatingMath.applyRating(3, count: 1) { i, r in calls.append((i, r)) }
        #expect(calls.count == 1)
        #expect(calls[0] == (0, 3))  // 单个 tuple == 自动合成
    }
}
