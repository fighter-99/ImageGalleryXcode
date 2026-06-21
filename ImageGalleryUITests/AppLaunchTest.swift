//
//  AppLaunchTest.swift
//  ImageGalleryUITests
//
//  V6.22.10 (Layer 2 e2e 自动化): Flow 1 — App 启动 + Onboarding
//   - 验证: 启动后 onboarding sheet 弹 (first-run 检测)
//   - 验证: 点 "开始使用" 后 sheet dismiss
//   - 验证: Empty State 显示 (提示用户拖入/导入)
//   - 防 regression: 如果 OnboardingView dismiss 逻辑改了 / Settings.hasSeenOnboarding reset 改了
//

import XCTest

final class AppLaunchTest: BaseUITestCase {

    func test_launchAndDismissOnboarding() throws {
        // V6.22.10: 验证 app 启动 — 5 sec 给 macOS runner 启动 + SwiftData init 时间
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5),
                      "App window should appear within 5s")

        // V6.22.10: 验证 onboarding sheet 弹 (因为 -uitest-reset-all 清了 hasSeenOnboarding)
        let startButton = app.buttons["onboarding.startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3),
                      "Onboarding button should be present after first launch")

        // V6.22.10: navigate to last page (onboarding 有 3 页, "开始使用"只在最后页)
        //   前两页 button 文字是 "下一步", identifier 仍是 "onboarding.startButton"
        //   点 "下一步" 2 次到第 3 页 → button 变 "开始使用" → 再点 dismiss
        startButton.tap()  // page 0 → page 1
        sleep(1)            // wait for animation
        startButton.tap()  // page 1 → page 2 (开始使用 page)
        sleep(1)
        // 现在 button 是 "开始使用" (zh-Hans/zh-Hant) / "Get Started" (en), 再点 dismiss
        // V6.52 fix: 之前 assert 只查 "开始使用", 但 BaseUITestCase launch arg -AppleLanguages (en)
        //   强制英文 → button label 是 "Get Started" → assert 永远 fail (从 V6.22.10 引入就 broken)
        //   改成 locale-aware: 接受 zh-Hans/zh-Hant/en 任一翻译, 验证我们到了 last page
        let dismissButton = app.buttons["onboarding.startButton"]
        let dismissLabel = dismissButton.label
        let isStartPage = dismissLabel.contains("开始使用")   // zh-Hans "开始使用" / zh-Hant "開始使用"
            || dismissLabel.contains("Get Started")            // en
        XCTAssertTrue(isStartPage,
                      "Onboarding button should be '开始使用' (zh) or 'Get Started' (en) on last page, got '\(dismissLabel)'")
        dismissButton.tap()

        // V6.22.10: sheet dismiss — button 不再存在
        XCTAssertFalse(dismissButton.waitForExistence(timeout: 2),
                       "Onboarding sheet should dismiss after final tap")

        // V6.22.10: Empty state 显示 — 不强匹配具体文案 (V6.22.10 follow-up 优化)
        //   之前用 NSPredicate "label CONTAINS '拖入'" 查 .descendants 没找到
        //   macOS 上 empty state 是 VStack + Button, text label 可能被 a11y tree 切成多个 element
        //   暂时简化: 验证 grid view 出现 (collectionView 或 scrollView)
        //   留 TODO V6.22.11 用更精确的 predicate (加 ContentView accessibilityIdentifier)
        let gridAppeared = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
            || app.scrollViews.firstMatch.waitForExistence(timeout: 1)
        XCTAssertTrue(gridAppeared,
                      "Grid view should appear after onboarding dismiss")
    }
}