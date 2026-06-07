//
//  AppearanceModeTests.swift
//  ImageGalleryTests
//
//  V3.6.22: AppearanceMode 单元测试
//  验证：
//  - 3 个 case 完整
//  - rawValue 稳定（@AppStorage 持久化契约）
//  - displayName / icon 非空
//  - colorScheme 映射：.system → nil（不覆盖系统），.light → .light，.dark → .dark
//

import Testing
import SwiftUI
@testable import ImageGallery

struct AppearanceModeTests {

    // MARK: - 完整性

    @Test func allCasesCountIsThree() {
        // 防止以后误删 case 而忘更新 SettingsView
        #expect(AppearanceMode.allCases.count == 3)
    }

    @Test func rawValuesAreStable() {
        // @AppStorage("appearanceMode") 用 rawValue 持久化，rawValue 不能改
        #expect(AppearanceMode.system.rawValue == 0)
        #expect(AppearanceMode.light.rawValue == 1)
        #expect(AppearanceMode.dark.rawValue == 2)
    }

    // MARK: - 显示

    @Test func displayNamesAreNonEmpty() {
        for mode in AppearanceMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode.rawValue) 应该有非空 displayName")
        }
    }

    @Test func iconsAreNonEmpty() {
        for mode in AppearanceMode.allCases {
            #expect(!mode.icon.isEmpty, "\(mode.rawValue) 应该有非空 icon")
        }
    }

    // MARK: - colorScheme 映射（关键：决定 .preferredColorScheme 怎么驱动）

    @Test func systemMapsToNil() {
        // .system 必须映射 nil，否则会强制覆盖系统的浅色/深色选择
        #expect(AppearanceMode.system.colorScheme == nil)
    }

    @Test func lightMapsToLight() {
        #expect(AppearanceMode.light.colorScheme == .light)
    }

    @Test func darkMapsToDark() {
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    // MARK: - 默认值

    @Test func defaultValueIsSystem() {
        // 首次安装应跟随系统（不强制覆盖）
        #expect(AppearanceMode.defaultValue == .system)
    }
}
