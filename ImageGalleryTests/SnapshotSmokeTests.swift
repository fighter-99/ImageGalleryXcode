//
//  SnapshotSmokeTests.swift
//  ImageGalleryTests
//
//  V6.101: 5 个 snapshot smoke test — 视觉回归网基础
//    - SettingsView: 整体 layout (V6.87 7 tab)
//    - PhotoGridEmptyState: 0 photo 空态 (V6.97.6 main CTA)
//    - CropCanvasView: 4:3 默认裁剪框 (V6.99 hitTest + Rotate 修后)
//    - EmptyStateView: 基础组件 (Photos 范式)
//    - ToastView: 视觉稳态 (V6.29.1 undo + V6.97.6 warning)
//
//  跑法:
//  - 第一次跑: 自动 record baseline 到 __Snapshots__/<name>.png, commit 进 repo
//  - 后续跑: byte 比较 baseline — 不一致 XCTFail
//
//  修视觉:
//  - 删 __Snapshots__/<name>.png
//  - 跑测试 — 自动 record 新 baseline
//  - git diff 看 PNG 变化, 决定接受还是调整视觉
//
//  风险 / 注意:
//  - 字体未装 / 颜色管理不同时 baseline 漂移 — 只用 SF Pro 系统字体
//  - macOS 14 vs Tahoe 抗锯齿差异 — V6.101 byte match 太严, V6.102 改 pixel hash 抗 0.05% 漂移
//  - V6.102-103 拆分后视觉零变化 → byte match 通过
//

import XCTest
import SwiftUI
@testable import ImageGallery

/// V6.101: 5 snapshot baseline — 视觉回归网基础
///   XCTest 顺序执行 (项目其他 test 都用 XCTest, 跟 V6.12.21 cfprefsd 并行 trap 隔离)
///   test 方法按字母顺序跑 (test_<view>_<case>)
///   @MainActor: UserSettings 是 @MainActor-isolated (V6.39.0), SwiftData @Model 也是 MainActor
///   XCTest 默认 sync nonisolated 上下文 — 调 MainActor init 要 @MainActor 类
@MainActor
final class SnapshotSmokeTests: SnapshotTestCase {

    // MARK: - SettingsView

    /// V6.101: Settings 整体 layout — 7 tab 切换视觉稳态
    ///   替代 Photos.app macOS Sonoma+ Preferences 真版
    func test_01_settingsView_generalTab() throws {
        let settings = UserSettings()
        let view = SettingsView(settings: settings)
        assertSnapshot(of: view, size: CGSize(width: 720, height: 520), named: "SettingsView_generalTab")
    }

    // MARK: - PhotoGridEmptyState

    /// V6.101: PhotoGrid 空态 — V6.97.6 加 "导入到此文件夹" main CTA
    ///   0 photo 时显示空态 view
    func test_02_photoGridEmptyState_noPhotos() throws {
        let view = PhotoGridEmptyState(
            searchText: "",
            folder: nil,
            tag: nil,
            filterUnfiled: false,
            filterDuplicates: false,
            filterRecent7Days: false,
            filterLargeFiles: false,
            filterInTrash: false,
            isFilterActive: false,
            onImport: {},
            onClearFilters: {},
            retentionDays: 30
        )
        assertSnapshot(of: view, size: CGSize(width: 800, height: 600), named: "PhotoGridEmptyState_noPhotos")
    }

    // MARK: - CropCanvasView (NSView)

    /// V6.101: CropCanvasView 视觉 — 9 handles 拖拽区
    ///   V6.99 修了 hitTest + Rotate 90° fit (M2/M3), 视觉稳态
    ///   注意: CropCanvasView 是 NSView, 不是 SwiftUI View — 走 NSHostingView 包装
    func test_03_cropCanvasView_default() throws {
        let canvas = CropCanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        canvas.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        canvas.aspect = .ratio_4_3
        // 渲染一个 mock 背景图 (1x1 红) — 避免 nil 背景 draw fail
        let bg = NSImage(size: NSSize(width: 1, height: 1))
        bg.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        bg.unlockFocus()
        canvas.backgroundImage = bg

        // NSHostingView 包装 (跟 V6.99 CropSheet 同 pattern)
        let hosting = NSHostingView(rootView: NSViewWrapper(view: canvas))
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hosting.layoutSubtreeIfNeeded()

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            XCTFail("Failed to render CropCanvasView")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let image = NSImage(size: NSSize(width: 800, height: 600))
        image.addRepresentation(bitmap)
        guard let data = Self.pngData(from: image) else {
            XCTFail("Failed to convert to PNG")
            return
        }
        try writeBaselineIfNeeded(data, named: "CropCanvasView_default")
    }

    // MARK: - EmptyStateView (基础组件, 复用)

    /// V6.101: EmptyStateView 基础组件 — Photos 范式 icon + title + subtitle + CTA
    ///   多个 view 复用 (DetailPane / PhotoGrid / Settings), baseline 锁定组件视觉
    func test_04_emptyStateView_basic() throws {
        let view = EmptyStateView(
            icon: "photo.on.rectangle.angled",
            title: "还没有图片",
            subtitle: "拖入图片，或点击下方按钮开始添加",
            style: .accent,
            primaryAction: EmptyStateView.Action(
                label: "导入图片 (⌘O)",
                systemImage: "square.and.arrow.down",
                onTap: {}
            ),
            secondaryAction: nil,
            useNativeStyle: true
        )
        assertSnapshot(of: view, size: CGSize(width: 600, height: 400), named: "EmptyStateView_basic")
    }

    // MARK: - ToastView

    /// V6.101: ToastView 视觉 — V6.29.1 加 undo, V6.97.6 warning 类型
    ///   bottom-right popover, 锁 baseline 防回归
    func test_05_toastView_success() throws {
        let view = ToastView(
            message: "导入完成 100 张照片",
            type: .success,
            duration: 3.0,
            onDismiss: {},
            undoAction: nil
        )
        assertSnapshot(of: view, size: CGSize(width: 400, height: 80), named: "ToastView_success")
    }
}

/// V6.101: NSView → SwiftUI 包装 (NSHostingView 只能吃 SwiftUI View, NSView 要 wrap)
struct NSViewWrapper: View {
    let view: NSView

    var body: some View {
        Representable(view: view)
    }

    /// NSViewRepresentable 包装 NSView 进 SwiftUI tree
    struct Representable: NSViewRepresentable {
        let view: NSView

        func makeNSView(context: Context) -> NSView {
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}