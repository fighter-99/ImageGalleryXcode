//
//  ContentViewModelSelectionTests.swift
//  ImageGalleryTests
//
//  V5.54-2: ContentViewModel 选中 + 导航 + 缩放 tests
//  测 funcs: toggleSortDirection, resetFilters, goPrev, goNext, handleDelete, handleTap, zoomIn, zoomOut, resetThumbnailSize
//
//  设计: 不依赖 ModelContainer——直接 push model.grid.allPhotos = [photo1, photo2, ...]
//  (func body 内部只读 allPhotos, 不写, 无需持久化)
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct ContentViewModelSelectionTests {

    // V6.12.20: 共享 suite + cleanup pattern (避开 UserDefaults.standard 跨 test 污染)
    //   跟 ContentViewModelStateTests.isolatedModel 同源——共享 1 个 suite, 每个 test cleanup
    //   避免每次 UUID 新 suite 给 cfprefsd 压力 (memory: swift-testing-userdefaults-parallel-crash)
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

    // MARK: - 测试数据工厂

    /// 构造带 N 张虚拟 photo 的 model（不写盘，纯内存）
    private func makeModelWithPhotos(_ count: Int) -> ContentViewModel {
        let model = Self.isolatedModel()
        let photos = (0..<count).map { i in
            Photo(
                filename: "test_\(i).jpg",
                fileURL: URL(fileURLWithPath: "/tmp/V554_\(i).jpg"),
                fileSize: Int64(1000 * (i + 1)),
                width: 100,
                height: 100
            )
        }
        model.grid.allPhotos = photos
        return model
    }

    // MARK: - toggleSortDirection

    @Test func toggleSortDirection_fromAsc_flipsToDesc() {
        let model = Self.isolatedModel()
        #expect(model.grid.sortOption == .filenameAsc)
        model.toggleSortDirection()
        #expect(model.grid.sortOption == .filenameDesc)
    }

    @Test func toggleSortDirection_fromDesc_flipsToAsc() {
        let model = Self.isolatedModel()
        model.grid.sortOption = .filenameDesc
        model.toggleSortDirection()
        #expect(model.grid.sortOption == .filenameAsc)
    }

    @Test func toggleSortDirection_toggleTwice_returnsToOriginal() {
        let model = Self.isolatedModel()
        let original = model.grid.sortOption
        model.toggleSortDirection()
        model.toggleSortDirection()
        #expect(model.grid.sortOption == original)
    }

    // MARK: - resetFilters

    @Test func resetFilters_clearsAllFilterState() {
        let model = Self.isolatedModel()
        // 预设一堆 dirty state
        model.sidebarSelection = .recent7Days
        model.grid.searchText = "query"
        model.filterState = FilterState(folders: [UUID()], tags: [], shapes: [.square], minRating: 5)
        // 改 default sort/thumbnail（resetFilters 不应清这些——只清 filters）
        model.grid.sortOption = .fileSizeDesc
        model.grid.thumbnailSize = 240

        model.grid.resetFilters()

        #expect(model.sidebarSelection == .all)
        #expect(model.grid.searchText == "")
        #expect(model.filterState == .empty)
        // sort/thumbnail 不应被 reset
        #expect(model.grid.sortOption == .fileSizeDesc)
        #expect(model.grid.thumbnailSize == 240)
    }

    // MARK: - goPrev / goNext

    @Test func goPrev_noSelection_isNoOp() {
        let model = makeModelWithPhotos(3)
        // 没有 selected
        model.grid.goPrev()
        // selection 仍空
        #expect(model.grid.selection.isEmpty)
    }

    @Test func goPrev_atFirstPhoto_isNoOp() {
        let model = makeModelWithPhotos(3)
        // 选中第 0 张 (最前)
        model.grid.selection = model.grid.selection.selectingSingle(model.grid.allPhotos[0].id)
        let before = model.grid.selection.singleSelectedID
        model.grid.goPrev()
        // idx 已经是 0, goPrev 应该是 no-op
        #expect(model.grid.selection.singleSelectedID == before)
    }

    @Test func goPrev_advancesToPreviousPhoto() {
        let model = makeModelWithPhotos(3)
        // 选中第 1 张（中间）
        model.grid.selection = model.grid.selection.selectingSingle(model.grid.allPhotos[1].id)
        // 确保当前 sort 是 filenameAsc 顺序 (model.grid.allPhotos 顺序)
        // sidebarSelection = .all, filterUnfiled = false, filterDuplicates = false, filterRecent7Days = false
        // visiblePhotos 应等于 allPhotos
        #expect(model.grid.visiblePhotos.count == 3)
        model.grid.goPrev()
        // 应选中第 0 张
        #expect(model.grid.selection.singleSelectedID == model.grid.allPhotos[0].id)
    }

    @Test func goNext_atLastPhoto_isNoOp() {
        let model = makeModelWithPhotos(3)
        // 选中最后一张
        model.grid.selection = model.grid.selection.selectingSingle(model.grid.allPhotos[2].id)
        let before = model.grid.selection.singleSelectedID
        model.grid.goNext()
        // 最后一张已是末尾, goNext no-op
        #expect(model.grid.selection.singleSelectedID == before)
    }

    @Test func goNext_advancesToNextPhoto() {
        let model = makeModelWithPhotos(3)
        model.grid.selection = model.grid.selection.selectingSingle(model.grid.allPhotos[1].id)
        model.grid.goNext()
        // 应选中第 2 张
        #expect(model.grid.selection.singleSelectedID == model.grid.allPhotos[2].id)
    }

    // MARK: - handleDelete

    @Test func handleDelete_noSelection_isNoOp() {
        let model = makeModelWithPhotos(2)
        // 没有 selected, handleDelete 应该是 no-op
        model.grid.handleDelete()
        #expect(model.grid.selection.isEmpty)
        #expect(model.grid.showingBatchDeleteConfirm == false)
    }

    @Test func handleDelete_withMultiSelection_setsBatchConfirm() {
        let model = makeModelWithPhotos(3)
        // 多选
        model.grid.selection = .empty
            .settingAll(in: [model.grid.allPhotos[0], model.grid.allPhotos[1]])
        model.grid.handleDelete()
        // 应弹 batch delete confirm (不是真的删——等用户确认)
        #expect(model.grid.showingBatchDeleteConfirm == true)
    }

    // MARK: - zoomIn / zoomOut / resetThumbnailSize

    @Test func zoomIn_fromDefault_advancesToLarger() {
        let model = Self.isolatedModel()
        let before = model.grid.thumbnailSize
        model.grid.zoomIn()
        #expect(model.grid.thumbnailSize > before, "zoomIn 应增大 thumbnailSize")
    }

    @Test func zoomOut_fromDefault_advancesToSmaller() {
        let model = Self.isolatedModel()
        let before = model.grid.thumbnailSize
        model.grid.zoomOut()
        #expect(model.grid.thumbnailSize < before, "zoomOut 应减小 thumbnailSize")
    }

    @Test func zoomIn_atMax_isNoOp() {
        let model = Self.isolatedModel()
        // 设到最大
        while let next = ThumbnailDensity.larger(than: model.grid.thumbnailSize) {
            model.grid.thumbnailSize = next.size
        }
        let maxSize = model.grid.thumbnailSize
        model.grid.zoomIn()
        #expect(model.grid.thumbnailSize == maxSize, "已最大, zoomIn no-op")
    }

    @Test func resetThumbnailSize_restoresStoredDefault() {
        // V6.14.8: 恢复这个 test — production 拆 liveThumbnailSize + settings.thumbnailSize
        //   1) 改 stored default (Settings 入口)
        //   2) 改 live size (zoom in/out 入口) — 不污染 stored
        //   3) reset ⌘0 清 live → 回到 stored
        let model = Self.isolatedModel()
        // 改 stored default
        model.settings.thumbnailSize = 240
        // 改 live size 到别的 (通过 thumbnailSize setter, 走 liveThumbnailSize)
        model.grid.thumbnailSize = 110
        model.grid.resetThumbnailSize()
        #expect(model.grid.thumbnailSize == 240, "⌘0 应清 live, 回到 stored default")
    }

    @Test func zoomIn_doesNotPolluteStoredDefault() {
        // V6.14.8: 验 zoom in 写 live, 不动 stored
        let model = Self.isolatedModel()
        let storedBefore = model.settings.thumbnailSize
        model.grid.zoomIn()
        #expect(model.grid.thumbnailSize != CGFloat(storedBefore),
                "zoomIn 后 live 改了, 应跟 stored 不同")
        #expect(model.settings.thumbnailSize == storedBefore,
                "zoomIn 不应污染 stored (跟 ⌘0 行为一致)")
    }
}
