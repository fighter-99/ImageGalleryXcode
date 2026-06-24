//
//  UndoTest.swift
//  ImageGalleryUITests
//
//  V6.22.10 (Layer 2 e2e 自动化): Flow 4 — 撤销 (⌘Z undo)
//   - 验证: 选中 + delete 后 ⌘Z 能恢复 photo
//   - 防 regression: 如果 ImageGalleryUndoManager 逻辑改了 / Edit menu wiring 断了
//

import XCTest

final class UndoTest: BaseUITestCase {
    // V6.22.11: setUp() 用 uitestLaunchArguments 注入 -uitest-import-dir
    override class var uitestLaunchArguments: [String] {
        let bundle = Bundle(for: BaseUITestCase.self)
        guard let resourceURL = bundle.resourceURL else { return [] }
        let testImageURL = resourceURL.appendingPathComponent("sample-photo.png")
        guard FileManager.default.fileExists(atPath: testImageURL.path) else { return [] }
        return ["-uitest-import-dir", testImageURL.deletingLastPathComponent().path]
    }

    func test_undoAfterDelete() throws {
        // V6.94.0: 删 V6.22.11 throw XCTSkip — -uitest-reset-store launch arg 已 reset SwiftData store
        //   600+ 累积残留问题解决, test_undoAfterDelete 重新启用
        // V6.94.0: 加 timeout 3s → 10s — import + thumbnail generation 实际需 5-8s
        //   之前 3s 太短, test 在 cell 还没渲染时就 fail
        // V6.22.10: dismiss onboarding

        // V6.22.10: 选中 + delete
        let cell = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "Cell should appear")
        cell.tap()
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])

        let confirmButton = app.buttons["移到回收站"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3),
                      "Delete confirmation should appear")
        confirmButton.tap()

        // V6.22.10: 验证 grid 空 (delete 成功)
        let grid = app.collectionViews.firstMatch
        XCTAssertEqual(grid.cells.count, 0, "Grid empty after delete")

        // V6.22.10: ⌘Z 撤销 — V6.14.10 ImageGalleryUndoManager 走 Edit menu UndoRedoMenuButtons
        //   XCUITest typeKey "z" with .command → 触发 app's ⌘Z handler
        app.typeKey("z", modifierFlags: .command)

        // V6.22.10: photo 恢复 — grid 重新出现 1 个 cell
        XCTAssertTrue(grid.cells.firstMatch.waitForExistence(timeout: 3),
                      "Photo should be restored after ⌘Z undo")
        XCTAssertEqual(grid.cells.count, 1, "Grid should have 1 cell after undo")
    }
}