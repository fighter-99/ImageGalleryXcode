//
//  Wave2ElevationTests.swift
//  ImageGalleryTests
//
//  V6.65 (Wave 2): Elevation 4 档 token 锁定
//  - 测 CGFloat radius / y / opacity (SwiftUI Color 没 Equatable, 不测 color 值)
//

import Testing
import SwiftUI
@testable import ImageGallery

struct Wave2ElevationTests {

    // MARK: - V6.65 (Wave 2): Elevation 4 档锁定

    @Test func elevationSubtleIsResting() {
        // 缩略图 / button resting 状态——极轻阴影
        let subtle = Elevation.subtle
        #expect(subtle.radius == 2)
        #expect(subtle.y == 1)
    }

    @Test func elevationStandardIsCard() {
        // V6.65 NEW: 标准浮层 card / 选中态 thumbnail
        let standard = Elevation.standard
        #expect(standard.radius == 4)
        #expect(standard.y == 2)
    }

    @Test func elevationProminentIsHover() {
        // V6.65 NEW: hover lift 状态——阴影比 resting 深
        let prominent = Elevation.prominent
        #expect(prominent.radius == 8)
        #expect(prominent.y == 3)
    }

    @Test func elevationElevatedIsPopover() {
        // V6.65 NEW: 极高 popover / sheet 浮层
        let elevated = Elevation.elevated
        #expect(elevated.radius == 12)
        #expect(elevated.y == 4)
    }

    @Test func elevationStrongIsAliasForElevated() {
        // V6.65: strong 保留 alias 指向 elevated 防 V3.6.14 调用点 regression
        #expect(Elevation.strong.radius == Elevation.elevated.radius)
        #expect(Elevation.strong.y == Elevation.elevated.y)
    }

    @Test func elevationHierarchyProgression() {
        // 验证档位单调递增: radius 从 subtle → elevated 单调不减
        let radii = [Elevation.subtle.radius, Elevation.standard.radius,
                     Elevation.prominent.radius, Elevation.elevated.radius]
        for i in 1..<radii.count {
            #expect(radii[i] >= radii[i-1], "radius 单调递增")
        }
        let yOffsets = [Elevation.subtle.y, Elevation.standard.y,
                        Elevation.prominent.y, Elevation.elevated.y]
        for i in 1..<yOffsets.count {
            #expect(yOffsets[i] >= yOffsets[i-1], "y offset 单调递增")
        }
    }
}
