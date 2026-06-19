//
//  BaseUITestCase.swift
//  ImageGalleryUITests
//
//  V6.22.10 (Layer 2 e2e 自动化): XCUITest smoke 基类
//   - setUp: 全 wipe (UserDefaults + PhotoStorage) → 启动 app with -uitest-reset-all
//   - tearDown: wipe PhotoStorage (UserDefaults 每次 setUp 都 wipe)
//   - 每个 test 互不依赖, 失败立即 fail 不 continue
//   - 提供 helper: dismissOnboardingIfPresent / importTestPhoto
//

import XCTest

class BaseUITestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        // V6.22.10: 失败立即停 — 防止后续 step 掩盖真因
        continueAfterFailure = false

        app = XCUIApplication(bundleIdentifier: "com.iridescent.ImageGallery")
        // V6.22.10: -uitest-reset-all 清 UserDefaults → onboarding 必弹, viewMode 重置
        //   让 AppLaunchTest 能验证"first-run onboarding 弹"逻辑
        app.launchArguments += [
            "-uitest-reset-all",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US@currency=USD",
        ]
        app.launch()
    }

    override func tearDown() {
        // V6.22.10: 清理 PhotoStorage 目录 (UserDefaults 下一 test setUp 重 wipe)
        wipePhotoStorage()
        super.tearDown()
    }

    // MARK: - Helpers

    /// 删 PhotoStorage 目录里所有图片文件, 保留目录
    ///   - 跟 prod PhotoStorage.shared.photosDirectory 路径一致
    ///   - 不动 .DS_Store 等隐藏文件
    func wipePhotoStorage() {
        // V6.22.10: 用 prod PhotoStorage 路径, 不硬编码 — 单一真相源
        let appSupportBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let photoDir = appSupportBase
            .appendingPathComponent("ImageGallery", isDirectory: true)
            .appendingPathComponent("Photos", isDirectory: true)

        guard FileManager.default.fileExists(atPath: photoDir.path) else { return }

        let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp"]
        if let contents = try? FileManager.default.contentsOfDirectory(at: photoDir, includingPropertiesForKeys: nil) {
            for url in contents where imageExts.contains(url.pathExtension.lowercased()) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// dismiss onboarding sheet 如果存在 (不在 AppLaunchTest 调用, 那个 test 故意保留它)
    func dismissOnboardingIfPresent() {
        let startButton = app.buttons["onboarding.startButton"]
        if startButton.waitForExistence(timeout: 2) {
            startButton.tap()
        }
    }

    /// 注入测试图片 (重新 launch app, 这次带 -uitest-import-dir)
    ///   - 必须 terminate app + 重新 launch, 因为 launch arg 只在启动时读
    ///   - V6.22.10 修: Xcode fileSystemSynchronizedGroups 把子目录文件扁平化到 Resources/
    ///     (image at ImageGalleryUITests/Resources/test-fixtures/sample-photo.png
    ///     → bundle at Resources/sample-photo.png)
    ///     所以直接读 sample-photo.png, 不走 subdirectory
    func importTestPhoto() {
        let bundle = Bundle(for: type(of: self))
        let testImageURL = bundle.resourceURL!
            .appendingPathComponent("sample-photo.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: testImageURL.path),
                      "Test fixture should exist at \(testImageURL.path)")

        // launch arg 接受目录路径, 用 sample-photo.png 所在目录
        let testImageDir = testImageURL.deletingLastPathComponent()
        app.terminate()
        app.launchArguments += ["-uitest-import-dir", testImageDir.path]
        app.launch()
        // 等待 grid 出现
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5),
                      "Grid should appear after import")
    }
}