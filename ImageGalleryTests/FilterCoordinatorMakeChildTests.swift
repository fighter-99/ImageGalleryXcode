//
//  FilterCoordinatorMakeChildTests.swift
//  ImageGalleryTests
//
//  V5.14: FilterPopoverCoordinator.makeChildViewController (V5.13 Day 1 内部化) +
//  lastWrittenState (V5.13 Day 1 改 private(set)) 路由测试。
//  4 个 category → 4 个子 popover VC 类型分发 + 1 个副作用测试。
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct FilterCoordinatorMakeChildTests {
    @Test func makeChildViewControllerReturnsFolderVCForFolderCategory() {
        let coord = FilterPopoverCoordinator(folders: [], tags: [], onStateChange: { _ in })
        let vc = coord.makeChildViewController(category: .folder, filterState: FilterState())
        #expect(vc is FolderFilterPopoverController)
    }

    @Test func makeChildViewControllerReturnsTagVCForTagCategory() {
        let coord = FilterPopoverCoordinator(folders: [], tags: [], onStateChange: { _ in })
        let vc = coord.makeChildViewController(category: .tag, filterState: FilterState())
        #expect(vc is TagFilterPopoverController)
    }

    @Test func makeChildViewControllerReturnsShapeVCForShapeCategory() {
        let coord = FilterPopoverCoordinator(folders: [], tags: [], onStateChange: { _ in })
        let vc = coord.makeChildViewController(category: .shape, filterState: FilterState())
        #expect(vc is ShapeFilterPopoverController)
    }

    @Test func makeChildViewControllerReturnsRatingVCForRatingCategory() {
        let coord = FilterPopoverCoordinator(folders: [], tags: [], onStateChange: { _ in })
        let vc = coord.makeChildViewController(category: .rating, filterState: FilterState())
        #expect(vc is RatingFilterPopoverController)
    }

    @Test func makeChildViewControllerStoresLastWrittenState() {
        // V4.89.0: makeChildViewController 副作用——lastWrittenState = filterState
        //   后续 openChild 读 lastWrittenState 取回当前 filterState
        let coord = FilterPopoverCoordinator(folders: [], tags: [], onStateChange: { _ in })
        let state = FilterState(folders: [UUID()])
        _ = coord.makeChildViewController(category: .folder, filterState: state)
        #expect(coord.lastWrittenState?.folders == state.folders)
    }
}
