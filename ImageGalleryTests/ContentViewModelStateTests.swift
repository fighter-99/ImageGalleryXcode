//
//  ContentViewModelStateTests.swift
//  ImageGalleryTests
//
//  V5.54-6: ContentViewModel 状态 + computed property tests
//  测 22 @State 字段转换 + 30+ computed property derivation
//  不需 ModelContainer——纯内存字段验证
//

import Testing
import Foundation
import SwiftData  // V6.12 收尾: sidebarSelection_canBeSetToFolder / affectsCurrentFolder / affectsCurrentTag 3 test 加 ModelContainer fetch——currentFolder/currentTag V6.08 改 UUID 后需要 context
@testable import ImageGallery

// V6.19.6 (P0 #18): 加 @Suite(.serialized) — 强制串行, 避免 ModelContainer 与其他 suite 并行创建冲突
@MainActor
@Suite(.serialized)
struct ContentViewModelStateTests {

    // V6.12.20: 共享 suite + cleanup pattern——避免每次 UUID 创建新 suite 给 cfprefsd 压力
    //   之前用 UUID 每次新 suite: cfprefsd 守护进程被大量临时 suite 注册拖累, Swift Testing
    //   并行下偶尔触发 signal trap 污染整个 process (memory: swift-testing-userdefaults-parallel-crash)
    //   改共享 1 个 suite, 每个 test 跑前清 key——suite 注册压力降到 1
    //   @MainActor 强制 + suite static let 一次性 init 避开 race
    @MainActor
    private static let isolatedDefaults: UserDefaults = FakeUserDefaults()
    /// UserSettings 读过的所有 key——任何被读过的 key 都得清, 防漏
    private static let userSettingsKeys: [String] = [
        "viewModeRaw", "showSidebar", "showDetail", "accentColorID",
        "trashRetentionDays", "appearanceMode", "thumbnailSize",
        "sidebarSelection", "sortOption", "thumbnailLayoutMode",
        "sidebarColumnWidth", "detailColumnWidth", "autoDeduplicate",
        "autoGenerateThumbnails", "defaultExportFormat",
        "defaultExportQuality", "scrollAnchorPhotoID"
    ]
    private static func isolatedModel() -> ContentViewModel {
        // Cleanup: 删所有 UserSettings 读过的 key, 强制走 field default
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }

    // MARK: - @State 字段 mutation

    @Test func selection_canBeReplaced() {
        let model = Self.isolatedModel()
        let id = UUID()
        model.grid.selection = model.grid.selection.selectingSingle(id)
        #expect(model.grid.selection.singleSelectedID == id)
        model.grid.selection = .empty
        #expect(model.grid.selection.isEmpty)
    }

    @Test func sidebarSelection_canBeSetToFolder() throws {
        // V6.08: currentFolder 改 UUID fetch——需要 ModelContainer 才有 context
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let folder = Folder(name: "Vacation")
        container.mainContext.insert(folder)
        try container.mainContext.save()
        // V6.08: SidebarSelection 改 UUID——.folder(folder.id) 替 .folder(folder)
        model.sidebarSelection = .folder(folder.id)
        #expect(model.sidebarSelection == .folder(folder.id))
        #expect(model.grid.currentFolder?.id == folder.id)
    }

    @Test func filterState_canBeReplacedWithEmpty() {
        let model = Self.isolatedModel()
        // 4 维 dirty: 1 folder + 0 tag + 1 shape + rating>0
        // activeCount = 1 + 0 + 1 + 1 = 3 (per FilterState.activeCount 公式)
        let dirty = FilterState(folders: [UUID()], tags: [], shapes: [.square], minRating: 5)
        model.filterState = dirty
        #expect(model.filterState.activeCount == 3, "activeCount = folders.count + tags.count + shapes.count + (minRating>0 ? 1 : 0)")
        model.filterState = .empty
        #expect(model.filterState.activeCount == 0)
        #expect(model.filterState.isActive == false)
    }

