//
//  RatingStarsMathTests.swift
//  ImageGalleryTests
//
//  V5.13：RatingStarsView 抽出的纯函数 seam 测试。
//  - displayedRating: max(current, hover) — hover 预览效果
//  - nextRating: click N 颗星，已是 N 则清 0，否则设 N（V5.8 行为不变）
//

import Testing
@testable import ImageGallery

struct RatingStarsMathTests {
    // MARK: - displayedRating

    @Test func displayedRatingReturnsCurrentWhenNoHover() {
        #expect(RatingStarsMath.displayedRating(current: 3, hover: 0) == 3)
    }

    @Test func displayedRatingReturnsHoverWhenHovering() {
        // hover 5 时显示 5（即使 current 是 2）——预览效果
        #expect(RatingStarsMath.displayedRating(current: 2, hover: 5) == 5)
    }

    @Test func displayedRatingHoverCanNotLowerDisplay() {
        // hover 1 < current 3——仍显示 3（max 规则）
        #expect(RatingStarsMath.displayedRating(current: 3, hover: 1) == 3)
    }

    @Test func displayedRatingBothZero() {
        #expect(RatingStarsMath.displayedRating(current: 0, hover: 0) == 0)
    }

    // MARK: - nextRating click-toggle

    @Test func nextRatingClicksSameStarClearsToZero() {
        // 点 N 颗星，当前是 N → 清 0（V5.8 行为）
        #expect(RatingStarsMath.nextRating(after: 3, current: 3) == 0)
    }

    @Test func nextRatingClicksDifferentStarSetsNew() {
        // 点 N 颗星，当前是 M (M != N) → 设 N
        #expect(RatingStarsMath.nextRating(after: 5, current: 2) == 5)
        #expect(RatingStarsMath.nextRating(after: 1, current: 0) == 1)
    }

    @Test func nextRatingFromZeroAlwaysSets() {
        // 当前 0 → 任何点击都设为 N（无 "0 点击"——0 是清除态）
        for n in 1...5 {
            #expect(RatingStarsMath.nextRating(after: n, current: 0) == n)
        }
    }
}
