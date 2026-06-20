//
//  FontScaleTests.swift
//  ImageGalleryTests
//
//  V6.33.3: FontScale enum 单元测试
//    4 档 (compact/default/relaxed/large) 验证:
//    - displayName 中文 i18n
//    - dynamicTypeSize 映射到 SwiftUI DynamicTypeSize
//    - rawValue 持久化
//

import Testing
import SwiftUI
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct FontScaleTests {

    // MARK: - 基本属性

    @Test func fontScaleHasFourCases() {
        #expect(FontScale.allCases.count == 4)
    }

    @Test func fontScaleDefaultIsDefault() {
        #expect(FontScale.defaultValue == .default)
    }

    @Test func fontScaleIdsMatchRawValues() {
        for scale in FontScale.allCases {
            #expect(scale.id == scale.rawValue)
        }
    }

    // MARK: - displayName i18n

    @Test func compactDisplayNameIsChinese() {
        #expect(FontScale.compact.displayName == "紧凑")
    }

    @Test func defaultDisplayNameIsChinese() {
        #expect(FontScale.default.displayName == "默认")
    }

    @Test func relaxedDisplayNameIsChinese() {
        #expect(FontScale.relaxed.displayName == "舒适")
    }

    @Test func largeDisplayNameIsChinese() {
        #expect(FontScale.large.displayName == "超大")
    }

    // MARK: - dynamicTypeSize 映射 (V6.33.1 关键 contract)

    @Test func compactMapsToSmall() {
        #expect(FontScale.compact.dynamicTypeSize == .small)
    }

    @Test func defaultMapsToMedium() {
        #expect(FontScale.default.dynamicTypeSize == .medium)
    }

    @Test func relaxedMapsToLarge() {
        #expect(FontScale.relaxed.dynamicTypeSize == .large)
    }

    @Test func largeMapsToXLarge() {
        #expect(FontScale.large.dynamicTypeSize == .xLarge)
    }

    // MARK: - 持久化 roundtrip

    @Test func fontScaleRawValueStable() {
        // rawValue 用于 UserDefaults 持久化, 改字符串会破坏用户配置
        // 锁定: 加新 case 没问题, 改/删/重命名要 migration
        #expect(FontScale.compact.rawValue == "compact")
        #expect(FontScale.default.rawValue == "default")
        #expect(FontScale.relaxed.rawValue == "relaxed")
        #expect(FontScale.large.rawValue == "large")
    }

    @Test func fontScaleFromInvalidRawValueFails() {
        // 防御性: 持久化的 rawValue 失效 (升级/外部改动) 时返 nil
        #expect(FontScale(rawValue: "invalid") == nil)
    }
}