    @Test func searchText_canBeSet() {
        let model = Self.isolatedModel()
        model.grid.searchText = "beach"
        #expect(model.grid.searchText == "beach")
        #expect(model.grid.trimmedSearch == "beach")
    }

    @Test func searchText_withSurroundingSpaces_trimmedCleanly() {
        let model = Self.isolatedModel()
        model.grid.searchText = "  beach  "
        #expect(model.grid.trimmedSearch == "beach")
    }

    @Test func thumbnailSize_canBeAdjusted() {
        let model = Self.isolatedModel()
        model.grid.thumbnailSize = 110
        #expect(model.grid.thumbnailSize == 110)
        model.grid.thumbnailSize = 240
        #expect(model.grid.thumbnailSize == 240)
    }

    @Test func sortOption_canBeSet() {
        let model = Self.isolatedModel()
        model.grid.sortOption = .fileSizeDesc
        #expect(model.grid.sortOption == .fileSizeDesc)
        model.grid.sortOption = .importedAtAsc
        #expect(model.grid.sortOption == .importedAtAsc)
    }

    @Test func showingBatchDeleteConfirm_canBeToggled() {
        let model = Self.isolatedModel()
        #expect(model.grid.showingBatchDeleteConfirm == false)
        model.grid.showingBatchDeleteConfirm = true
        #expect(model.grid.showingBatchDeleteConfirm == true)
    }

    @Test func newFolderName_canBeSet() {
        let model = Self.isolatedModel()
        model.grid.newFolderName = "Vacation 2024"
        #expect(model.grid.newFolderName == "Vacation 2024")
    }

    @Test func toastQueue_canAppend() {
        let model = Self.isolatedModel()
        let info = ToastInfo(message: "test", type: .info, duration: .normal)
        model.toastQueue.append(info)
        #expect(model.toastQueue.count == 1)
        #expect(model.toastQueue.first?.message == "test")
    }

    @Test func importProgress_canBeSet() {
        let model = Self.isolatedModel()
        let progress = ImportProgress(current: 5, total: 10, isImporting: true)
        model.importProgress = progress
        #expect(model.importProgress?.current == 5)
        #expect(model.importProgress?.total == 10)
    }

