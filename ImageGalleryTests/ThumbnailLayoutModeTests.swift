//
//  ThumbnailLayoutModeTests.swift
//  ImageGalleryTests
//
//  V6.12.12: 砍 .square 后——单 case (.squareFit) 单元测试
//  V5.17 → V5.47: ThumbnailLayoutMode 单元测试历史
//  - V5.17: .square (.fill, iOS Photos Library 风格)
//  - V5.46: + .squareFit (.fit letterbox, macOS Photos 真版)
//  - V5.47: - .masonry (justified row)
//  - V6.12.12: - .square (5 commit 修不了 bug, 用户决定砍掉, 只留 macOS Photos 真版)
//  验证:
//  - 1 个 case (.squareFit) 完整 (V6.12.12 砍 .square 后)
//  - rawValue 稳定（@AppStorage("thumbnailLayoutMode") 持久化契约, 仍 2 不变）
//  - displayName / icon 非空 (单 case 不用测唯一)
//  - defaultValue = .squareFit
//  - masonryParams(rowHeight:) 返 rowHeight
//  - id 唯一（虽然只有 1 个 case, 仍验证 id 不变 rawValue）
//

import Testing
import CoreGraphics
@testable import ImageGallery

struct ThumbnailLayoutModeTests {

    // MARK: - 完整性

    @Test func allCasesCountIsOne() {
        // V6.12.12: 2 → 1 (.square 砍)
        // V5.47: 3 → 2 (.masonry 删)
        // V5.46: 2 → 3 (.squareFit 加)
        // V5.39.5: 3 → 2 (.masonryStretch 删)
        // 防止以后误加 case 而忘更新 Toolbar 布局模式菜单 + masonryParams switch
        #expect(ThumbnailLayoutMode.allCases.count == 1)
    }

    @Test func idsAreUnique() {
        // ForEach Identifiable 依赖唯一 id
        let ids = ThumbnailLayoutMode.allCases.map(\.id)
        #expect(Set(ids).count == ids.count, "id 必须唯一——ForEach 渲染依赖")
    }

    // MARK: - rawValue 契约（@AppStorage 持久化）

    @Test func rawValuesAreStable() {
        // @AppStorage("thumbnailLayoutMode") 用 rawValue 持久化
        // rawValue 改了就破坏老用户偏好——必须锁死
        // V6.12.12: .square (rawValue=0) 砍, 老用户 storedLayoutModeRaw=0 ?? defaultValue (.squareFit) 平滑回退
        // V5.46: .squareFit 复用 rawValue=2——V5.46+ 老用户 ?? .squareFit
        #expect(ThumbnailLayoutMode.squareFit.rawValue == 2)
    }

    @Test func rawValueRoundTrip() {
        // rawValue → enum → rawValue 不丢
        for mode in ThumbnailLayoutMode.allCases {
            let roundTripped = ThumbnailLayoutMode(rawValue: mode.rawValue)
            #expect(roundTripped == mode, "\(mode.rawValue) 必须能 round-trip")
        }
    }

    // MARK: - 显示

    @Test func displayNamesAreNonEmpty() {
        for mode in ThumbnailLayoutMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode.rawValue) 应该有非空 displayName")
        }
    }

    @Test func iconsAreNonEmpty() {
        for mode in ThumbnailLayoutMode.allCases {
            #expect(!mode.icon.isEmpty, "\(mode.rawValue) 应该有非空 icon")
        }
    }

    // MARK: - 默认值

    @Test func defaultValueIsSquareFit() {
        // V6.12.12: 砍 .square 后 defaultValue = .squareFit
        //   .squareFit = macOS Photos.app Library 真版 (1:1 方格 + .fit letterbox)
        //   之前 defaultValue = .square, 改后 = .squareFit
        // 老用户 @AppStorage 有 storedLayoutModeRaw 不受影响（仅新装/重置生效）
        #expect(ThumbnailLayoutMode.defaultValue == .squareFit)
    }

    // MARK: - masonryParams 映射

    @Test func squareFitMapsToUniformWidth() {
        // V6.12.12: 单 case 后 masonryParams 简化——只 .squareFit
        //   返 rowHeight (1:1 方格, MasonryMath 用)
        let uniformWidth = ThumbnailLayoutMode.squareFit.masonryParams(rowHeight: 200)
        #expect(uniformWidth == 200)
    }

    @Test func squareFitUniformWidthScalesWithRowHeight() {
        // uniformWidth 必须 = rowHeight（不同密度下保持方形）
        // 用户切到 120pt 密度 → 方格也是 120×120
        for rowHeight: CGFloat in [80, 120, 170, 200, 280] {
            let uniformWidth = ThumbnailLayoutMode.squareFit.masonryParams(rowHeight: rowHeight)
            #expect(uniformWidth == rowHeight, "rowHeight \(rowHeight) → uniformWidth \(rowHeight)")
        }
    }
}
