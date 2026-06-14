//
//  ThumbnailLayoutModeTests.swift
//  ImageGalleryTests
//
//  V5.17 → V5.46: ThumbnailLayoutMode 单元测试
//  验证：
//  - 3 个 case 完整（保护 Toolbar 布局模式菜单 / masonryRowsView 调度表）
//  - rawValue 稳定（@AppStorage("thumbnailLayoutMode") 持久化契约）
//  - displayName / icon 非空 + 唯一
//  - defaultValue = .square（V5.20 改 iOS Photos.app Library 风格——V5.41/V5.46 修正认知）
//  - masonryParams(rowHeight:) 返 CGFloat? (V5.39.5 简化——只返 uniformWidth, 不再返 stretchLastRow)
//  - id 唯一（ForEach Identifiable 依赖）
//
//  V5.39.5: 删 .masonryStretch case + 删对应测试
//  - allCasesCount: 3 → 2
//  - rawValue 范围: 0, 1 (2 已被删, 老用户 storedLayoutModeRaw=2 ?? .square 平滑回退)
//
//  V5.46: 增 .squareFit case + 对应测试
//  - allCasesCount: 2 → 3
//  - rawValue 范围: 0, 1, 2 (.squareFit 复用之前 .masonryStretch 的 rawValue=2)
//  - 老用户 storedLayoutModeRaw=2 现在会走到 .squareFit (而不是 fallback 到 .square)——更合理
//
//  镜像 AppearanceModeTests pattern
//

import Testing
import CoreGraphics  // CGFloat 在 for-in 循环 type annotation 显式用
@testable import ImageGallery

struct ThumbnailLayoutModeTests {

    // MARK: - 完整性

    @Test func allCasesCountIsThree() {
        // V5.46: 2 → 3 (.squareFit 加)
        // V5.39.5: 3 → 2 (.masonryStretch 删)
        // 防止以后误删/加 case 而忘更新 Toolbar 布局模式菜单 + masonryParams switch
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
        // V5.39.5: .masonryStretch rawValue=2 删, 老用户 storedLayoutModeRaw=2 ?? .square
        // V5.46: .squareFit 复用 rawValue=2——老用户现在 ?? .squareFit (更接近 masonryStretch 原始意图)
        #expect(ThumbnailLayoutMode.square.rawValue == 0)
        #expect(ThumbnailLayoutMode.masonry.rawValue == 1)
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

    @Test func displayNamesAreUnique() {
        // 工具栏菜单内显示——重复会让用户困惑（"两个一样的选项？"）
        let names = ThumbnailLayoutMode.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "displayName 必须唯一")
    }

    @Test func iconsAreUnique() {
        // 工具栏按钮 + 菜单都用同一 icon——重复会视觉混淆
        let icons = ThumbnailLayoutMode.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count, "icon 必须唯一")
    }

    // MARK: - 默认值

    @Test func defaultValueIsSquare() {
        // V5.20: 默认改 .square（iOS Photos.app Library 视图——统一方形 grid，无 ragged right edge）
        // V5.41 修正：macOS Photos.app Library 实际是 Justified Row（= .masonry），不是 .square
        // V5.19 默认 .masonry 被反馈"右边缘空缺 + 不对齐"
        // 截图 27 vs 截图 28 对比：iOS Photos Library 是统一方形——column 完美对齐
        // 老用户 @AppStorage 有 storedLayoutModeRaw 不受影响（仅新装/重置生效）
        #expect(ThumbnailLayoutMode.defaultValue == .square)
    }

    // MARK: - masonryParams 映射（关键：决定 PhotoGridView 调 MasonryMath 的参数）

    @Test func squareMapsToUniformWidth() {
        // V5.39.5: masonryParams 简化, 只返 uniformWidth (CGFloat?)
        //   stretchLastRow 字段已删——所有模式末行都保持 targetRowHeight
        //   .square: 返 rowHeight (方形 cell, MasonryMath 用)
        //   .masonry: 返 nil (JustifiedRowLayout 不读此字段, 仍返以保持 API 兼容)
        let uniformWidth = ThumbnailLayoutMode.square.masonryParams(rowHeight: 200)
        #expect(uniformWidth == 200)
    }

    @Test func masonryMapsToNilUniformWidth() {
        // .masonry: cell 宽 = rowHeight × aspectRatio（按比例），末行不满保留
        //   Photos.app "Days" 行为——末行右缘空着不补
        let uniformWidth = ThumbnailLayoutMode.masonry.masonryParams(rowHeight: 200)
        #expect(uniformWidth == nil)
    }

    @Test func squareFitMapsToUniformWidth() {
        // V5.46 NEW: .squareFit masonryParams 跟 .square 一样 (返 rowHeight)
        //   区别在 PhotoThumbnailView 渲染分支 (.fill vs .fit)——layout 算法层不关心
        //   1:1 方格 + .fit letterbox = macOS Photos.app 按比例真版
        let uniformWidth = ThumbnailLayoutMode.squareFit.masonryParams(rowHeight: 200)
        #expect(uniformWidth == 200)
    }

    @Test func squareUniformWidthScalesWithRowHeight() {
        // uniformWidth 必须 = rowHeight（不同密度下保持方形）
        // 用户切到 120pt 密度 → 方格也是 120×120
        for rowHeight: CGFloat in [80, 120, 170, 200, 280] {
            let uniformWidth = ThumbnailLayoutMode.square.masonryParams(rowHeight: rowHeight)
            #expect(uniformWidth == rowHeight, "rowHeight \(rowHeight) → uniformWidth \(rowHeight)")
        }
    }
}
