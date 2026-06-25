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

// V6.19.6: 加 @Suite(.serialized) — 避免 parallel test 共享 isolatedDefaults 状态
//   defaultImportLocation_initFromUserDefaults 写入值后, parallel 跑的
//   defaultImportLocation_defaultsToNil 可能读到上次的值导致 fail
//   ContentViewModel*Tests 同款 pattern (memory: swift-testing-userdefaults-parallel-crash)
@MainActor
@Suite(.serialized)
struct UserSettingsTests {

    // V6.14.7: 改 isolatedDefaults pattern (跟 ContentViewModel*Tests 同源)
    //   之前用 UserDefaults.standard + clearUserDefaults helper, 并行 test 互相污染
    //   跟 ImageLoaderTests 的 ThumbnailCache.shared 撞车 — singleton 状态共享
    //   改 static let isolatedDefaults: UserDefaults = FakeUserDefaults()
    //   每 test 显式传 UserSettings(defaults: isolatedDefaults)
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
    private static func isolatedSettings() -> UserSettings {
        for key in userSettingsKeys {
            isolatedDefaults.removeObject(forKey: key)
        }
        return UserSettings(defaults: isolatedDefaults)
    }

    // MARK: - init() 行为

    @Test func init_withEmptyUserDefaults_usesFieldDefaults() {
        let settings = Self.isolatedSettings()
        #expect(settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(settings.showSidebar == true)
        // V6.112: showDetail 默认改 false (用户要求"主页面默认不显示详情面板")
        //   走 immersive 时用 ⓘ drawer (V6.111) 查看详情
        #expect(settings.showDetail == false)
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
        // 提前 set isolatedDefaults 几个 key——验证 init() 读到了
        let defaults = Self.isolatedDefaults
        defaults.set(ViewMode.list.rawValue, forKey: "viewModeRaw")
        defaults.set(false, forKey: "showSidebar")
        defaults.set(true, forKey: "showDetail")
        defaults.set(AccentColor.purple.rawValue, forKey: "accentColorID")
        defaults.set(150.0, forKey: "thumbnailSize")
        defaults.set("uuid-12345", forKey: "scrollAnchorPhotoID")

        let settings = UserSettings(defaults: defaults)
        #expect(settings.viewModeRaw == ViewMode.list.rawValue, "viewModeRaw 应读 UserDefaults")
        #expect(settings.showSidebar == false, "showSidebar 应读 UserDefaults")
        #expect(settings.showDetail == true, "showDetail 应读 UserDefaults")
        #expect(settings.accentColorID == AccentColor.purple.rawValue, "accentColorID 应读 UserDefaults")
        #expect(settings.thumbnailSize == 150.0, "thumbnailSize 应读 UserDefaults")
        #expect(settings.scrollAnchorPhotoID == "uuid-12345", "scrollAnchorPhotoID 应读 UserDefaults")
    }

