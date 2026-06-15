//
//  SettingsCategoryTests.swift
//  ImageGalleryTests
//
//  V5.58-2: SettingsCategory enum 单元测试
//  覆盖: 6 case 数量, .about 在末尾, title/icon/rawValue 唯一性
//  全部不需 ModelContainer——纯 enum 验证
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct SettingsCategoryTests {

    @Test func allCases_containsFiveExpectedCases() {
        // V5.57-1 加 .about——5 类 (general/appearance/library/accent/about)
        #expect(SettingsCategory.allCases.count == 5)
    }

    @Test func allCases_includesGeneralAppearanceLibraryAccentAbout() {
        // 全 6 类都得在
        #expect(SettingsCategory.allCases.contains(.general))
        #expect(SettingsCategory.allCases.contains(.appearance))
        #expect(SettingsCategory.allCases.contains(.library))
        #expect(SettingsCategory.allCases.contains(.accent))
        #expect(SettingsCategory.allCases.contains(.about))
    }

    @Test func about_isLastCase() {
        // macOS Photos.app 习惯——about 放最末
        #expect(SettingsCategory.allCases.last == .about)
    }

    @Test func title_returnsChineseLabel() {
        // 每个 case title 是中文字符串
        #expect(SettingsCategory.general.title == "通用")
        #expect(SettingsCategory.appearance.title == "外观")
        #expect(SettingsCategory.library.title == "图库")
        #expect(SettingsCategory.accent.title == "强调色")
        #expect(SettingsCategory.about.title == "关于")
    }

    @Test func icon_returnsNonEmptySFSymbolName() {
        // 每个 case icon 是非空 SF Symbol 字符串
        for category in SettingsCategory.allCases {
            #expect(!category.icon.isEmpty, "\(category) 的 icon 应非空")
            #expect(category.icon.allSatisfy { $0.isLetter || $0 == "." || $0.isNumber },
                    "\(category) 的 icon '\(category.icon)' 应是 SF Symbol 字符")
        }
    }

    @Test func rawValue_isUniqueIdentifier() {
        // rawValue 唯一——防止改名破坏持久化
        let rawValues = SettingsCategory.allCases.map { $0.rawValue }
        let uniqueCount = Set(rawValues).count
        #expect(rawValues.count == uniqueCount, "rawValue 应唯一, 实际: \(rawValues)")
    }

    @Test func id_matchesRawValue() {
        // id == rawValue (Identifiable 协议实现)
        for category in SettingsCategory.allCases {
            #expect(category.id == category.rawValue)
        }
    }
}
