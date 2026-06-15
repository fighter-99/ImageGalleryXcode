//
//  ToolbarControllerStartupStateTests.swift
//  ImageGalleryTests
//
//  V5.66: 锁住 updateAllStates 推字段 invariant——修 V5.66 bug '启动不 transition 不同步' 时
//  加的回归测试. ToolbarController 内部 layoutMode/density/sortOption 字段在 updateAllStates
//  后必须跟传入值一致, 不论是 .task 启动推还是 .onChange 后续推.
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct ToolbarControllerStartupStateTests {
    @Test func updateAllStatesChangesLayoutModeField() {
        let tc = ToolbarController()
        #expect(tc.layoutMode == .defaultValue)  // V5.66: 启动硬编码 .defaultValue
        tc.updateAllStates(
            hasSelection: false,
            hasMultipleSelection: false,
            layoutMode: .squareFit
        )
        #expect(tc.layoutMode == .squareFit)
    }

    @Test func updateAllStatesChangesSortOptionField() {
        let tc = ToolbarController()
        #expect(tc.sortOption == .filenameAsc)  // V5.66: 启动默认值
        tc.updateAllStates(
            hasSelection: false,
            hasMultipleSelection: false,
            sortOption: .importedAtDesc
        )
        #expect(tc.sortOption == .importedAtDesc)
    }

    @Test func updateAllStatesWithAllThreeFieldsUpdatesAll() {
        // V5.66: 模拟 ContentView.task 启动推一次——layoutMode + density + sortOption 一次性
        let tc = ToolbarController()
        tc.updateAllStates(
            hasSelection: false,
            hasMultipleSelection: false,
            density: 240,
            layoutMode: .squareFit,
            sortOption: .importedAtDesc
        )
        #expect(tc.layoutMode == .squareFit)
        #expect(tc.thumbnailSize == 240)
        #expect(tc.sortOption == .importedAtDesc)
    }
}
