//
//  SelectionAndDeleteTest.swift
//  ImageGalleryUITests
//
//  V6.22.10 (Layer 2 e2e 自动化): Flow 3 — 选中 + 删除
//   - 验证: 点 cell → detail panel 显示
//   - 验证: ⌫ 触发 delete confirmation dialog
//   - 验证: 点确认 → grid 空, 回收站 +1
//   - 防 regression: 如果 cell tap / delete flow / 确认 dialog 改了
//

import XCTest

final class SelectionAndDeleteTest: BaseUITestCase {
    // V6.22.11: setUp() 用 uitestLaunchArguments 注入 -uitest-import-dir
    override class var uitestLaunchArguments: [String] {
        let bundle = Bundle(for: BaseUITestCase.self)
        guard let resourceURL = bundle.resourceURL else { return [] }
        let testImageURL = resourceURL.appendingPathComponent("sample-photo.png")
        guard FileManager.default.fileExists(atPath: testImageURL.path) else { return [] }
        return ["-uitest-import-dir", testImageURL.deletingLastPathComponent().path]
    }

    func test_selectAndDeletePhoto() throws {
        // V6.22.11 follow-up: revert skip
        //   V6.22.10 测试假设环境干净 (grid.cells.count == 1)
        //   实际用户 PhotoStorage 累积 600+ 照片, SwiftData @Model 持久化残留
        //   wipePhotoStorage 只删文件, 不删 SwiftData entries → grid 始终非空
        //   重新启用前需要: (1) 全 reset SwiftData store (2) 或换测试断言策略
        //   暂时恢复 skip, 等 V6.22.12 设计 fix
        throw XCTSkip("V6.22.11 follow-up: 用户累积 SwiftData 数据污染 grid 验证, 待 V6.22.12 全 store reset")

        // V6.22.10: dismiss onboarding
        dismissOnboardingIfPresent()

        // V6.22.10: 点 cell 选中
        let cell = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(cell.waitForExistence(timeout: 3), "Cell should appear")
        cell.tap()

        // V6.22.10: 按 ⌫ 触发 delete (forward delete = XCUIKeyboardKey.delete)
        cell.tap()  // 第二次 tap 确保选中 (cell.tap 可能 toggle selection)
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])

        // V6.22.10: 确认 dialog 弹 — "移到回收站" button (来自 DeleteConfirmDialog / Copy.swift)
        let confirmButton = app.buttons["移到回收站"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3),
                      "Delete confirmation dialog should appear with '移到回收站' button")
        confirmButton.tap()

        // V6.22.10: grid 空 + sidebar "回收站" count 应增加 (从 0 → 1)
        let grid = app.collectionViews.firstMatch
        XCTAssertEqual(grid.cells.count, 0,
                       "Grid should be empty after delete")

        // V6.22.10: sidebar "回收站" 行存在 (V6.22.6 已改名为 "回收站")
        let trashRow = app.staticTexts.matching(NSPredicate(format: "label == '回收站'"))
            .firstMatch
        XCTAssertTrue(trashRow.waitForExistence(timeout: 2),
                      "Sidebar should show '回收站' row after delete")
    }
}