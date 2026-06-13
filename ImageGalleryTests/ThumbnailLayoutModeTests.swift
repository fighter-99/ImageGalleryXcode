//
//  ThumbnailLayoutModeTests.swift
//  ImageGalleryTests
//
//  V5.17: ThumbnailLayoutMode 单元测试
//  验证：
//  - 3 个 case 完整（保护 ViewOptionsPopover / masonryRowsView 调度表）
//  - rawValue 稳定（@AppStorage("thumbnailLayoutMode") 持久化契约）
//  - displayName / icon 非空
//  - defaultValue = .masonry（V5.19 默认——Photos Days 风格末行不满不补齐）
//  - masonryParams(rowHeight:) 映射到 MasonryMath 3 模式
//    · .square:         uniformWidth = rowHeight, stretchLastRow = false
//    · .masonry:        uniformWidth = nil,        stretchLastRow = false
//    · .masonryStretch: uniformWidth = nil,        stretchLastRow = true
//  - id 唯一（ForEach Identifiable 依赖）
//
//  镜像 AppearanceModeTests pattern
//

import Testing
import CoreGraphics  // CGFloat 在 for-in 循环 type annotation 显式用
@testable import ImageGallery

struct ThumbnailLayoutModeTests {

    // MARK: - 完整性

    @Test func allCasesCountIsThree() {
        // 防止以后误删 case 而忘更新 ViewOptionsPopover 段 + masonryParams switch
        #expect(ThumbnailLayoutMode.allCases.count == 3)
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
        #expect(ThumbnailLayoutMode.square.rawValue == 0)
        #expect(ThumbnailLayoutMode.masonry.rawValue == 1)
        #expect(ThumbnailLayoutMode.masonryStretch.rawValue == 2)
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

    @Test func displayNamesAreUnique() {
        // popover 段内显示——重复会让用户困惑（"两个一样的选项？"）
        let names = ThumbnailLayoutMode.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "displayName 必须唯一")
    }

    @Test func iconsAreUnique() {
        // 3 个 icon segment 视觉区分——重复 icon 视觉混淆
        let icons = ThumbnailLayoutMode.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count, "icon 必须唯一")
    }

    // MARK: - 默认值

    @Test func defaultValueIsSquare() {
        // V5.20: 默认改 .square（Photos.app Library 视图——统一方形 grid，无 ragged right edge）
        // V5.19 默认 .masonry 被反馈"右边缘空缺 + 不对齐"
        // 截图 27 vs 截图 28 对比：Photos Library 是统一方形——column 完美对齐
        // 老用户 @AppStorage 有 storedLayoutModeRaw 不受影响（仅新装/重置生效）
        #expect(ThumbnailLayoutMode.defaultValue == .square)
    }

    // MARK: - masonryParams 映射（关键：决定 PhotoGridView 调 MasonryMath 的参数）

    @Test func squareMapsToUniformWidthWithNoStretch() {
        // .square: 所有 cell 用 rowHeight 宽（方形），不拉伸末行
        //   拉伸会让方格变形（变矩形）
        let params = ThumbnailLayoutMode.square.masonryParams(rowHeight: 200)
        #expect(params.uniformWidth == 200)
        #expect(params.stretchLastRow == false)
    }

    @Test func masonryMapsToAspectModeNoStretch() {
        // .masonry: cell 宽 = rowHeight × aspectRatio（按比例），末行不满保留
        //   Photos.app "Days" 行为——末行右缘空着不补
        let params = ThumbnailLayoutMode.masonry.masonryParams(rowHeight: 200)
        #expect(params.uniformWidth == nil)
        #expect(params.stretchLastRow == false)
    }

    @Test func masonryStretchMapsToAspectModeWithStretch() {
        // .masonryStretch: cell 宽按比例，末行均分多余宽
        //   Flickr/500px 风格——消除"空右缘"但不破坏行高
        let params = ThumbnailLayoutMode.masonryStretch.masonryParams(rowHeight: 200)
        #expect(params.uniformWidth == nil)
        #expect(params.stretchLastRow == true)
    }

    @Test func squareUniformWidthScalesWithRowHeight() {
        // uniformWidth 必须 = rowHeight（不同密度下保持方形）
        // 用户切到 120pt 密度 → 方格也是 120×120
        for rowHeight: CGFloat in [80, 120, 170, 200, 280] {
            let params = ThumbnailLayoutMode.square.masonryParams(rowHeight: rowHeight)
            #expect(params.uniformWidth == rowHeight, "rowHeight \(rowHeight) → uniformWidth \(rowHeight)")
        }
    }

    @Test func masonryAndMasonryStretchOnlyDifferInStretchFlag() {
        // .masonry vs .masonryStretch 唯一区别就是 stretchLastRow
        // —— 验证 enum 区分意图一致（不是误把不同 case 写一样了）
        let a = ThumbnailLayoutMode.masonry.masonryParams(rowHeight: 200)
        let b = ThumbnailLayoutMode.masonryStretch.masonryParams(rowHeight: 200)
        #expect(a.uniformWidth == b.uniformWidth)
        #expect(a.stretchLastRow != b.stretchLastRow)
    }
}
