//
//  ContentViewModelInitTests.swift
//  ImageGalleryTests
//
//  V5.59-3: ContentViewModel(settings:) 构造测试
//  覆盖:
//    - 默认无参 init 走 fallback UserSettings() (不抛错, 现有测试用)
//    - 接受外部 settings, 共享同一引用 (ImageGalleryApp.sharedSettings 模式)
//    - sharedSettings 改值, model.settings 同步 (单一真相源验证)
//  全部不需 ModelContainer——纯引用相等 + 属性访问
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct ContentViewModelInitTests {

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

    // 测试 setup/teardown——隔离 UserDefaults 防污染其他 test
    private func clearUserDefaults() {
        for key in [
            "viewModeRaw", "showSidebar", "showDetail", "accentColorID",
            "trashRetentionDays", "appearanceMode", "thumbnailSize",
            "sidebarSelection", "sortOption", "thumbnailLayoutMode",
            "sidebarColumnWidth", "detailColumnWidth", "scrollAnchorPhotoID"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - init(settings:)

    @Test func init_withDefaultArg_createsNewUserSettings() {
        clearUserDefaults()
        let model = Self.isolatedModel()  // 无参 → fallback UserSettings()
        // 不是 nil 也不是 default arg——是新 UserSettings 实例
        #expect(model.settings.viewModeRaw == ViewMode.grid.rawValue)
        #expect(model.settings.thumbnailSize == 200.0)
        #expect(model.settings.scrollAnchorPhotoID == nil)
    }

    @Test func init_withProvidedSettings_storesSameInstance() {
        clearUserDefaults()
        let sharedSettings = UserSettings()
        sharedSettings.viewModeRaw = ViewMode.list.rawValue
        sharedSettings.thumbnailSize = 150.0

        let model = ContentViewModel(settings: sharedSettings)

        // model.settings 引用 === sharedSettings (同实例, 非拷贝)
        #expect(model.settings.viewModeRaw == ViewMode.list.rawValue,
                "model.settings 应读 sharedSettings 写入的 viewModeRaw")
        #expect(model.settings.thumbnailSize == 150.0,
                "model.settings 应读 sharedSettings 写入的 thumbnailSize")
    }

    @Test func modelSettings_isTheSameInstancePassed() {
        clearUserDefaults()
        let sharedSettings = UserSettings()

        let model = ContentViewModel(settings: sharedSettings)

        // 改 model.settings 应立即反映在 sharedSettings (同一引用, @Observable 自动广播)
        model.settings.viewModeRaw = ViewMode.timeline.rawValue
        #expect(sharedSettings.viewModeRaw == ViewMode.timeline.rawValue,
                "改 model.settings 后, sharedSettings 也应看到 (同一引用)")

        // 反向: 改 sharedSettings 也应反映在 model.settings
        sharedSettings.thumbnailSize = 250.0
        #expect(model.settings.thumbnailSize == 250.0,
                "改 sharedSettings 后, model.settings 也应看到 (同一引用)")
    }
}
