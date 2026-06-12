//
//  FilterCategoryTests.swift
//  ImageGalleryTests
//
//  V5.13：FilterCategory enum 行为测试。
//  FilterState 派生查询依赖 rawValue 稳定（UserDefaults / 持久化），title/icon 是 UI 字符串。
//

import Testing
import Foundation
@testable import ImageGallery

struct FilterCategoryTests {
    @Test func allCasesIsFour() {
        #expect(FilterCategory.allCases.count == 4)
    }

    @Test func rawValuesAreStable() {
        // rawValue 用于持久化——保持稳定（改名 = 旧数据失效）
        #expect(FilterCategory.folder.rawValue == "folder")
        #expect(FilterCategory.tag.rawValue == "tag")
        #expect(FilterCategory.shape.rawValue == "shape")
        #expect(FilterCategory.rating.rawValue == "rating")
    }

    @Test func rawValuesAreUnique() {
        let raws = Set(FilterCategory.allCases.map(\.rawValue))
        #expect(raws.count == 4)
    }

    @Test func titlesAreChinese() {
        // 与 image-gallery-text-consistency 字典对齐：文件夹/标签/形状/评分
        #expect(FilterCategory.folder.title == "文件夹")
        #expect(FilterCategory.tag.title == "标签")
        #expect(FilterCategory.shape.title == "形状")
        #expect(FilterCategory.rating.title == "评分")
    }

    @Test func iconsAreSFSymbols() {
        // SF Symbol 名——macOS Photos 实际使用风格
        #expect(FilterCategory.folder.icon == "folder")
        #expect(FilterCategory.tag.icon == "tag")
        #expect(FilterCategory.shape.icon == "rectangle")
        #expect(FilterCategory.rating.icon == "star")
    }

    // 注：FilterCategory 暂未声明 Codable（V5.13 暂不引入持久化）——跳过 codable round-trip 测试
}
