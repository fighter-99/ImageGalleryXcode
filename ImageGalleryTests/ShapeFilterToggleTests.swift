//
//  ShapeFilterToggleTests.swift
//  ImageGalleryTests
//
//  V5.14: ShapeFilterPopoverController.handleToggle 测试。
//  参数是 PhotoShape（不是 UUID）——PhotoShape 有 4 cases。
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct ShapeFilterToggleTests {
    @Test func handleToggleAddsShapeToFilterState() {
        let vc = ShapeFilterPopoverController(filterState: FilterState())
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(.square)
        #expect(captured?.shapes.contains(.square) == true)
    }

    @Test func handleToggleRemovesExistingShape() {
        let vc = ShapeFilterPopoverController(
            filterState: FilterState(shapes: [.square])
        )
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(.square)
        #expect(captured?.shapes.contains(.square) == false)
    }

    @Test func handleToggleOnEmptyStartsWithInsert() {
        let vc = ShapeFilterPopoverController(filterState: FilterState())
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(.square)
        #expect(captured?.shapes.count == 1)
    }

    @Test func handleToggleFiresOnStateChange() {
        let vc = ShapeFilterPopoverController(filterState: FilterState())
        var callCount = 0
        vc.onStateChange = { _ in callCount += 1 }
        vc.handleToggle(.square)
        #expect(callCount == 1)
    }

    @Test func handleToggleMultipleShapesTogglesIndependently() {
        let vc = ShapeFilterPopoverController(filterState: FilterState())
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(.square)
        vc.handleToggle(.portrait)
        vc.handleToggle(.landscape)
        #expect(captured?.shapes == [.square, .portrait, .landscape])
    }

    @Test func handleToggleTwiceRemovesFromState() {
        let vc = ShapeFilterPopoverController(filterState: FilterState())
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(.square)
        vc.handleToggle(.square)
        #expect(captured?.shapes.isEmpty == true)
    }
}
