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
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return ContentViewModel(settings: UserSettings(defaults: isolatedDefaults))
    }

    @Test func init_hasCorrectDefaultState() {
        // V6.12.20: 用 isolatedModel (共享 suite + cleanup)——避开 UserDefaults.standard 跨 test 污染
        let model = Self.isolatedModel()

        // 22 个 @State 默认值验证
        #expect(model.grid.selection.isEmpty == true)
        #expect(model.sidebarSelection == nil)  // V5.59-2: default = nil (从 settings 反序列化, init 时 nil)
        #expect(model.filterState.isActive == false)
        #expect(model.grid.searchText == "")
        #expect(model.grid.thumbnailSize == 200)
        #expect(model.grid.sortOption == .filenameAsc)
        #expect(model.grid.showingBatchDeleteConfirm == false)
        #expect(model.grid.showingEmptyTrashConfirm == false)
        #expect(model.importVM.importDuplicateCheck == nil)
        #expect(model.importVM.pendingImportURLs.isEmpty == true)
        #expect(model.grid.showingNewFolderAlert == false)
        #expect(model.grid.newFolderName == "")
        #expect(model.grid.immersivePhoto == nil)
        #expect(model.grid.immersiveIndex == 0)
        #expect(model.storageErrorMessage == nil)
        // V6.74.2: 删 model.windowVM.titlebarAccessory 检查 — TitlebarAccessoryController 整文件删
        //   ⓘ 按钮改走 SwiftUI .toolbar .primaryAction (V6.74.1), 无 NSObject 引用
        #expect(model.toastQueue.isEmpty == true)
        #expect(model.toastTask == nil)
        #expect(model.importVM.importProgress == nil)
        #expect(model.sidebarColumnWidth == 220)
        // V6.113: 删 model.detailColumnWidth 检查 — 字段已删
    }

    @Test func init_settingsHaveCorrectDefaults() {
        // V6.12.20: 用 isolatedModel (共享 suite + cleanup)——避开 UserDefaults.standard 跨 test 污染
        let model = Self.isolatedModel()
        #expect(model.settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(model.settings.showSidebar == true)
        // V6.113: 删 showDetail 检查 — 字段已删
        #expect(model.settings.accentColorID == AccentColor.system.rawValue)
        #expect(model.settings.trashRetentionDays == TrashRetentionDays.defaultValue.rawValue)
        #expect(model.settings.appearanceMode == AppearanceMode.defaultValue.rawValue)
        #expect(model.settings.thumbnailSize == 200)
        #expect(model.settings.sidebarSelection == "all")
        #expect(model.settings.sortOption == SortOption.filenameAsc.rawValue)
        #expect(model.settings.thumbnailLayoutMode == ThumbnailLayoutMode.defaultValue.rawValue)
        #expect(model.settings.sidebarColumnWidth == 220)
        // V6.113: 删 detailColumnWidth 检查 — 字段已删
    }

    @Test func init_modelContextIsNil() {
        let model = Self.isolatedModel()
        #expect(model.modelContext == nil, "init 后 modelContext 应是 nil——由 .task 注入")
    }

    @Test func init_allPhotosAndFoldersAndAllTagsEmpty() {
        let model = Self.isolatedModel()
        #expect(model.grid.allPhotos.isEmpty)
        #expect(model.grid.folders.isEmpty)
        #expect(model.grid.allTags.isEmpty)
    }
}
