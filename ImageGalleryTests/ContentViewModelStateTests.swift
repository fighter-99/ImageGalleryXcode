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

@MainActor
struct ContentViewModelStateTests {

    // MARK: - @State 字段 mutation

    @Test func selection_canBeReplaced() {
        let model = ContentViewModel()
        let id = UUID()
        model.selection = model.selection.selectingSingle(id)
        #expect(model.selection.singleSelectedID == id)
        model.selection = .empty
        #expect(model.selection.isEmpty)
    }

    @Test func sidebarSelection_canBeSetToFolder() throws {
        // V6.08: currentFolder 改 UUID fetch——需要 ModelContainer 才有 context
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = ContentViewModel()
        model.modelContext = container.mainContext
        let folder = Folder(name: "Vacation")
        container.mainContext.insert(folder)
        try container.mainContext.save()
        // V6.08: SidebarSelection 改 UUID——.folder(folder.id) 替 .folder(folder)
        model.sidebarSelection = .folder(folder.id)
        #expect(model.sidebarSelection == .folder(folder.id))
        #expect(model.currentFolder?.id == folder.id)
    }

    @Test func filterState_canBeReplacedWithEmpty() {
        let model = ContentViewModel()
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
        let model = ContentViewModel()
        model.searchText = "beach"
        #expect(model.searchText == "beach")
        #expect(model.trimmedSearch == "beach")
    }

    @Test func searchText_withSurroundingSpaces_trimmedCleanly() {
        let model = ContentViewModel()
        model.searchText = "  beach  "
        #expect(model.trimmedSearch == "beach")
    }

    @Test func thumbnailSize_canBeAdjusted() {
        let model = ContentViewModel()
        model.thumbnailSize = 110
        #expect(model.thumbnailSize == 110)
        model.thumbnailSize = 240
        #expect(model.thumbnailSize == 240)
    }

    @Test func sortOption_canBeSet() {
        let model = ContentViewModel()
        model.sortOption = .fileSizeDesc
        #expect(model.sortOption == .fileSizeDesc)
        model.sortOption = .importedAtAsc
        #expect(model.sortOption == .importedAtAsc)
    }

    @Test func showingBatchDeleteConfirm_canBeToggled() {
        let model = ContentViewModel()
        #expect(model.showingBatchDeleteConfirm == false)
        model.showingBatchDeleteConfirm = true
        #expect(model.showingBatchDeleteConfirm == true)
    }

    @Test func newFolderName_canBeSet() {
        let model = ContentViewModel()
        model.newFolderName = "Vacation 2024"
        #expect(model.newFolderName == "Vacation 2024")
    }

    @Test func toastQueue_canAppend() {
        let model = ContentViewModel()
        let info = ToastInfo(message: "test", type: .info, duration: .normal)
        model.toastQueue.append(info)
        #expect(model.toastQueue.count == 1)
        #expect(model.toastQueue.first?.message == "test")
    }

    @Test func importProgress_canBeSet() {
        let model = ContentViewModel()
        let progress = ImportProgress(current: 5, total: 10, isImporting: true)
        model.importProgress = progress
        #expect(model.importProgress?.current == 5)
        #expect(model.importProgress?.total == 10)
    }

