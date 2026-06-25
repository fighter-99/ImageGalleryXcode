//
//  GridViewModelRecordRecentSearchTests.swift
//  ImageGalleryTests
//
//  V6.74.4: 验证 GridViewModel.recordRecentSearch(_:) 行为
//    - dedup (大小写不敏感)
//    - trim 非空
//    - cap 20 (保留最新 20)
//    - 插入顺序 (最新最前)
//
//  in-memory 测, 不依赖 SwiftData container (recordRecentSearch 只操作 recentSearches: [String])
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct GridViewModelRecordRecentSearchTests {

    // V6.74.4: 共享 isolatedDefaults 防 cfprefsd 拖累 (V6.12.21 pattern)
    private static let isolatedDefaults: UserDefaults = FakeUserDefaults()
    private static let userSettingsKeys: [String] = [
        "viewModeRaw", "showSidebar", "accentColorID",
        "trashRetentionDays", "appearanceMode", "thumbnailSize",
        "sidebarSelection", "sortOption", "thumbnailLayoutMode",
        "sidebarColumnWidth", "autoDeduplicate",
        "autoGenerateThumbnails", "defaultExportFormat",
        "defaultExportQuality", "scrollAnchorPhotoID", "appLanguage",
        "fontScale", "doubleClickAction", "lastSettingsCategory"
    ]

    private static func makeGrid() -> GridViewModel {
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        let settings = UserSettings(defaults: isolatedDefaults)
        let undoManager = ImageGalleryUndoManager()
        return GridViewModel(settings: settings, undoManager: undoManager)
    }

    // MARK: - V6.74.4: recordRecentSearch 基础行为

    @Test func firstSearchRecords() {
        let grid = Self.makeGrid()
        #expect(grid.recentSearches.isEmpty)
        grid.recordRecentSearch("cat")
        #expect(grid.recentSearches == ["cat"])
    }

    @Test func multipleSearchesNewestFirst() {
        let grid = Self.makeGrid()
        grid.recordRecentSearch("cat")
        grid.recordRecentSearch("dog")
        grid.recordRecentSearch("bird")
        #expect(grid.recentSearches == ["bird", "dog", "cat"])
    }

    @Test func dedupMovesToFront() {
        let grid = Self.makeGrid()
        grid.recordRecentSearch("cat")
        grid.recordRecentSearch("dog")
        grid.recordRecentSearch("cat")  // 重复 cat
        // dedup: ["dog", "cat"] — cat 移到最前 (Photos / Finder 范式)
        #expect(grid.recentSearches == ["cat", "dog"])
    }

    @Test func caseInsensitiveDedup() {
        let grid = Self.makeGrid()
        grid.recordRecentSearch("Cat")
        grid.recordRecentSearch("CAT")
        grid.recordRecentSearch("cat")
        // 三个变体都视作重复, 最终 list 只剩 ["cat"] (最近一次用的小写形式保留)
        #expect(grid.recentSearches == ["cat"])
    }

    @Test func trimWhitespaceEmptySkipped() {
        let grid = Self.makeGrid()
        grid.recordRecentSearch("   ")
        grid.recordRecentSearch("\t\n")
        #expect(grid.recentSearches.isEmpty)
    }

    @Test func trimWhitespacePreservesContent() {
        let grid = Self.makeGrid()
        grid.recordRecentSearch("  cat  ")
        // trim 后存 "cat" (V6.74.4 dedup/排序都用 trimmed)
        #expect(grid.recentSearches == ["cat"])
    }

    @Test func cap20OldestDropped() {
        let grid = Self.makeGrid()
        // 输入 25 个不同 query
        for i in 0..<25 {
            grid.recordRecentSearch("query-\(i)")
        }
        // 只保留最近 20 个, 最先输入的 "query-0"..."query-4" 被丢弃
        #expect(grid.recentSearches.count == 20)
        #expect(grid.recentSearches.first == "query-24")  // 最新在最前
        #expect(!grid.recentSearches.contains("query-0"))
        #expect(!grid.recentSearches.contains("query-4"))
        #expect(grid.recentSearches.contains("query-5"))
    }

    @Test func cap20WithDedupKeepsUnique() {
        let grid = Self.makeGrid()
        // 输入 30 个查询, 其中 10 个重复, 期望最后剩 20 unique
        for i in 0..<30 {
            grid.recordRecentSearch("query-\(i % 20)")  // 0..19, 0..9 各重复 1 次
        }
        #expect(grid.recentSearches.count == 20)
        // 最新 input 是 i=29 (29 % 20 = 9) → "query-9" 移到最前
        #expect(grid.recentSearches.first == "query-9")
        // 老 query (i=0 的 "query-0" 已被挤掉, 因为它只出现 1 次在最早, 后续 dedup 不在前列)
        // 实际: query-0 在 i=0 出现, i=20 又出现, 第二次出现移到最前 (i=20 时刻)
        // 然后被 query-1..9 推后, 但 query-1..9 在 i=21..29 又出现, 推 query-0 出去
        // 最终 list 包含 query-10..19 (出现 1 次, 最新) + query-10..19 没被 cap 推走因为它们在前
        #expect(grid.recentSearches.contains("query-9"))
        #expect(grid.recentSearches.contains("query-19"))
    }

    @Test func emptyStringSkipped() {
        let grid = Self.makeGrid()
        grid.recordRecentSearch("")
        #expect(grid.recentSearches.isEmpty)
    }
}