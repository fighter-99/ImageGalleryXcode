//
//  PhotoShapeTests.swift
//  ImageGalleryTests
//
//  V4.36.x: 形状判定单元测试
//  - 边界条件：landscape > portrait > square（含等号归 square）
//

import Testing
import Foundation
@testable import ImageGallery

struct PhotoShapeTests {

    @Test func landscapeWhenWidthExceedsHeight() {
        #expect(PhotoShape.from(width: 1920, height: 1080) == .landscape)
    }

    @Test func portraitWhenHeightExceedsWidth() {
        #expect(PhotoShape.from(width: 1080, height: 1920) == .portrait)
    }

    @Test func squareWhenWidthEqualsHeight() {
        #expect(PhotoShape.from(width: 1000, height: 1000) == .square)
    }

    @Test func squareWhenOneByOne() {
        // 1×1 最小边界
        #expect(PhotoShape.from(width: 1, height: 1) == .square)
    }

    @Test func squareAtEqualBoundary() {
        // 等号归 square（Photos.app 行为），不是 landscape
        #expect(PhotoShape.from(width: 500, height: 500) == .square)
    }

    @Test func allCasesHasThree() {
        // CaseIterable 完整性守护
        #expect(PhotoShape.allCases.count == 3)
    }

    @Test func labelsAreUnique() {
        let labels = PhotoShape.allCases.map { $0.label }
        #expect(Set(labels).count == labels.count)
    }
}
