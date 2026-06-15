//
//  ContentViewModelSmokeTests.swift
//  ImageGalleryTests
//
//  V5.54-1: ContentViewModel 烟雾测试
//  简化版——只测 ContentViewModel init/默认值，不涉及 ModelContainer
//  ModelContainer 相关测试在 V5.54-2+ 加，那时再独立测
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct ContentViewModelSmokeTests {

    @Test func init_hasCorrectDefaultState() {
        let model = ContentViewModel()

        // 22 个 @State 默认值验证
        #expect(model.selection.isEmpty == true)
        #expect(model.sidebarSelection == .all)
        #expect(model.filterState.isActive == false)
        #expect(model.searchText == "")
        #expect(model.thumbnailSize == 200)
        #expect(model.sortOption == .filenameAsc)
        #expect(model.showingBatchDeleteConfirm == false)
        #expect(model.showingEmptyTrashConfirm == false)
        #expect(model.importDuplicateCheck == nil)
        #expect(model.pendingImportURLs.isEmpty == true)
        #expect(model.showingNewFolderAlert == false)
        #expect(model.newFolderName == "")
        #expect(model.immersivePhoto == nil)
        #expect(model.immersiveIndex == 0)
        #expect(model.storageErrorMessage == nil)
        #expect(model.titlebarAccessory == nil)
        #expect(model.toastQueue.isEmpty == true)
        #expect(model.toastTask == nil)
        #expect(model.importProgress == nil)
        #expect(model.sidebarColumnWidth == 220)
        #expect(model.detailColumnWidth == 360)
    }

    @Test func init_settingsHaveCorrectDefaults() {
        let model = ContentViewModel()
        #expect(model.settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(model.settings.showSidebar == true)
        #expect(model.settings.showDetail == false)
        #expect(model.settings.accentColorID == AccentColor.system.rawValue)
        #expect(model.settings.trashRetentionDays == TrashRetentionDays.defaultValue.rawValue)
        #expect(model.settings.appearanceMode == AppearanceMode.defaultValue.rawValue)
        #expect(model.settings.thumbnailSize == 200)
        #expect(model.settings.sidebarSelection == "all")
        #expect(model.settings.sortOption == SortOption.filenameAsc.rawValue)
        #expect(model.settings.thumbnailLayoutMode == ThumbnailLayoutMode.defaultValue.rawValue)
        #expect(model.settings.sidebarColumnWidth == 220)
        #expect(model.settings.detailColumnWidth == 360)
    }

    @Test func init_modelContextIsNil() {
        let model = ContentViewModel()
        #expect(model.modelContext == nil, "init 后 modelContext 应是 nil——由 .task 注入")
    }

    @Test func init_allPhotosAndFoldersAndAllTagsEmpty() {
        let model = ContentViewModel()
        #expect(model.allPhotos.isEmpty)
        #expect(model.folders.isEmpty)
        #expect(model.allTags.isEmpty)
    }
}
