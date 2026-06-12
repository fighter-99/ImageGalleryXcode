//
//  FolderFilterToggleTests.swift
//  ImageGalleryTests
//
//  V5.14: FolderFilterPopoverController.handleToggle (V5.13 Day 1 内部化) 测试。
//  filterState 是 private——必须用 onStateChange capture pattern。
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct FolderFilterToggleTests {
    @Test func handleToggleAddsFolderIdToFilterState() {
        let vc = FolderFilterPopoverController(filterState: FilterState(), folders: [])
        let folderID = UUID()
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(folderID)
        #expect(captured?.folders.contains(folderID) == true)
    }

    @Test func handleToggleRemovesExistingFolderId() {
        let folderID = UUID()
        let vc = FolderFilterPopoverController(
            filterState: FilterState(folders: [folderID]),
            folders: []
        )
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(folderID)
        #expect(captured?.folders.contains(folderID) == false)
    }

    @Test func handleToggleOnEmptyStartsWithInsert() {
        let vc = FolderFilterPopoverController(filterState: FilterState(), folders: [])
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(UUID())
        #expect(captured?.folders.count == 1)
    }

    @Test func handleToggleFiresOnStateChange() {
        let vc = FolderFilterPopoverController(filterState: FilterState(), folders: [])
        var callCount = 0
        vc.onStateChange = { _ in callCount += 1 }
        vc.handleToggle(UUID())
        #expect(callCount == 1)
    }

    @Test func handleToggleMultipleFoldersTogglesIndependently() {
        let a = UUID(), b = UUID(), c = UUID()
        let vc = FolderFilterPopoverController(filterState: FilterState(), folders: [])
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(a)
        vc.handleToggle(b)
        vc.handleToggle(c)
        #expect(captured?.folders == [a, b, c])
    }

    @Test func handleToggleTwiceRemovesFromState() {
        let folderID = UUID()
        let vc = FolderFilterPopoverController(filterState: FilterState(), folders: [])
        var captured: FilterState?
        vc.onStateChange = { captured = $0 }
        vc.handleToggle(folderID)
        vc.handleToggle(folderID)
        #expect(captured?.folders.isEmpty == true)
    }
}