    @Test func immersivePhoto_canBeSet() {
        let model = Self.isolatedModel()
        let photo = Photo(
            filename: "i.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/V554_immersive.jpg"),
            fileSize: 100, width: 10, height: 10
        )
        model.grid.immersivePhoto = photo
        model.grid.immersiveIndex = 3
        #expect(model.grid.immersivePhoto?.id == photo.id)
        #expect(model.grid.immersiveIndex == 3)
    }

    // MARK: - Computed properties (不需要 mutation)

    @Test func viewMode_defaultIsGrid() {
        let model = Self.isolatedModel()
        #expect(model.viewMode == .grid)
    }

    @Test func viewMode_setterWritesSettingsRaw() {
        let model = Self.isolatedModel()
        model.viewMode = .list
        #expect(model.settings.viewModeRaw == ViewMode.list.rawValue)
        #expect(model.viewMode == .list)
    }

    @Test func layoutMode_defaultIsSquareFit() {
        // V6.12.12: 砍 .square 后 defaultValue = .squareFit
        let model = Self.isolatedModel()
        #expect(model.layoutMode == .defaultValue)
    }

    @Test func appearanceMode_defaultIsSystem() {
        let model = Self.isolatedModel()
        #expect(model.appearanceMode == .system)
    }

    @Test func accentColor_defaultIsSystem() {
        let model = Self.isolatedModel()
        #expect(model.accentColor == .system)
    }

    @Test func currentViewTitle_forAllSidebar() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .all
        #expect(model.grid.currentViewTitle == "全部照片")
    }

    @Test func currentViewTitle_forTrashUsesRecycleBin() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .recentlyDeleted
        #expect(model.grid.currentViewTitle == Term.recycleBin)
    }

    @Test func currentViewSubtitle_empty_returnsZeroPhotos() {
        let model = Self.isolatedModel()
        #expect(model.grid.currentViewSubtitle.contains("0 张"))
    }

    @Test func filterUnfiled_onlyTrue_whenSidebarIsUnfiled() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .unfiled
        #expect(model.grid.filterUnfiled == true)
        model.sidebarSelection = .all
        #expect(model.grid.filterUnfiled == false)
    }

    @Test func filterDuplicates_onlyTrue_whenSidebarIsDuplicates() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .duplicates
        #expect(model.grid.filterDuplicates == true)
        model.sidebarSelection = .all
        #expect(model.grid.filterDuplicates == false)
    }

    @Test func filterInTrash_onlyTrue_whenSidebarIsTrash() {
        let model = Self.isolatedModel()
        model.sidebarSelection = .recentlyDeleted
        #expect(model.grid.filterInTrash == true)
        model.sidebarSelection = .all
        #expect(model.grid.filterInTrash == false)
    }

    @Test func sidebarSelection_affectsCurrentFolder() throws {
        // V6.08: currentFolder 改 UUID fetch——需要 ModelContainer 才有 context
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let folder = Folder(name: "Beach")
        container.mainContext.insert(folder)
        try container.mainContext.save()
        // V6.08: SidebarSelection 改 UUID——.folder(folder.id) 替 .folder(folder)
        model.sidebarSelection = .folder(folder.id)
        #expect(model.grid.currentFolder?.id == folder.id)
        model.sidebarSelection = .all
        #expect(model.grid.currentFolder == nil)
    }

    @Test func sidebarSelection_affectsCurrentTag() throws {
        // V6.08: currentTag 改 UUID fetch——需要 ModelContainer 才有 context
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = Self.isolatedModel()
        model.modelContext = container.mainContext
        let tag = Tag(name: "favorite")
        container.mainContext.insert(tag)
        try container.mainContext.save()
        // V6.08: SidebarSelection 改 UUID——.tag(tag.id) 替 .tag(tag)
        model.sidebarSelection = .tag(tag.id)
        #expect(model.grid.currentTag?.id == tag.id)
        model.sidebarSelection = .all
        #expect(model.grid.currentTag == nil)
    }

    @Test func canPrev_canNext_initiallyFalse() {
        let model = Self.isolatedModel()
        #expect(model.grid.canPrev == false)
        #expect(model.grid.canNext == false)
    }

    @Test func isMultiSelect_initiallyFalse() {
        let model = Self.isolatedModel()
        #expect(model.grid.isMultiSelect == false)
    }

    @Test func totalSizeFormatted_withEmptyAllPhotos_returnsZeroBytes() {
        let model = Self.isolatedModel()
        // V6.13.1: 之前 hardcode "Zero KB" 在 zh-Hans locale 下 stale
        //   ByteCountFormatter 按 locale 选词: en "Zero KB" / zh-Hans "0 KB"
        //   改用 ByteCountFormatter 自己算期望值, locale-agnostic
        let expected = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
        #expect(model.grid.totalSizeFormatted == expected)
    }

    @Test func sidebarColumnWidth_canBeAdjusted() {
        let model = Self.isolatedModel()
        model.sidebarColumnWidth = 300
        #expect(model.sidebarColumnWidth == 300)
    }

    @Test func detailColumnWidth_canBeAdjusted() {
        let model = Self.isolatedModel()
        model.detailColumnWidth = 420
        #expect(model.detailColumnWidth == 420)
    }

    @Test func batchDeleteTitle_zeroSelected_returnsDefault() {
        let model = Self.isolatedModel()
        #expect(model.grid.batchDeleteTitle == Copy.deleteConfirmTitle)
    }
}
