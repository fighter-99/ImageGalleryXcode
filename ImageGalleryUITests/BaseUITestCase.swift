//
//  BaseUITestCase.swift
//  ImageGalleryUITests
//
//  V6.22.10 (Layer 2 e2e 自动化): XCUITest smoke 基类
//   - setUp: 全 wipe (UserDefaults + PhotoStorage) → 启动 app with -uitest-reset-all
//   - tearDown: wipe PhotoStorage (UserDefaults 每次 setUp 都 wipe)
//   - 每个 test 互不依赖, 失败立即 fail 不 continue
//   - 提供 helper: importTestPhoto (V6.70: 删 dismissOnboardingIfPresent)
//

import XCTest

class BaseUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// V6.22.11: 子类覆盖 — 在 setUp launch 前追加 launch args
    ///   之前: ImportTest 在 setUp 之后 terminate+relaunch 加 -uitest-import-dir
    ///     不可靠 — terminate 在 Xcode 26 runner 上 hang 60s timeout
    ///   现在: setUp 直接带 -uitest-import-dir, import 在 app startup 时自动跑
    ///     单 launch, no relaunch, race-free
    ///   AppLaunchTest 不覆盖 → 只 reset, onboarding 必弹 (smoke pass)
    ///   ImportTest/SelectionAndDeleteTest/UndoTest 覆盖 → reset + import-dir
    class var uitestLaunchArguments: [String] { [] }

    override func setUp() {
        super.setUp()
        // V6.22.10: 失败立即停 — 防止后续 step 掩盖真因
        continueAfterFailure = false

        app = XCUIApplication(bundleIdentifier: "com.iridescent.ImageGallery")
        // V6.22.10: -uitest-reset-all 清 UserDefaults → onboarding 必弹, viewMode 重置
        //   让 AppLaunchTest 能验证"first-run onboarding 弹"逻辑
        // V6.22.11: 子类 uitestLaunchArguments 追加 (e.g. -uitest-import-dir)
        app.launchArguments += [
            "-uitest-reset-all",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US@currency=USD",
        ]
        app.launchArguments += Self.uitestLaunchArguments
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
    ///   V6.70: 删 dismissOnboardingIfPresent — OnboardingView 取消, helper 无 caller
    //   ImportTest / UndoTest / SelectionAndDeleteTest 各删 1 行 caller

    /// V6.22.11: deprecated — 改用子类 uitestLaunchArguments 静态属性
    ///   之前 terminate+relaunch 不可靠 (Xcode 26 runner 60s hang)
    ///   现在 import 在 setUp 单 launch 时自动跑 (ImportTest 通过 uitestLaunchArguments 注入 -uitest-import-dir)
    ///   保留函数签名给 V6.22.10 兼容
    func importTestPhoto() {
        // V6.22.11: no-op — setUp already imported via launch arg
        //   ImportTest.test_importPhotoViaLaunchArg 现在只验证 grid 出现 1 cell
    }
}