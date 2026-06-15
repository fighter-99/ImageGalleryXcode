//
//  UserSettingsTests.swift
//  ImageGalleryTests
//
//  V5.58-2: UserSettings 单元测试
//  覆盖: init() 从 UserDefaults 读, didSet 写回, reset() 恢复 12 字段, scrollAnchorPhotoID 不被 reset
//  全部不需 ModelContainer——纯 UserDefaults 字段验证
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct UserSettingsTests {

    // 测试 setup/teardown——每个 test 前后清 UserDefaults 防污染
    // 用 .userDomainMask + removePersistentDomain 清空标准 suite
    private func clearUserDefaults() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 同时清标准 keys——防遗留
        for key in [
            "viewModeRaw", "showSidebar", "showDetail", "accentColorID",
            "trashRetentionDays", "appearanceMode", "thumbnailSize",
            "sidebarSelection", "sortOption", "thumbnailLayoutMode",
            "sidebarColumnWidth", "detailColumnWidth", "scrollAnchorPhotoID"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - init() 行为

    @Test func init_withEmptyUserDefaults_usesFieldDefaults() {
        clearUserDefaults()
        let settings = UserSettings()
        #expect(settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(settings.showSidebar == true)
        // V5.60-1: showDetail 默认改 true (用户要求"详情面板常驻")
        #expect(settings.showDetail == true)
        #expect(settings.accentColorID == AccentColor.system.rawValue)
        #expect(settings.trashRetentionDays == TrashRetentionDays.defaultValue.rawValue)
        #expect(settings.appearanceMode == AppearanceMode.defaultValue.rawValue)
        #expect(settings.thumbnailSize == 200.0)
        #expect(settings.sidebarSelection == "all")
        #expect(settings.sortOption == SortOption.filenameAsc.rawValue)
        #expect(settings.thumbnailLayoutMode == ThumbnailLayoutMode.defaultValue.rawValue)
        #expect(settings.sidebarColumnWidth == 220.0)
        #expect(settings.detailColumnWidth == 360.0)
        #expect(settings.scrollAnchorPhotoID == nil)
    }

    @Test func init_withPopulatedUserDefaults_readsStoredValues() {
        clearUserDefaults()
        // 提前 set UserDefaults 几个 key——验证 init() 读到了
        let defaults = UserDefaults.standard
        defaults.set(ViewMode.list.rawValue, forKey: "viewModeRaw")
        defaults.set(false, forKey: "showSidebar")
        defaults.set(true, forKey: "showDetail")
        defaults.set(AccentColor.purple.rawValue, forKey: "accentColorID")
        defaults.set(150.0, forKey: "thumbnailSize")
        defaults.set("uuid-12345", forKey: "scrollAnchorPhotoID")

        let settings = UserSettings()
        #expect(settings.viewModeRaw == ViewMode.list.rawValue, "viewModeRaw 应读 UserDefaults")
        #expect(settings.showSidebar == false, "showSidebar 应读 UserDefaults")
        #expect(settings.showDetail == true, "showDetail 应读 UserDefaults")
        #expect(settings.accentColorID == AccentColor.purple.rawValue, "accentColorID 应读 UserDefaults")
        #expect(settings.thumbnailSize == 150.0, "thumbnailSize 应读 UserDefaults")
        #expect(settings.scrollAnchorPhotoID == "uuid-12345", "scrollAnchorPhotoID 应读 UserDefaults")
    }

    @Test func init_withEmptyScrollAnchorString_treatsAsNil() {
        clearUserDefaults()
        // 空字符串应当 nil 处理 (避免脏数据)
        UserDefaults.standard.set("", forKey: "scrollAnchorPhotoID")
        let settings = UserSettings()
        #expect(settings.scrollAnchorPhotoID == nil, "空字符串应被当 nil 处理")
    }

    // MARK: - didSet 写回 UserDefaults

    @Test func setViewModeRaw_writesToUserDefaults() {
        clearUserDefaults()
        let settings = UserSettings()
        settings.viewModeRaw = ViewMode.timeline.rawValue
        #expect(UserDefaults.standard.string(forKey: "viewModeRaw") == ViewMode.timeline.rawValue,
                "改 viewModeRaw 后 didSet 应写回 UserDefaults")
    }

    @Test func setShowSidebar_writesToUserDefaults() {
        clearUserDefaults()
        let settings = UserSettings()
        settings.showSidebar = false
        #expect(UserDefaults.standard.bool(forKey: "showSidebar") == false,
                "改 showSidebar 后 didSet 应写回 UserDefaults")
    }

    // MARK: - reset() 行为

    @Test func reset_restoresAllTwelveFieldsToDefault() {
        clearUserDefaults()
        let settings = UserSettings()

        // 改一堆值 (非默认)
        settings.viewModeRaw = ViewMode.timeline.rawValue
        settings.showSidebar = false
        settings.showDetail = true
        settings.accentColorID = AccentColor.red.rawValue
        settings.trashRetentionDays = 90
        settings.appearanceMode = AppearanceMode.dark.rawValue
        settings.thumbnailSize = 250.0
        settings.sidebarSelection = "folder:xxx"
        settings.sortOption = SortOption.fileSizeDesc.rawValue
        settings.thumbnailLayoutMode = ThumbnailLayoutMode.squareFit.rawValue
        settings.sidebarColumnWidth = 300.0
        settings.detailColumnWidth = 500.0

        settings.reset()

        #expect(settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(settings.showSidebar == true)
        // V5.60-1: reset() 同步 showDetail 回新默认 true
        #expect(settings.showDetail == true)
        #expect(settings.accentColorID == AccentColor.system.rawValue)
        #expect(settings.trashRetentionDays == TrashRetentionDays.defaultValue.rawValue)
        #expect(settings.appearanceMode == AppearanceMode.defaultValue.rawValue)
        #expect(settings.thumbnailSize == 200.0)
        #expect(settings.sidebarSelection == "all")
        #expect(settings.sortOption == SortOption.filenameAsc.rawValue)
        #expect(settings.thumbnailLayoutMode == ThumbnailLayoutMode.defaultValue.rawValue)
        #expect(settings.sidebarColumnWidth == 220.0)
        #expect(settings.detailColumnWidth == 360.0)
    }

    @Test func reset_preservesScrollAnchorPhotoID() {
        clearUserDefaults()
        let settings = UserSettings()
        settings.scrollAnchorPhotoID = "photo-uuid-abc"

        settings.reset()

        #expect(settings.scrollAnchorPhotoID == "photo-uuid-abc",
                "scrollAnchorPhotoID 是 per-window 状态, reset 不应抹掉")
    }

    @Test func reset_writesToUserDefaultsViaDidSet() {
        clearUserDefaults()
        let settings = UserSettings()
        // 改值触发 didSet
        settings.viewModeRaw = ViewMode.timeline.rawValue
        settings.thumbnailSize = 250.0

        settings.reset()

        // 验证 reset() 内部赋值也走 didSet → UserDefaults 同步回滚
        #expect(UserDefaults.standard.string(forKey: "viewModeRaw") == ViewMode.grid.rawValue)
        #expect(UserDefaults.standard.double(forKey: "thumbnailSize") == 200.0)
    }
}