    @Test func immersivePhoto_canBeSet() {
        let model = ContentViewModel()
        let photo = Photo(
            filename: "i.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/V554_immersive.jpg"),
            fileSize: 100, width: 10, height: 10
        )
        model.immersivePhoto = photo
        model.immersiveIndex = 3
        #expect(model.immersivePhoto?.id == photo.id)
        #expect(model.immersiveIndex == 3)
    }

    // MARK: - Computed properties (不需要 mutation)

    @Test func viewMode_defaultIsGrid() {
        // V6.12 收尾: 清 UserDefaults viewModeRaw——测试间不隔离会污染上次 .list/.timeline
        //   ContentViewModel.init 走 UserSettings.init() 从 UserDefaults 读, 上次测试写
        //   "list" 后本次 init() 拿到 "list", 默认断言 .grid 失败
        UserDefaults.standard.removeObject(forKey: "viewModeRaw")
        let model = ContentViewModel()
        #expect(model.viewMode == .grid)
    }

    @Test func viewMode_setterWritesSettingsRaw() {
        let model = ContentViewModel()
        model.viewMode = .list
        #expect(model.settings.viewModeRaw == ViewMode.list.rawValue)
        #expect(model.viewMode == .list)
    }

    @Test func layoutMode_defaultIsSquare() {
        let model = ContentViewModel()
        #expect(model.layoutMode == .defaultValue)
    }

    @Test func appearanceMode_defaultIsSystem() {
        let model = ContentViewModel()
        #expect(model.appearanceMode == .system)
    }

    @Test func accentColor_defaultIsSystem() {
        let model = ContentViewModel()
        #expect(model.accentColor == .system)
    }

    @Test func currentViewTitle_forAllSidebar() {
        let model = ContentViewModel()
        model.sidebarSelection = .all
        #expect(model.currentViewTitle == "全部照片")
    }

    @Test func currentViewTitle_forTrashUsesRecycleBin() {
        let model = ContentViewModel()
        model.sidebarSelection = .recentlyDeleted
        #expect(model.currentViewTitle == Term.recycleBin)
    }

    @Test func currentViewSubtitle_empty_returnsZeroPhotos() {
        let model = ContentViewModel()
        #expect(model.currentViewSubtitle.contains("0 张"))
    }

    @Test func filterUnfiled_onlyTrue_whenSidebarIsUnfiled() {
        let model = ContentViewModel()
        model.sidebarSelection = .unfiled
        #expect(model.filterUnfiled == true)
        model.sidebarSelection = .all
        #expect(model.filterUnfiled == false)
    }

    @Test func filterDuplicates_onlyTrue_whenSidebarIsDuplicates() {
        let model = ContentViewModel()
        model.sidebarSelection = .duplicates
        #expect(model.filterDuplicates == true)
        model.sidebarSelection = .all
        #expect(model.filterDuplicates == false)
    }

    @Test func filterInTrash_onlyTrue_whenSidebarIsTrash() {
        let model = ContentViewModel()
        model.sidebarSelection = .recentlyDeleted
        #expect(model.filterInTrash == true)
        model.sidebarSelection = .all
        #expect(model.filterInTrash == false)
    }

    @Test func sidebarSelection_affectsCurrentFolder() throws {
        // V6.08: currentFolder 改 UUID fetch——需要 ModelContainer 才有 context
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = ContentViewModel()
        model.modelContext = container.mainContext
        let folder = Folder(name: "Beach")
        container.mainContext.insert(folder)
        try container.mainContext.save()
        // V6.08: SidebarSelection 改 UUID——.folder(folder.id) 替 .folder(folder)
        model.sidebarSelection = .folder(folder.id)
        #expect(model.currentFolder?.id == folder.id)
        model.sidebarSelection = .all
        #expect(model.currentFolder == nil)
    }

    @Test func sidebarSelection_affectsCurrentTag() throws {
        // V6.08: currentTag 改 UUID fetch——需要 ModelContainer 才有 context
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let model = ContentViewModel()
        model.modelContext = container.mainContext
        let tag = Tag(name: "favorite")
        container.mainContext.insert(tag)
        try container.mainContext.save()
        // V6.08: SidebarSelection 改 UUID——.tag(tag.id) 替 .tag(tag)
        model.sidebarSelection = .tag(tag.id)
        #expect(model.currentTag?.id == tag.id)
        model.sidebarSelection = .all
        #expect(model.currentTag == nil)
    }

    @Test func canPrev_canNext_initiallyFalse() {
        let model = ContentViewModel()
        #expect(model.canPrev == false)
        #expect(model.canNext == false)
    }

    @Test func isMultiSelect_initiallyFalse() {
        let model = ContentViewModel()
        #expect(model.isMultiSelect == false)
    }

    @Test func totalSizeFormatted_withEmptyAllPhotos_returnsZeroBytes() {
        let model = ContentViewModel()
        // ByteCountFormatter .file: 0 bytes → "Zero KB"
        #expect(model.totalSizeFormatted == "Zero KB")
    }

    @Test func sidebarColumnWidth_canBeAdjusted() {
        let model = ContentViewModel()
        model.sidebarColumnWidth = 300
        #expect(model.sidebarColumnWidth == 300)
    }

    @Test func detailColumnWidth_canBeAdjusted() {
        let model = ContentViewModel()
        model.detailColumnWidth = 420
        #expect(model.detailColumnWidth == 420)
    }

    @Test func batchDeleteTitle_zeroSelected_returnsDefault() {
        let model = ContentViewModel()
        #expect(model.batchDeleteTitle == Copy.deleteConfirmTitle)
    }
}
