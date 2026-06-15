//
//  ClosureButtonHoverTests.swift
//  ImageGalleryTests
//
//  V5.88: 验证 ClosureButton hover 状态 (4% labelColor bg)
//  filter popover checkbox 鼠标悬停视觉反馈
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct ClosureButtonHoverTests {
    @Test func closureButtonHasHoverBackgroundLayer() {
        // V5.88: ClosureButton init 时创建 hoverBackgroundLayer (4pt 圆角, 透明默认)
        let button = ClosureButton(title: "test", action: {})
        // button.layer 的第一个 sublayer 应是 hoverBackgroundLayer
        let hasHoverLayer = button.layer?.sublayers?.first != nil
        #expect(hasHoverLayer, "V5.88: ClosureButton 应有 hoverBackgroundLayer sublayer")
    }

    @Test func hoverBackgroundLayerDefaultIsTransparent() {
        // V5.88: 默认未 hover 时 bg 透明
        let button = ClosureButton(title: "test", action: {})
        let bg = button.layer?.sublayers?.first
        // V5.88: 默认 backgroundColor == NSColor.clear.cgColor
        #expect(bg?.backgroundColor == NSColor.clear.cgColor, "V5.88: 默认状态 bg 应等于 NSColor.clear.cgColor")
    }

    @Test func closureButtonHasTrackingArea() {
        // V5.88: 视图在 window 后会注册 tracking area (mouseEntered/Exited)
        //   简单测: button 加载后有 tracking area 候选 (updateTrackingAreas 后)
        let button = ClosureButton(title: "test", action: {})
        button.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        // 模拟添加到 view 触发 updateTrackingAreas
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        container.addSubview(button)
        button.updateTrackingAreas()
        // V5.88: 至少 1 个 tracking area
        #expect(button.trackingAreas.count >= 1, "V5.88: 应有至少 1 个 tracking area (mouseEntered/Exited)")
    }
}
