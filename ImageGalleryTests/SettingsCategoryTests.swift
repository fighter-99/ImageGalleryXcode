//
//  SettingsCategoryTests.swift
//  ImageGalleryTests
//
//  V5.58-2: SettingsCategory enum 单元测试
//  V6.39.0: 更新 — 5 → 7 cases (新增 trash/language/shortcuts, accent 移除搬到 appearance 内)
//  V6.90.0: 更新 — 7 → 5 cases (合并 .trash 到 .library, .shortcuts 到 .general)
//    跟 macOS Sonoma+ System Settings 真版 5-6 categories 接近, segmented 视觉密度减 30%
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct SettingsCategoryTests {

    @Test func allCases_containsFiveCases() {
        // V6.90.0: 7 → 5 cases (合并 .trash 到 .library, .shortcuts 到 .general)
        //   跟 macOS Sonoma+ System Settings 真版 5-6 categories 接近
        #expect(SettingsCategory.allCases.count == 5)
    }

    @Test func allCases_includesAllExpectedCategories() {
        // V6.90.0: 5 类 (V6.39.0 7 类合并: 回收站并入图库, 快捷键并入通用)
        #expect(SettingsCategory.allCases.contains(.general))
        #expect(SettingsCategory.allCases.contains(.appearance))
        #expect(SettingsCategory.allCases.contains(.library))
        #expect(SettingsCategory.allCases.contains(.language))
        #expect(SettingsCategory.allCases.contains(.about))
    }

    @Test func about_isLastCase() {
        // macOS Photos.app 习惯——about 放最末
        #expect(SettingsCategory.allCases.last == .about)
    }

    @Test func title_returnsChineseLabel() {
        // V6.90.0: 5 类每个 title 是中文字符串 (V6.39.0 7 类合并后)
        #expect(SettingsCategory.general.title == "通用")
        #expect(SettingsCategory.appearance.title == "外观")
        #expect(SettingsCategory.library.title == "图库")
        #expect(SettingsCategory.language.title == "语言")
        #expect(SettingsCategory.about.title == "关于")
    }

    @Test func icon_returnsNonEmptySFSymbolName() {
        for category in SettingsCategory.allCases {
            #expect(!category.icon.isEmpty, "\(category) 的 icon 应非空")
            #expect(category.icon.allSatisfy { $0.isLetter || $0 == "." || $0.isNumber },
                    "\(category) 的 icon '\(category.icon)' 应是 SF Symbol 字符")
        }
    }

    @Test func rawValue_isUniqueIdentifier() {
        let rawValues = SettingsCategory.allCases.map { $0.rawValue }
        let uniqueCount = Set(rawValues).count
        #expect(rawValues.count == uniqueCount, "rawValue 应唯一, 实际: \(rawValues)")
    }

    @Test func id_matchesRawValue() {
        for category in SettingsCategory.allCases {
            #expect(category.id == category.rawValue)
        }
    }
}
