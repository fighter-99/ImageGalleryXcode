//
//  SnapshotTestCase.swift
//  ImageGalleryTests
//
//  V6.101: 自写 MinimalSnapshot helper — 不引 SPM, 避免 SPM + FSSG 交互风险
//
//  设计目标:
//  - 给 V6.102-103 大拆提供视觉回归网 (V6.74 toolbar 5 轮迭代教训)
//  - 5 baseline PNG commit 进 repo (1MB 内不需 LFS)
//  - byte hash 比对 (简化, 不引 precision 阈值, 0 SPM)
//
//  为什么自写不用 swift-snapshot-testing:
//  - ImageGallery 0 SPM 依赖 (V6.22.10 playbook FSSG)
//  - SPM + FSSG 交互未在 ImageGallery 验证
//  - 5 baseline 简单 case, NSImage → PNG bytes → 字节比较足够
//  - 跨 macOS 一致 (跟 SPM 第三方库版本无关)
//
//  XCTest 模式:
//  - 用 XCTestCase (项目其他 test 都用这个)
//  - 不引 Swift Testing (@Suite / @Test) — 避免 Swift Testing + cfprefsd 并行 trap (V6.12.21)
//  - test 方法默认顺序 (XCTest 自己 serial)
//

import XCTest
import SwiftUI
import AppKit

/// V6.101: 自写 snapshot test helper — 0 SPM 依赖
///   跨 macOS 一致 (NSImage PNG encoding 稳定), 5 baseline 简单 case 够用
///   用法: 继承 SnapshotTestCase, 在 test 方法调 assertSnapshot(...)
class SnapshotTestCase: XCTestCase {

    /// V6.101: Baseline PNG 存放目录 (跟 test file 同级, FSSG 自动 sync)
    ///   第一次跑 assertSnapshot 会自动 record (跟 swift-snapshot-testing 一致)
    ///   后续跑 diff — 不一致抛 XCTFail
    static let baselineDirectory: URL = {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL.deletingLastPathComponent().appendingPathComponent("__Snapshots__")
    }()

    /// V6.101: SwiftUI view → NSImage
    ///   用 NSHostingView (跟 V6.99 CropSheet 同 pattern) 走 SwiftUI 渲染管线
    ///   size 精确指定 (避免 auto layout 推断差异)
    static func renderView<V: View>(_ view: V, size: CGSize) -> NSImage? {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    /// V6.101: NSImage → PNG Data
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// V6.101: Baseline 比较 — byte 比较
    ///   简化: 不做像素级 diff, byte 完全匹配 (抗抗锯齿不抗)
    ///   V6.102 拆分时如果视觉零变化, byte 必匹配
    ///   如果 baseline fail, 看 PNG binary 差异定位 (而不是模糊 "0.95 precision")
    ///   第一次跑 — record baseline, XCTFail 转 XCTAssert (用 recordSnapshot 模式)
    func writeBaselineIfNeeded(_ data: Data, named name: String) throws {
        let baselineURL = SnapshotTestCase.baselineDirectory.appendingPathComponent("\(name).png")

        if !FileManager.default.fileExists(atPath: baselineURL.path) {
            // V6.101: 第一次跑 — record baseline, 测试通过
            try FileManager.default.createDirectory(
                at: SnapshotTestCase.baselineDirectory, withIntermediateDirectories: true
            )
            try data.write(to: baselineURL)
            print("[Snapshot] Recorded baseline: \(name).png (\(data.count) bytes)")
            return
        }

        // V6.101: 后续跑 — byte 比较
        let existing = try Data(contentsOf: baselineURL)
        if existing != data {
            // V6.101: 失败时写 current PNG (供 diff)
            let diffURL = SnapshotTestCase.baselineDirectory.appendingPathComponent("\(name).diff.png")
            try? data.write(to: diffURL)
            XCTFail("""
            Snapshot mismatch for '\(name)'.
            Baseline: \(existing.count) bytes
            Current:  \(data.count) bytes
            Diff saved to: \(diffURL.lastPathComponent)
            To update baseline: delete \(baselineURL.lastPathComponent) and re-run.
            """)
        }
    }

    /// V6.101: Convenience — SwiftUI view → PNG baseline 比较 (instance method)
    ///   view: 要测试的 SwiftUI view
    ///   size: 渲染尺寸 (frame 精确指定)
    ///   name: test name (e.g. "SettingsView_generalTab")
    func assertSnapshot<V: View>(
        of view: V,
        size: CGSize,
        named name: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let image = Self.renderView(view, size: size),
              let data = Self.pngData(from: image) else {
            XCTFail("Failed to render \(name)", file: file, line: line)
            return
        }

        do {
            try writeBaselineIfNeeded(data, named: name)
        } catch {
            XCTFail("Snapshot write failed for \(name): \(error)", file: file, line: line)
        }
    }
}