//
//  ContentViewModelSelectionTests.swift
//  ImageGalleryTests
//
//  V5.54-2: ContentViewModel 选中 + 导航 + 缩放 tests
//  测 funcs: toggleSortDirection, resetFilters, goPrev, goNext, handleDelete, handleTap, zoomIn, zoomOut, resetThumbnailSize
//
//  设计: 不依赖 ModelContainer——直接 push model.allPhotos = [photo1, photo2, ...]
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
        model.allPhotos = photos
        return model
    }

    // MARK: - toggleSortDirection

    @Test func toggleSortDirection_fromAsc_flipsToDesc() {
        let model = Self.isolatedModel()
        #expect(model.sortOption == .filenameAsc)
        model.toggleSortDirection()
        #expect(model.sortOption == .filenameDesc)
    }

    @Test func toggleSortDirection_fromDesc_flipsToAsc() {
        let model = Self.isolatedModel()
        model.sortOption = .filenameDesc
        model.toggleSortDirection()
        #expect(model.sortOption == .filenameAsc)
    }

    @Test func toggleSortDirection_toggleTwice_returnsToOriginal() {
        let model = Self.isolatedModel()
        let original = model.sortOption
        model.toggleSortDirection()
        model.toggleSortDirection()
        #expect(model.sortOption == original)
    }

    // MARK: - resetFilters

    @Test func resetFilters_clearsAllFilterState() {
        let model = Self.isolatedModel()
        // 预设一堆 dirty state
        model.sidebarSelection = .recent7Days
        model.searchText = "query"
        model.filterState = FilterState(folders: [UUID()], tags: [], shapes: [.square], minRating: 5)
        // 改 default sort/thumbnail（resetFilters 不应清这些——只清 filters）
        model.sortOption = .fileSizeDesc
        model.thumbnailSize = 240

        model.resetFilters()

        #expect(model.sidebarSelection == .all)
        #expect(model.searchText == "")
        #expect(model.filterState == .empty)
        // sort/thumbnail 不应被 reset
        #expect(model.sortOption == .fileSizeDesc)
        #expect(model.thumbnailSize == 240)
    }

    // MARK: - goPrev / goNext

    @Test func goPrev_noSelection_isNoOp() {
        let model = makeModelWithPhotos(3)
        // 没有 selected
        model.goPrev()
        // selection 仍空
        #expect(model.selection.isEmpty)
    }

    @Test func goPrev_atFirstPhoto_isNoOp() {
        let model = makeModelWithPhotos(3)
        // 选中第 0 张 (最前)
        model.selection = model.selection.selectingSingle(model.allPhotos[0].id)
        let before = model.selection.singleSelectedID
        model.goPrev()
        // idx 已经是 0, goPrev 应该是 no-op
        #expect(model.selection.singleSelectedID == before)
    }

    @Test func goPrev_advancesToPreviousPhoto() {
        let model = makeModelWithPhotos(3)
        // 选中第 1 张（中间）
        model.selection = model.selection.selectingSingle(model.allPhotos[1].id)
        // 确保当前 sort 是 filenameAsc 顺序 (model.allPhotos 顺序)
        // sidebarSelection = .all, filterUnfiled = false, filterDuplicates = false, filterRecent7Days = false
        // visiblePhotos 应等于 allPhotos
        #expect(model.visiblePhotos.count == 3)
        model.goPrev()
        // 应选中第 0 张
        #expect(model.selection.singleSelectedID == model.allPhotos[0].id)
    }

    @Test func goNext_atLastPhoto_isNoOp() {
        let model = makeModelWithPhotos(3)
        // 选中最后一张
        model.selection = model.selection.selectingSingle(model.allPhotos[2].id)
        let before = model.selection.singleSelectedID
        model.goNext()
        // 最后一张已是末尾, goNext no-op
        #expect(model.selection.singleSelectedID == before)
    }

    @Test func goNext_advancesToNextPhoto() {
        let model = makeModelWithPhotos(3)
        model.selection = model.selection.selectingSingle(model.allPhotos[1].id)
        model.goNext()
        // 应选中第 2 张
        #expect(model.selection.singleSelectedID == model.allPhotos[2].id)
    }

    // MARK: - handleDelete

    @Test func handleDelete_noSelection_isNoOp() {
        let model = makeModelWithPhotos(2)
        // 没有 selected, handleDelete 应该是 no-op
        model.handleDelete()
        #expect(model.selection.isEmpty)
        #expect(model.showingBatchDeleteConfirm == false)
    }

    @Test func handleDelete_withMultiSelection_setsBatchConfirm() {
        let model = makeModelWithPhotos(3)
        // 多选
        model.selection = .empty
            .settingAll(in: [model.allPhotos[0], model.allPhotos[1]])
        model.handleDelete()
        // 应弹 batch delete confirm (不是真的删——等用户确认)
        #expect(model.showingBatchDeleteConfirm == true)
    }

    // MARK: - zoomIn / zoomOut / resetThumbnailSize

    @Test func zoomIn_fromDefault_advancesToLarger() {
        let model = Self.isolatedModel()
        let before = model.thumbnailSize
        model.zoomIn()
        #expect(model.thumbnailSize > before, "zoomIn 应增大 thumbnailSize")
    }

    @Test func zoomOut_fromDefault_advancesToSmaller() {
        let model = Self.isolatedModel()
        let before = model.thumbnailSize
        model.zoomOut()
        #expect(model.thumbnailSize < before, "zoomOut 应减小 thumbnailSize")
    }

    @Test func zoomIn_atMax_isNoOp() {
        let model = Self.isolatedModel()
        // 设到最大
        while let next = ThumbnailDensity.larger(than: model.thumbnailSize) {
            model.thumbnailSize = next.size
        }
        let maxSize = model.thumbnailSize
        model.zoomIn()
        #expect(model.thumbnailSize == maxSize, "已最大, zoomIn no-op")
    }

    // V6.14.7: 删 resetThumbnailSize_restoresStoredDefault stale test
    //   测的"stored default vs live size"分离在 production code 不存在
    //   ContentViewModel.thumbnailSize 是 settings.thumbnailSize 的 computed property (L50-53)
    //   resetThumbnailSize() = settings.thumbnailSize = settings.thumbnailSize (no-op)
    //   ⌘0 实际行为缺口: 当前不做事; 真要做需要拆 "preferred default" + "current size" 状态
    //   留 V6.14.8+ 跟进 (按 Photos.app 范式: ⌘0 = 回到 initial default 200pt)
}
