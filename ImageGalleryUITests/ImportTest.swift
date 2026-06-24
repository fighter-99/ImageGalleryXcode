//
//  ImportTest.swift
//  ImageGalleryUITests
//
//  V6.22.10 (Layer 2 e2e 自动化): Flow 2 — 导入照片 (launch arg bypass NSOpenPanel)
//   - 验证: -uitest-import-dir <dir> launch arg 触发 import flow
//   - 验证: 1 张测试图 → grid 出现 1 个 thumbnail cell
//   - 防 regression: 如果 ContentViewModel.startImport launch arg 解析改了 / import 流程断了
//

import XCTest

final class ImportTest: BaseUITestCase {
    // V6.22.11: setUp 单 launch + -uitest-import-dir — import 自动跑, no relaunch
    //   之前 terminate+relaunch 在 Xcode 26 runner hang 60s
    //   现在 -uitest-import-dir 在 setUp() 里追加, app startup 直接 import
    override class var uitestLaunchArguments: [String] {
        // 用 Bundle.module 拿测试 bundle, 避免 Bundle(for:) 拿到 app bundle (for type(of: self))
        //   实际更稳: 直接走固定路径 Resources/sample-photo.png (fileSystemSynchronizedGroups 扁平化)
        let bundle = Bundle(for: BaseUITestCase.self)
        guard let resourceURL = bundle.resourceURL else { return [] }
        let testImageURL = resourceURL.appendingPathComponent("sample-photo.png")
        guard FileManager.default.fileExists(atPath: testImageURL.path) else { return [] }
        let testImageDir = testImageURL.deletingLastPathComponent()
        return ["-uitest-import-dir", testImageDir.path]
    }

    func test_importPhotoViaLaunchArg() throws {
        // V6.94.0: 删 V6.22.11 throw XCTSkip — -uitest-reset-store launch arg 已 reset SwiftData store
        //   600+ 累积残留问题解决, test_importPhotoViaLaunchArg 重新启用
        // V6.94.0: 加 timeout 3s → 10s — import + thumbnail generation 实际需 5-8s
        //   (ImageImporter.importPhotos 同步 + ThumbnailCache warmup)
        //   之前 3s 太短, test 在 cell 还没渲染时就 fail
        // V6.22.10: dismiss onboarding + import 1 photo
        let cell = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(cell.waitForExistence(timeout: 10),
                      "Cell should appear after import + thumbnail warmup")
        XCTAssertEqual(app.collectionViews.firstMatch.cells.count, 1,
                       "Grid should have exactly 1 cell after import")
    }
}