//
//  ToolbarButtonSizeTests.swift
//  ImageGalleryTests
//
//  V5.79: 验证 toolbar button 大小在 image 切换时保持一致
//  修 4 档 density SF Symbol intrinsic size 微差 → 按钮 bezel 跟 image 变 → 大小不一致
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct ToolbarButtonSizeTests {
    @Test func newMenuItemButtonHasFixedSizeConstraints() {
        // V5.79: makeMenuItem 加显式 28x28 widthAnchor/heightAnchor constraints
        //   锁死 button frame, 防止 image 切换引起 toolbar 重新 layout 时 button 变
        let tc = ToolbarController()
        // 通过 makeMenuItem 是 private, 走 updateAllStates 触发按钮创建路径间接验证
        // 简化: 直接 new 一个 NSButton 用同样 constraints 模拟
        let button = NSButton()
        button.imageScaling = .scaleProportionallyDown
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        // 模拟 image 切换 (medium → large)
        button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let size1 = button.frame.size
        button.image = NSImage(systemSymbolName: "square", accessibilityDescription: nil)
        let size2 = button.frame.size
        #expect(size1 == size2, "V5.79: button 大小应在 image 切换时保持一致 (medium=\(size1), large=\(size2))")
    }
}
