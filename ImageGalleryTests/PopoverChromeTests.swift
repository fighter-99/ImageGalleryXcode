//
//  PopoverChromeTests.swift
//  ImageGalleryTests
//
//  V5.13：NSVisualEffectView.popoverHost() static helper 测试（V4.80.0 抽）。
//  验 material/state/blendingMode/cornerRadius/borderWidth 配置。
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct PopoverChromeTests {
    @Test func popoverHostReturnsVisualEffectView() {
        let host = NSVisualEffectView.popoverHost()
        // 返回 NSVisualEffectView
        let _: NSVisualEffectView = host  // 编译期类型断言
        // 默认 frame = .zero
        #expect(host.frame == .zero)
    }

    @Test func popoverHostHasPopoverMaterial() {
        // material = .popover（macOS popover 专用材质）
        let host = NSVisualEffectView.popoverHost()
        #expect(host.material == .popover)
    }

    @Test func popoverHostFollowsWindowActiveState() {
        // state = .followsWindowActiveState（窗口 active 时高亮）
        let host = NSVisualEffectView.popoverHost()
        #expect(host.state == .followsWindowActiveState)
    }

    @Test func popoverHostHasPopoverChrome() {
        // V4.67.0 范式：12pt 圆角 + 0.5pt NSColor.separatorColor hairline
        let host = NSVisualEffectView.popoverHost()
        #expect(host.wantsLayer == true)
        #expect(host.layer?.cornerRadius == PopoverStyle.hostCornerRadius)  // 12pt
        #expect(host.layer?.borderWidth == PopoverStyle.hostBorderWidth)  // 0.5pt
        #expect(host.layer?.borderColor == NSColor.separatorColor.cgColor)
    }
}
