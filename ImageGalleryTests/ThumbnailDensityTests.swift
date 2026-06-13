//
//  ThumbnailDensityTests.swift
//  ImageGalleryTests
//
//  V5.18: ThumbnailDensity 单元测试
//  验证：
//  - 4 个 case 完整（保护 ViewOptionsPopover 段 + nearest/larger/smaller 调度表）
//  - size 数值契约（.compact 70pt / .small 110pt / .medium 200pt / .large 240pt）
//  - rawValue 稳定（@AppStorage("thumbnailSize") 用 nearest() 落 rawValue 持久化）
//  - displayName / icon 非空 + 唯一
//  - nearest() 边界 + 中间值吸附
//  - larger() / smaller() 边界（最小返回 nil，最大返回 nil）
//  - 4 档 size 单调递增（.compact < .small < .medium < .large）
//
//  镜像 ThumbnailLayoutModeTests pattern
//

import Testing
import CoreGraphics
@testable import ImageGallery

struct ThumbnailDensityTests {

    // MARK: - 完整性

    @Test func allCasesCountIsFour() {
        // V5.18: 3 → 4 档（加 .compact 70pt）
        #expect(ThumbnailDensity.allCases.count == 4)
    }

    @Test func idsAreUnique() {
        // ForEach Identifiable 依赖唯一 id
        let ids = ThumbnailDensity.allCases.map(\.id)
        #expect(Set(ids).count == ids.count, "id 必须唯一——ForEach 渲染依赖")
    }

    // MARK: - size 单调性 + 数值契约

    @Test func sizesAreMonotonicallyIncreasing() {
        // 4 档按 size 升序排列——larger/smaller 依赖此顺序
        let sizes = ThumbnailDensity.allCases.map(\.size)
        for i in 1..<sizes.count {
            #expect(sizes[i] > sizes[i - 1], "size 必须单调递增: \(sizes)")
        }
    }

    @Test func compactSizeIs70pt() {
        // V5.18: .compact = 70pt（Photos "Months" 视图风格）
        #expect(ThumbnailDensity.compact.size == 70)
    }

    @Test func smallSizeIs110pt() {
        #expect(ThumbnailDensity.small.size == 110)
    }

    @Test func mediumSizeIs200pt() {
        // V5.16: 170 → 200（行高 200pt 视觉更宽裕）
        #expect(ThumbnailDensity.medium.size == 200)
    }

    @Test func largeSizeIs240pt() {
        #expect(ThumbnailDensity.large.size == 240)
    }

    // MARK: - rawValue 契约

    @Test func rawValuesAreStable() {
        // @AppStorage("thumbnailSize") 持久化 nearest(to:) 落 rawValue
        // rawValue 改了就破坏老用户偏好——必须锁死
        #expect(ThumbnailDensity.compact.rawValue == "compact")
        #expect(ThumbnailDensity.small.rawValue == "small")
        #expect(ThumbnailDensity.medium.rawValue == "medium")
        #expect(ThumbnailDensity.large.rawValue == "large")
    }

    // MARK: - 显示

    @Test func displayNamesAreNonEmpty() {
        for density in ThumbnailDensity.allCases {
            #expect(!density.label.isEmpty, "\(density.rawValue) 应该有非空 label")
        }
    }

    @Test func displayNamesAreUnique() {
        // popover 段内显示——重复会让用户困惑
        let labels = ThumbnailDensity.allCases.map(\.label)
        #expect(Set(labels).count == labels.count, "label 必须唯一")
    }

    @Test func iconsAreNonEmpty() {
        for density in ThumbnailDensity.allCases {
            #expect(!density.icon.isEmpty, "\(density.rawValue) 应该有非空 icon")
        }
    }

    @Test func iconsAreUnique() {
        // 4 个 icon segment 视觉区分——重复 icon 视觉混淆
        let icons = ThumbnailDensity.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count, "icon 必须唯一")
    }

    // MARK: - nearest() 吸附

    @Test func nearestPicksExactSize() {
        #expect(ThumbnailDensity.nearest(to: 70) == .compact)
        #expect(ThumbnailDensity.nearest(to: 110) == .small)
        #expect(ThumbnailDensity.nearest(to: 200) == .medium)
        #expect(ThumbnailDensity.nearest(to: 240) == .large)
    }

    @Test func nearestPicksCloserTier() {
        // 90pt 距离 .compact(70)=20 vs .small(110)=20——同距，取 first match
        // 80pt 距离 .compact(70)=10 vs .small(110)=30 → .compact
        #expect(ThumbnailDensity.nearest(to: 80) == .compact)
        // 150pt 距离 .small(110)=40 vs .medium(200)=50 → .small
        #expect(ThumbnailDensity.nearest(to: 150) == .small)
        // 220pt 距离 .medium(200)=20 vs .large(240)=20——同距
        #expect(ThumbnailDensity.nearest(to: 220) == .medium)
    }

    @Test func nearestHandlesOutOfRangeValues() {
        // 50pt 低于最小 → .compact
        #expect(ThumbnailDensity.nearest(to: 50) == .compact)
        // 500pt 高于最大 → .large
        #expect(ThumbnailDensity.nearest(to: 500) == .large)
    }

    // MARK: - larger() / smaller() 边界

    @Test func largerReturnsNextTier() {
        // .compact → .small
        #expect(ThumbnailDensity.larger(than: 70) == .small)
        // .small → .medium
        #expect(ThumbnailDensity.larger(than: 110) == .medium)
        // .medium → .large
        #expect(ThumbnailDensity.larger(than: 200) == .large)
    }

    @Test func largerReturnsNilAtMax() {
        // .large 已是最大 → ⌘+ 无下一档
        #expect(ThumbnailDensity.larger(than: 240) == nil)
    }

    @Test func smallerReturnsNextTier() {
        // .large → .medium
        #expect(ThumbnailDensity.smaller(than: 240) == .medium)
        // .medium → .small
        #expect(ThumbnailDensity.smaller(than: 200) == .small)
        // .small → .compact
        #expect(ThumbnailDensity.smaller(than: 110) == .compact)
    }

    @Test func smallerReturnsNilAtMin() {
        // .compact 已是最小 → ⌘- 无下一档
        #expect(ThumbnailDensity.smaller(than: 70) == nil)
    }

    @Test func largerSmallerRoundTrip() {
        // 任意中间档 larger 再 smaller 回到原档
        for density in ThumbnailDensity.allCases.dropFirst().dropLast() {
            let larger = ThumbnailDensity.larger(than: density.size)!
            let back = ThumbnailDensity.smaller(than: larger.size)
            #expect(back == density, "\(density) → \(larger) → \(String(describing: back))")
        }
    }
}
