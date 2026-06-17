//
//  ContentViewModelSmokeTests.swift
//  ImageGalleryTests
//
//  V5.54-1: ContentViewModel 烟雾测试
//  简化版——只测 ContentViewModel init/默认值，不涉及 ModelContainer
//  ModelContainer 相关测试在 V5.54-2+ 加，那时再独立测
//
//  V6.12.20: 加 isolatedDefaults / isolatedModel helper (跟 ContentViewModelStateTests 同源 pattern)
//  避开 UserDefaults.standard 跨 test 污染
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct ContentViewModelSmokeTests {

    // V6.12.20: 共享 suite + cleanup pattern (跟 ContentViewModelStateTests.isolatedModel 同源)
    @MainActor
    private static let isolatedDefaults: UserDefaults = UserDefaults(suiteName: "ImageGalleryTests_Smoke")!
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

    @Test func init_hasCorrectDefaultState() {
        // V6.12.20: 用 isolatedModel (共享 suite + cleanup)——避开 UserDefaults.standard 跨 test 污染
        let model = Self.isolatedModel()

        // 22 个 @State 默认值验证
        #expect(model.selection.isEmpty == true)
        #expect(model.sidebarSelection == nil)  // V5.59-2: default = nil (从 settings 反序列化, init 时 nil)
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
        // V6.12.20: 用 isolatedModel (共享 suite + cleanup)——避开 UserDefaults.standard 跨 test 污染
        let model = Self.isolatedModel()
        #expect(model.settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(model.settings.showSidebar == true)
        #expect(model.settings.showDetail == true)  // V5.60-1: 改回 true (用户要求"详情面板常驻")
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
        let model = Self.isolatedModel()
        #expect(model.modelContext == nil, "init 后 modelContext 应是 nil——由 .task 注入")
    }

    @Test func init_allPhotosAndFoldersAndAllTagsEmpty() {
        let model = Self.isolatedModel()
        #expect(model.allPhotos.isEmpty)
        #expect(model.folders.isEmpty)
        #expect(model.allTags.isEmpty)
    }
}
