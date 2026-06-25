//
//  SmartFolderCreateTests.swift
//  ImageGalleryTests
//
//  P4.1.1 智能文件夹创建 + filter 实际生效 — 测试
//
//  测 funcs: SmartFolder JSON roundtrip, ContentViewModel.createSmartFolder,
//            currentSmartFolder, currentViewTitle, PhotoStats.filtered w/ smartFolderFilter
//
//  沿用 V6.14.7 isolatedDefaults + per-test ModelContainer 模式
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct SmartFolderCreateTests {

    // 共享 suite + cleanup (跟 ContentViewModelBatchTests / StateTests 同源)
    @MainActor
    private static let isolatedDefaults: UserDefaults = FakeUserDefaults()
    private static let userSettingsKeys: [String] = [
        "viewModeRaw", "showSidebar", "accentColorID",
        "trashRetentionDays", "appearanceMode", "thumbnailSize",
        "sidebarSelection", "sortOption", "thumbnailLayoutMode",
        "sidebarColumnWidth", "autoDeduplicate",
        "autoGenerateThumbnails", "defaultExportFormat",
        "defaultExportQuality", "scrollAnchorPhotoID"
    ]
    private static func isolatedModel() -> ContentViewModel {
        for key in userSettingsKeys { isolatedDefaults.removeObject(forKey: key) }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }
    private static func isolatedContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Photo.self, Folder.self, Tag.self, SmartFolder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - SmartFolder model + JSON roundtrip

    @Test func smartFolder_init_persistsFilterAsJSON() {
        let folderID = UUID()
        let tagID = UUID()
        let filter = FilterState(
            folders: [folderID], tags: [tagID], shapes: [.square], minRating: 4
        )
        let sf = SmartFolder(name: "Best Squares", iconName: "star.fill", filterState: filter)
        #expect(sf.decodedFilter == filter, "JSON encode → decode round-trip 必须保留 filter")
    }

    @Test func smartFolder_emptyFilter_roundTripsAsEmpty() {
        let sf = SmartFolder(name: "All", iconName: "photo.stack.fill", filterState: .empty)
        #expect(sf.decodedFilter == .empty)
        #expect(sf.decodedFilter.isActive == false)
    }

    @Test func smartFolder_init_defaultsIconAndOrder() {
        let sf = SmartFolder(name: "X")
        #expect(sf.iconName == "star.fill", "默认 iconName = star.fill")
        #expect(sf.order == 0, "默认 order = 0")
    }

    @Test func smartFolder_updateFilter_overwritesJSON() {
        let sf = SmartFolder(name: "X", iconName: "star.fill", filterState: .empty)
        let newFilter = FilterState(minRating: 5)
        sf.updateFilter(newFilter)
        #expect(sf.decodedFilter == newFilter)
    }

    // MARK: - SmartFolderIcon enum

    @Test func smartFolderIcon_hasThirteenCases() {
        #expect(SmartFolderIcon.allCases.count == 13)
    }

    @Test func smartFolderIcon_displayNameIsNonEmpty() {
        for icon in SmartFolderIcon.allCases {
            #expect(!icon.displayName.isEmpty, "\(icon.rawValue) 必须有 display name (i18n 兜底)")
        }
    }

    @Test func smartFolderIcon_rawValuesAreSFSymbols() {
        for icon in SmartFolderIcon.allCases {
            #expect(icon.rawValue.contains(".fill") || icon.rawValue == "sparkles",
                   "\(icon.rawValue) 应该是 SF Symbol 格式")
        }
    }

    // MARK: - ContentViewModel.createSmartFolder

    @Test func createSmartFolder_insertsAndSelects() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        model.createSmartFolder(name: "Best 2024", iconName: "star.fill", filterState: .empty)

        let smartFolders = try container.mainContext.fetch(FetchDescriptor<SmartFolder>())
        #expect(smartFolders.count == 1)
        #expect(smartFolders.first?.name == "Best 2024")
        if case .smartFolder(let id) = model.sidebarSelection {
            #expect(id == smartFolders.first?.id, "auto-select 新创建的 smart folder")
        } else {
            Issue.record("sidebarSelection 应该是 .smartFolder after create")
        }
    }

    @Test func createSmartFolder_emptyName_noOp() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        model.createSmartFolder(name: "  ", iconName: "star.fill", filterState: .empty)
        let smartFolders = try container.mainContext.fetch(FetchDescriptor<SmartFolder>())
        #expect(smartFolders.isEmpty, "空白 name 不应 insert")
    }

    @Test func createSmartFolder_assignsIncrementingOrder() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        // 用 cache 模拟 sidebar @Query 推送 (跟 ContentView .onChange 路径一致)
        model.createSmartFolder(name: "A", iconName: "star.fill", filterState: .empty)
        let sfA = try container.mainContext.fetch(FetchDescriptor<SmartFolder>()).first
        model.grid.smartFoldersCache = [sfA!].compactMap { $0 }
        model.createSmartFolder(name: "B", iconName: "heart.fill", filterState: .empty)
        let sfs2 = try container.mainContext.fetch(FetchDescriptor<SmartFolder>(sortBy: [SortDescriptor(\.order)]))
        model.grid.smartFoldersCache = sfs2
        model.createSmartFolder(name: "C", iconName: "flame.fill", filterState: .empty)

        let sfs = try container.mainContext.fetch(FetchDescriptor<SmartFolder>(sortBy: [SortDescriptor(\.order)]))
        #expect(sfs.map(\.name) == ["A", "B", "C"])
        #expect(sfs.map(\.order) == [0, 1, 2])
    }

    @Test func createSmartFolder_persistsFilter() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        let filter = FilterState(shapes: [.landscape], minRating: 3)
        model.createSmartFolder(name: "Landscape 3+", iconName: "photo.stack.fill", filterState: filter)

        let sf = try container.mainContext.fetch(FetchDescriptor<SmartFolder>()).first
        #expect(sf?.decodedFilter == filter, "filter 应通过 JSON 持久化")
    }

    // MARK: - currentSmartFolder

    @Test func currentSmartFolder_returnsFetchedEntity() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        let sf = SmartFolder(name: "Test", iconName: "star.fill", filterState: .empty)
        container.mainContext.insert(sf)
        try container.mainContext.save()
        model.sidebarSelection = .smartFolder(sf.id)

        #expect(model.grid.currentSmartFolder?.id == sf.id)
    }

    @Test func currentSmartFolder_deletedReturnsNil() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        let sf = SmartFolder(name: "Test", iconName: "star.fill", filterState: .empty)
        container.mainContext.insert(sf)
        try container.mainContext.save()
        model.sidebarSelection = .smartFolder(sf.id)

        container.mainContext.delete(sf)
        try container.mainContext.save()

        #expect(model.grid.currentSmartFolder == nil, "删后 fetch 返 nil (V6.08 dangling ref 防护)")
    }

    // MARK: - smartFolderFilter

    @Test func smartFolderFilter_returnsDecodedFilter() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        let filter = FilterState(shapes: [.square], minRating: 4)
        let sf = SmartFolder(name: "Best Squares", iconName: "star.fill", filterState: filter)
        container.mainContext.insert(sf)
        try container.mainContext.save()
        model.sidebarSelection = .smartFolder(sf.id)

        #expect(model.grid.smartFolderFilter == filter)
    }

    @Test func smartFolderFilter_nilWhenNotActive() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .all
        #expect(model.grid.smartFolderFilter == nil, "非 .smartFolder selection → nil")
    }

    // MARK: - currentViewTitle

    @Test func currentViewTitle_forSmartFolderReturnsName() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        let sf = SmartFolder(name: "Vacation 2024", iconName: "sun.max.fill", filterState: .empty)
        container.mainContext.insert(sf)
        try container.mainContext.save()
        model.sidebarSelection = .smartFolder(sf.id)

        #expect(model.grid.currentViewTitle == "Vacation 2024")
    }

    @Test func currentViewTitle_forDeletedSmartFolderFallback() throws {
        let container = try Self.isolatedContainer()
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext

        let sf = SmartFolder(name: "X", iconName: "star.fill", filterState: .empty)
        container.mainContext.insert(sf)
        try container.mainContext.save()
        model.sidebarSelection = .smartFolder(sf.id)

        container.mainContext.delete(sf)
        try container.mainContext.save()

        #expect(model.grid.currentViewTitle == Copy.smartFolderFallback)
    }

    // MARK: - PhotoStats.filtered with smartFolderFilter

    @Test func filtered_smartFolderFilter_appliesFolders() throws {
        let container = try Self.isolatedContainer()
        let folder = Folder(name: "F")
        container.mainContext.insert(folder)
        let photo = Photo(
            filename: "p.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SFC_filter_\(UUID().uuidString).jpg"),
            fileSize: 100, width: 100, height: 100
        )
        photo.folder = folder
        container.mainContext.insert(photo)
        try container.mainContext.save()

        let sff = FilterState(folders: [folder.id])
        let result = PhotoStats.filtered(
            [photo], folder: nil, tag: nil, searchText: "",
            sortOption: .filenameAsc,
            filterUnfiled: false, filterDuplicates: false,
            filterRecent7Days: false, filterLargeFiles: false, filterInTrash: false,
            smartFolderFilter: sff
        )
        #expect(result.count == 1, "folder 维度匹配")
    }

    @Test func filtered_smartFolderFilter_empty_noEffect() throws {
        let container = try Self.isolatedContainer()
        let photo = Photo(
            filename: "p.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SFC_empty_\(UUID().uuidString).jpg"),
            fileSize: 100, width: 100, height: 100
        )
        container.mainContext.insert(photo)
        try container.mainContext.save()

        let result = PhotoStats.filtered(
            [photo], folder: nil, tag: nil, searchText: "",
            sortOption: .filenameAsc,
            filterUnfiled: false, filterDuplicates: false,
            filterRecent7Days: false, filterLargeFiles: false, filterInTrash: false,
            smartFolderFilter: FilterState.empty
        )
        #expect(result.count == 1, "empty smart folder filter 必须是 no-op")
    }

    @Test func filtered_smartFolderFilter_minRating() {
        let high = Photo(
            filename: "h.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SFC_h_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 1, height: 1
        )
        high.rating = 5
        let low = Photo(
            filename: "l.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SFC_l_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 1, height: 1
        )
        low.rating = 2

        let sff = FilterState(minRating: 4)
        let result = PhotoStats.filtered(
            [high, low], folder: nil, tag: nil, searchText: "",
            sortOption: .filenameAsc,
            filterUnfiled: false, filterDuplicates: false,
            filterRecent7Days: false, filterLargeFiles: false, filterInTrash: false,
            smartFolderFilter: sff
        )
        #expect(result.count == 1)
        #expect(result[0].id == high.id)
    }

    @Test func filtered_smartFolderFilter_ANDWithToolbarFilter() throws {
        // smart folder 跟 toolbar filter 都应用, AND
        let container = try Self.isolatedContainer()
        let folder = Folder(name: "F")
        container.mainContext.insert(folder)
        let p1 = Photo(
            filename: "a.jpg", fileURL: URL(fileURLWithPath: "/tmp/SFC_and_a.jpg"),
            fileSize: 0, width: 1, height: 1
        )
        p1.folder = folder
        p1.rating = 5
        let p2 = Photo(
            filename: "b.jpg", fileURL: URL(fileURLWithPath: "/tmp/SFC_and_b.jpg"),
            fileSize: 0, width: 1, height: 1
        )
        p2.folder = folder
        p2.rating = 2
        container.mainContext.insert(p1)
        container.mainContext.insert(p2)
        try container.mainContext.save()

        // smart folder: folder=F, toolbar filter: minRating=4
        // 期望: 只有 p1 (满足 AND)
        let sff = FilterState(folders: [folder.id])
        let result = PhotoStats.filtered(
            [p1, p2], folder: nil, tag: nil, searchText: "",
            sortOption: .filenameAsc,
            filterUnfiled: false, filterDuplicates: false,
            filterRecent7Days: false, filterLargeFiles: false, filterInTrash: false,
            selectedFolderIDs: [], selectedTagIDs: [],
            selectedShapes: [], minRating: 4,
            smartFolderFilter: sff
        )
        #expect(result.count == 1)
        #expect(result[0].id == p1.id, "smart folder + toolbar filter 双重 AND")
    }

    @Test func smartFolderCount_handlesEmptyFilter() {
        let photo = Photo(
            filename: "p.jpg", fileURL: URL(fileURLWithPath: "/tmp/SFC_count.jpg"),
            fileSize: 0, width: 1, height: 1
        )
        #expect(PhotoStats.smartFolderCount([photo], smartFolderFilter: .empty) == 1,
                "empty smart folder filter → 命中全部")
    }
}
