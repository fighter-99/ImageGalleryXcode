//
//  KeyboardShortcutRoutingTests.swift
//  ImageGalleryTests
//
//  V5.13：RatingShortcuts.routes 路由表测试（V5.12 抽）。
//  验 ⌘0-⌘5 6 行 key/modifier/rating 三元组。
//
//  // TODO V5.14：⌘1/3/4/5 与 sidebar 快捷键潜在冲突已知不修
//

import Testing
import SwiftUI
@testable import ImageGallery

struct KeyboardShortcutRoutingTests {
    @Test func routesHasSixEntries() {
        #expect(RatingShortcuts.routes.count == 6)
    }

    @Test func routesCoverZeroThroughFive() {
        // ratings 必须是 0, 1, 2, 3, 4, 5
        let ratings = RatingShortcuts.routes.map(\.rating).sorted()
        #expect(ratings == [0, 1, 2, 3, 4, 5])
    }

    @Test func allRoutesUseCommandModifier() {
        // macOS Photos 标准：⌘ + 0-5
        for route in RatingShortcuts.routes {
            #expect(route.modifiers == .command)
        }
    }

    @Test func allKeysAreUnique() {
        // 0-5 数字键互不重复
        let keys = RatingShortcuts.routes.map { String(routeKey: $0.key) }
        let uniqueKeys = Set(keys)
        #expect(uniqueKeys.count == 6)
        #expect(keys.sorted() == ["0", "1", "2", "3", "4", "5"])
    }

    @Test func routesAreOrderedByRating() {
        // 按 rating 升序排列——ContentKeyboardShortcuts 渲染顺序确定
        let ratings = RatingShortcuts.routes.map(\.rating)
        #expect(ratings == [0, 1, 2, 3, 4, 5])
    }
}

// 辅助：KeyEquivalent → String（用于测试 key 唯一性）
private extension String {
    init(routeKey: KeyEquivalent) {
        self = "\(routeKey.character)"
    }
}
