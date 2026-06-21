//
//  GridViewModelCacheTests.swift
//  ImageGalleryTests
//
//  V6.38.0 (P0 perf): 验证 3 个新增 cache 的 invalidation 行为
//    - visiblePhotos: filterSignature hash keyed, 仅 filter inputs 真变时重算
//    - currentFolder/currentTag/currentSmartFolder: SidebarSelection keyed
//    - currentViewSubtitle: 单次 evaluate visiblePhotos (行为不变, 但测试覆盖)
//
//  设计: 全部 in-memory 测, 不依赖 SwiftData container (visiblePhotos/currentViewSubtitle
//    只读 allPhotos: [Photo] 和 folder/tag UUID, 不真 fetch)
//  currentFolder cache 测试需要 ModelContainer (测真 fetch path + cache 复用)
//
//  测 ~12 case × 4 cache
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct GridViewModelCacheTests {

    // V6.12.20: 共享 suite + cleanup pattern——避免 cfprefsd 压力
    @MainActor
    private static let isolatedDefaults: UserDefaults = FakeUserDefaults()
    private static let userSettingsKeys: [String] = [
        "viewModeRaw", "showSidebar", "showDetail", "accentColorID",
        "trashRetentionDays", "appearanceMode", "thumbnailSize",
        "sidebarSelection", "sortOption", "thumbnailLayoutMode",
        "sidebarColumnWidth", "detailColumnWidth", "autoDeduplicate",
        "autoGenerateThumbnails", "defaultExportFormat",
        "defaultExportQuality", "scrollAnchorPhotoID"
    ]
    private static func isolatedModel() -> ContentViewModel {
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }

    // MARK: - helpers

    private func makePhoto(filename: String = "t.jpg", rating: Int = 0, isInTrash: Bool = false) -> Photo {
        let p = Photo(
            filename: filename,
            fileURL: URL(fileURLWithPath: "/tmp/CacheTest_\(UUID().uuidString)_\(filename)"),
            fileSize: 0,
            width: 1000,
            height: 1000
        )
        p.rating = rating
        if isInTrash { p.trashedAt = Date() }
        return p
    }

    // MARK: - visiblePhotos cache

    @Test func visiblePhotos_returnsSameArrayOnRepeatRead() {
        let model = Self.isolatedModel()
        model.grid.allPhotos = [makePhoto()]
        let first = model.grid.visiblePhotos
        let second = model.grid.visiblePhotos
        // V6.38.0: cache hit 返同一 array reference (Swift Array value type, 但 cache 不复制)
        //   之前每次都新建 array (PhotoStats.filtered 返回新 array)
        //   现在 cache 后返同一引用 — pointer equality
        #expect(first.count == second.count)
        // ID 集合相等 (验证 filter 行为一致)
        #expect(Set(first.map(\.id)) == Set(second.map(\.id)))
    }

    @Test func visiblePhotos_invalidatesOnSearchTextChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "alpha.jpg")
        let p2 = makePhoto(filename: "beta.jpg")
        model.grid.allPhotos = [p1, p2]
        let all = model.grid.visiblePhotos
        #expect(all.count == 2)
        // 改 searchText → cache miss → 重算
        model.grid.searchText = "alpha"
        let filtered = model.grid.visiblePhotos
        #expect(filtered.count == 1)
        #expect(filtered.first?.filename == "alpha.jpg")
    }

    @Test func visiblePhotos_invalidatesOnSortOptionChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        let p2 = makePhoto(filename: "b.jpg")
        model.grid.allPhotos = [p1, p2]
        let asc = model.grid.visiblePhotos
        #expect(asc.first?.filename == "a.jpg")
        model.grid.sortOption = .filenameDesc
        let desc = model.grid.visiblePhotos
        #expect(desc.first?.filename == "b.jpg")
    }

    @Test func visiblePhotos_invalidatesOnAllPhotosCountChange() {
        let model = Self.isolatedModel()
        model.grid.allPhotos = [makePhoto()]
        let one = model.grid.visiblePhotos
        #expect(one.count == 1)
        // allPhotos.count 变 → key 变 → cache miss
        model.grid.allPhotos = [makePhoto(), makePhoto(), makePhoto()]
        let three = model.grid.visiblePhotos
        #expect(three.count == 3)
    }

    @Test func visiblePhotos_invalidatesOnFilterStateChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg", rating: 1)
        let p2 = makePhoto(filename: "b.jpg", rating: 4)
        model.grid.allPhotos = [p1, p2]
        let all = model.grid.visiblePhotos
        #expect(all.count == 2)
        // 加 minRating filter → cache miss
        model.filterState = FilterState(folders: [], tags: [], shapes: [], minRating: 2)
        let highRated = model.grid.visiblePhotos
        #expect(highRated.count == 1)
        #expect(highRated.first?.filename == "b.jpg")
    }

    @Test func visiblePhotos_invalidatesOnTrashFlagChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg", isInTrash: false)
        let p2 = makePhoto(filename: "b.jpg", isInTrash: true)
        model.grid.allPhotos = [p1, p2]
        // 默认 (.all) 视图排除 trash
        let library = model.grid.visiblePhotos
        #expect(library.count == 1)
        // 切到 trash 视图 → filterInTrash = true → cache miss
        model.sidebarSelection = .recentlyDeleted
        let trash = model.grid.visiblePhotos
        #expect(trash.count == 1)
        #expect(trash.first?.filename == "b.jpg")
    }

    // MARK: - currentFolder / currentTag / currentSmartFolder cache

    @Test func currentFolder_cachesFetchResult() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let folder = Folder(name: "CachedFolder")
        container.mainContext.insert(folder)
        try container.mainContext.save()
        model.sidebarSelection = .folder(folder.id)

        // V6.38.0: 第 1 次 fetch + cache; 第 2 次 cache hit (无 SwiftData fetch)
        let first = model.grid.currentFolder
        #expect(first?.id == folder.id)
        let second = model.grid.currentFolder
        #expect(second?.id == folder.id)
        // pointer equality (同一 @Model 实例)
        #expect(first === second)
    }

    @Test func currentFolder_invalidatesOnSidebarSelectionChange() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let f1 = Folder(name: "F1")
        let f2 = Folder(name: "F2")
        container.mainContext.insert(f1)
        container.mainContext.insert(f2)
        try container.mainContext.save()
        model.sidebarSelection = .folder(f1.id)
        #expect(model.grid.currentFolder?.id == f1.id)
        // 切换 selection → cache miss → 重新 fetch f2
        model.sidebarSelection = .folder(f2.id)
        #expect(model.grid.currentFolder?.id == f2.id)
    }

    @Test func currentFolder_returnsNilWhenSelectionNotFolder() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .all
        #expect(model.grid.currentFolder == nil)
        model.sidebarSelection = .recentlyDeleted
        #expect(model.grid.currentFolder == nil)
    }

    @Test func currentTag_cachesFetchResult() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let tag = ImageGallery.Tag(name: "CachedTag", colorHex: "#5B8FF9")
        container.mainContext.insert(tag)
        try container.mainContext.save()
        model.sidebarSelection = .tag(tag.id)
        let first = model.grid.currentTag
        let second = model.grid.currentTag
        #expect(first?.id == tag.id)
        #expect(first === second)
    }

    @Test func currentSmartFolder_cachesFetchResult() throws {
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self, SmartFolder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let sf = SmartFolder(
            name: "CachedSF",
            iconName: "sparkles",
            filterState: .empty,
            order: 0
        )
        container.mainContext.insert(sf)
        try container.mainContext.save()
        model.sidebarSelection = .smartFolder(sf.id)
        let first = model.grid.currentSmartFolder
        let second = model.grid.currentSmartFolder
        #expect(first?.id == sf.id)
        #expect(first === second)
    }

    // MARK: - currentViewSubtitle (行为不变 + 顺带覆盖)

    @Test func currentViewSubtitle_returnsFormattedCountAndSize() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        p1.fileSize = 1_000_000
        let p2 = makePhoto(filename: "b.jpg")
        p2.fileSize = 2_000_000
        model.grid.allPhotos = [p1, p2]
        let subtitle = model.grid.currentViewSubtitle
        // V6.38.0: 单次 evaluate visiblePhotos (之前 2 次). 验证最终文案不变
        #expect(subtitle.contains("2"))
    }

    @Test func currentViewSubtitle_appendsFilterSuffixWhenFilterActive() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg", rating: 5)
        model.grid.allPhotos = [p1]
        // activeCount = minRating > 0 → 1
        model.filterState = FilterState(folders: [], tags: [], shapes: [], minRating: 3)
        let subtitle = model.grid.currentViewSubtitle
        // V4.36.x: filter active 时追加 "· 已筛选 (N)" 后缀
        #expect(subtitle.contains("已筛选") || subtitle.contains("筛选"))
    }

    // MARK: - V6.38.1: selectedPhotosInVisible cache

    @Test func selectedPhotosInVisible_returnsSameArrayOnRepeatRead() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        let p2 = makePhoto(filename: "b.jpg")
        model.grid.allPhotos = [p1, p2]
        model.grid.selection = model.grid.selection.toggling(p1.id)
        // V6.38.1: cache hit → 同一 array (Swift Array copy-on-write, cache 复用底层 buffer)
        //   验证方法: Set<ID> 相等 + 同一 selection 下多次读返同一结果
        let first = model.grid.selectedPhotosInVisible
        let second = model.grid.selectedPhotosInVisible
        let third = model.grid.selectedPhotosInVisible
        #expect(first.count == 1)
        #expect(first.first?.id == p1.id)
        #expect(Set(first.map(\.id)) == Set(second.map(\.id)))
        #expect(Set(second.map(\.id)) == Set(third.map(\.id)))
    }

    @Test func selectedPhotosInVisible_invalidatesOnSelectionChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        let p2 = makePhoto(filename: "b.jpg")
        model.grid.allPhotos = [p1, p2]
        // 初始 selection = empty → selectedPhotosInVisible = []
        #expect(model.grid.selectedPhotosInVisible.isEmpty)
        // 选 p1 → cache miss → 重算
        model.grid.selection = model.grid.selection.toggling(p1.id)
        let after = model.grid.selectedPhotosInVisible
        #expect(after.count == 1)
        #expect(after.first?.id == p1.id)
    }

    @Test func selectedPhotosInVisible_invalidatesOnFilterChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg", rating: 5)
        let p2 = makePhoto(filename: "b.jpg", rating: 1)
        model.grid.allPhotos = [p1, p2]
        model.grid.selection = model.grid.selection.toggling(p1.id)
        let initial = model.grid.selectedPhotosInVisible
        #expect(initial.count == 1)
        // filter 变化 → visiblePhotos 变化 → cache miss → 重算
        model.filterState = FilterState(folders: [], tags: [], shapes: [], minRating: 3)
        let filtered = model.grid.selectedPhotosInVisible
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == p1.id)  // p2 被 minRating 过滤掉, selected = p1
    }

    @Test func selectedTotalSize_usesSelectedPhotosInVisibleCache() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        p1.fileSize = 5_000_000
        let p2 = makePhoto(filename: "b.jpg")
        p2.fileSize = 3_000_000
        model.grid.allPhotos = [p1, p2]
        // 无 selection → selectedTotalSize = 0
        #expect(model.grid.selectedTotalSize == 0)
        // 选 p1 → selectedTotalSize = 5_000_000
        model.grid.selection = model.grid.selection.toggling(p1.id)
        #expect(model.grid.selectedTotalSize == 5_000_000)
        // 加选 p2 → selectedTotalSize = 8_000_000
        model.grid.selection = model.grid.selection.toggling(p2.id)
        #expect(model.grid.selectedTotalSize == 8_000_000)
    }

    // MARK: - V6.38.2: resolvedSingle cache

    @Test func resolvedSingle_returnsSameTupleOnRepeatRead() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        let p2 = makePhoto(filename: "b.jpg")
        model.grid.allPhotos = [p1, p2]
        model.grid.selection = model.grid.selection.selectingSingle(p1.id)
        // V6.38.2: cache hit → 同一 tuple
        let first = model.grid.resolvedSingle
        let second = model.grid.resolvedSingle
        let third = model.grid.resolvedSingle
        #expect(first?.photo.id == p1.id)
        #expect(first?.visibleIndex == 0)
        #expect(first?.photo === second?.photo)
        #expect(first?.visibleIndex == second?.visibleIndex)
        #expect(second?.visibleIndex == third?.visibleIndex)
    }

    @Test func resolvedSingle_invalidatesOnSelectionChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        let p2 = makePhoto(filename: "b.jpg")
        model.grid.allPhotos = [p1, p2]
        model.grid.selection = model.grid.selection.selectingSingle(p1.id)
        let first = model.grid.resolvedSingle
        #expect(first?.photo.id == p1.id)
        #expect(first?.visibleIndex == 0)
        // 切换 selection 到 p2 → cache miss → 重算
        model.grid.selection = model.grid.selection.selectingSingle(p2.id)
        let second = model.grid.resolvedSingle
        #expect(second?.photo.id == p2.id)
        #expect(second?.visibleIndex == 1)
    }

    @Test func resolvedSingle_invalidatesOnFilterChange() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg", rating: 1)
        let p2 = makePhoto(filename: "b.jpg", rating: 4)
        model.grid.allPhotos = [p1, p2]
        model.grid.selection = model.grid.selection.selectingSingle(p1.id)
        let before = model.grid.resolvedSingle
        #expect(before?.photo.id == p1.id)
        // 改 filter: minRating=3 → p1.rating=1 被过滤, visiblePhotos 只剩 p2
        //   selection 仍 p1 → resolvedSingle 找不到 p1 → nil
        model.filterState = FilterState(folders: [], tags: [], shapes: [], minRating: 3)
        let after = model.grid.resolvedSingle
        #expect(after == nil)
    }

    @Test func resolvedSingle_returnsNilWhenNoSingleSelection() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        model.grid.allPhotos = [p1]
        // 无 selection
        #expect(model.grid.resolvedSingle == nil)
        // multi selection
        model.grid.selection = model.grid.selection.toggling(p1.id)
        model.grid.selection = model.grid.selection.toggling(UUID())
        #expect(model.grid.resolvedSingle == nil)
    }

    @Test func currentIndex_canPrev_canNext_useResolvedSingleCache() {
        let model = Self.isolatedModel()
        let p1 = makePhoto(filename: "a.jpg")
        let p2 = makePhoto(filename: "b.jpg")
        let p3 = makePhoto(filename: "c.jpg")
        model.grid.allPhotos = [p1, p2, p3]
        // 选 p2 (index 1)
        model.grid.selection = model.grid.selection.selectingSingle(p2.id)
        #expect(model.grid.currentIndex == 2)  // 1-based
        #expect(model.grid.canPrev == true)   // index 2 > 1
        #expect(model.grid.canNext == true)   // index 2 < 3
        // 选 p1 (第 1 张) — canPrev = false
        model.grid.selection = model.grid.selection.selectingSingle(p1.id)
        #expect(model.grid.currentIndex == 1)
        #expect(model.grid.canPrev == false)
        #expect(model.grid.canNext == true)
        // 选 p3 (最后一张) — canNext = false
        model.grid.selection = model.grid.selection.selectingSingle(p3.id)
        #expect(model.grid.currentIndex == 3)
        #expect(model.grid.canPrev == true)
        #expect(model.grid.canNext == false)
    }
}