    @Test func init_withEmptyScrollAnchorString_treatsAsNil() {
        // 空字符串应当 nil 处理 (避免脏数据)
        Self.isolatedDefaults.set("", forKey: "scrollAnchorPhotoID")
        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.scrollAnchorPhotoID == nil, "空字符串应被当 nil 处理")
    }

    // MARK: - didSet 写回 UserDefaults

    @Test func setViewModeRaw_writesToUserDefaults() {
        let settings = Self.isolatedSettings()
        settings.viewModeRaw = ViewMode.timeline.rawValue
        #expect(Self.isolatedDefaults.string(forKey: "viewModeRaw") == ViewMode.timeline.rawValue,
                "改 viewModeRaw 后 didSet 应写回 UserDefaults")
    }

    @Test func setShowSidebar_writesToUserDefaults() {
        let settings = Self.isolatedSettings()
        settings.showSidebar = false
        #expect(Self.isolatedDefaults.bool(forKey: "showSidebar") == false,
                "改 showSidebar 后 didSet 应写回 UserDefaults")
    }

    // MARK: - reset() 行为

    @Test func reset_restoresAllTwelveFieldsToDefault() {
        let settings = Self.isolatedSettings()

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
        // V6.112: reset() 同步 showDetail 回新默认 false (跟 init 一致)
        #expect(settings.showDetail == false)
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
        let settings = Self.isolatedSettings()
        settings.scrollAnchorPhotoID = "photo-uuid-abc"

        settings.reset()

        #expect(settings.scrollAnchorPhotoID == "photo-uuid-abc",
                "scrollAnchorPhotoID 是 per-window 状态, reset 不应抹掉")
    }

    @Test func reset_writesToUserDefaultsViaDidSet() {
        let settings = Self.isolatedSettings()
        // 改值触发 didSet
        settings.viewModeRaw = ViewMode.timeline.rawValue
        settings.thumbnailSize = 250.0

        settings.reset()

        // 验证 reset() 内部赋值也走 didSet → UserDefaults 同步回滚
        #expect(Self.isolatedDefaults.string(forKey: "viewModeRaw") == ViewMode.grid.rawValue)
        #expect(Self.isolatedDefaults.double(forKey: "thumbnailSize") == 200.0)
    }

    // MARK: - V6.39.0: 新字段 + DoubleClickAction

    @Test func defaultImportLocation_defaultsToNil() {
        let settings = Self.isolatedSettings()
        #expect(settings.defaultImportLocation == nil)
    }

    @Test func defaultImportLocation_writesToUserDefaults() {
        let settings = Self.isolatedSettings()
        settings.defaultImportLocation = "file:///tmp/photos"
        #expect(settings.defaultImportLocation == "file:///tmp/photos")
        #expect(Self.isolatedDefaults.string(forKey: "defaultImportLocation") == "file:///tmp/photos")
    }

    @Test func defaultImportLocation_initFromUserDefaults() {
        Self.isolatedDefaults.set("file:///Users/x/Photos", forKey: "defaultImportLocation")
        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.defaultImportLocation == "file:///Users/x/Photos")
    }

    @Test func doubleClickAction_defaultsToImmersive() {
        let settings = Self.isolatedSettings()
        #expect(settings.appDoubleClickAction == .immersive)
        #expect(settings.doubleClickAction == DoubleClickAction.immersive.rawValue)
    }

    @Test func doubleClickAction_canBeSetToQuickLook() {
        let settings = Self.isolatedSettings()
        settings.appDoubleClickAction = .quickLook
        #expect(settings.appDoubleClickAction == .quickLook)
        #expect(Self.isolatedDefaults.string(forKey: "doubleClickAction") == "quickLook")
    }

    @Test func doubleClickAction_initFromUserDefaults() {
        Self.isolatedDefaults.set("quickLook", forKey: "doubleClickAction")
        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.appDoubleClickAction == .quickLook)
    }

    @Test func doubleClickAction_invalidRawValueFallsBackToDefault() {
        Self.isolatedDefaults.set("nonexistent", forKey: "doubleClickAction")
        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.appDoubleClickAction == DoubleClickAction.defaultValue)
    }

    @Test func appViewMode_typedWrapperRoundtripsThroughRawValue() {
        let settings = Self.isolatedSettings()
        settings.appViewMode = .timeline
        #expect(settings.viewModeRaw == ViewMode.timeline.rawValue)
        #expect(settings.appViewMode == .timeline)
        settings.appViewMode = .list
        #expect(settings.viewModeRaw == ViewMode.list.rawValue)
    }

    @Test func reset_clearsNewFields() {
        let settings = Self.isolatedSettings()
        settings.defaultImportLocation = "file:///tmp/x"
        settings.appDoubleClickAction = .quickLook
        settings.appFontScale = .large
        settings.reset()
        #expect(settings.defaultImportLocation == nil)
        #expect(settings.appDoubleClickAction == DoubleClickAction.defaultValue)
        #expect(settings.appFontScale == .defaultValue)
        // V6.39.0: scrollAnchorPhotoID 不在 reset 范围 (跟之前一致)
        settings.scrollAnchorPhotoID = "abc-123"
        settings.reset()
        #expect(settings.scrollAnchorPhotoID == "abc-123")
    }

    // V6.58 (audit P1.1): fontScale UserDefaults 重启后保留
    //   之前 V6.33.1 加的字段漏了 init reader — didSet 写得起作用但重启读不回来
    @Test func fontScale_persistsAcrossInit() {
        // 隔离 UserDefaults (跟其他 test 用同一个 isolatedDefaults, 但用 removeObject 防止污染)
        Self.isolatedDefaults.removeObject(forKey: "fontScale")
        Self.isolatedDefaults.set("large", forKey: "fontScale")

        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.appFontScale == .large, "V6.58: fontScale 应从 UserDefaults 读回")
    }
}
