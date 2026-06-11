//
//  TitlebarAccessoryController.swift
//  ImageGallery
//
//  V4.37.3 NEW: NSWindow titlebar 右上角小按钮（macOS Photos.app ⓘ 风格）
//
//  Photos.app / Mail.app / Notes.app 都有 titlebar 右上角小按钮：
//    - Photos.app: ⓘ 显示/隐藏详情面板
//    - Mail.app:   📥 跳到收件箱
//    - Notes.app:  📝 新建备忘录
//
//  NSToolbar 在 toolbar 区域（红黄绿交通灯下方），titlebar accessory 在 titlebar 区域
//  （与交通灯同行 / 紧邻交通灯右侧），用户视线更容易落在那里。
//
//  macOS API: NSTitlebarAccessoryViewController (macOS 10.10+)
//    - window.addTitlebarAccessoryViewController(_:) 添加
//    - controller.layoutAttribute = .trailing 决定位置（leading / center / trailing）
//    - controller.view 容纳一个 NSButton
//

import AppKit

/// V4.37.3: titlebar 右上角按钮的 NSTitlebarAccessoryViewController 包装
/// 通用模式：SF Symbol icon + 点击触发 closure + hover tooltip
/// Photos.app ⓘ 风格（info.circle 图标）——showDetail toggle
@MainActor
final class TitlebarAccessoryController: NSTitlebarAccessoryViewController {
    /// 点击按钮时触发（V4.37.3: 接 ContentView.showDetail toggle）
    private var onAction: (() -> Void)?

    /// V4.37.3: 通用初始化——SF Symbol + 可达性描述 + tooltip + action closure
    ///   image: SF Symbol 名（如 "info.circle"）
    ///   accessibilityLabel: VoiceOver 念出（必须）
    ///   tooltip: hover 显示
    ///   onAction: 点击时调（无值时按钮不响应——通常应给）
    init(
        image: String,
        accessibilityLabel: String,
        tooltip: String,
        onAction: @escaping () -> Void
    ) {
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
        loadViewProgrammatically(
            image: image,
            accessibilityLabel: accessibilityLabel,
            tooltip: tooltip
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// V4.37.3: 手写 view 装载——NSTitlebarAccessoryViewController 通常配 NIB，但项目惯例
    /// 是手写（参考 ToolbarController.makeSimpleItem 手写 NSButton）
    private func loadViewProgrammatically(
        image: String,
        accessibilityLabel: String,
        tooltip: String
    ) {
        // V4.37.3: NSButton + .recessed 风格——与 NSToolbar 内 5 actions 视觉一致
        //   高度 24pt（titlebar accessory 标准高度）——NSTitlebarAccessoryViewController
        //   自动控制 layout，view 实际尺寸由 layoutAttribute 决定
        let button = NSButton(
            image: NSImage(systemSymbolName: image, accessibilityDescription: accessibilityLabel) ?? NSImage(),
            target: self,
            action: #selector(handleClick)
        )
        button.bezelStyle = .recessed
        button.toolTip = tooltip
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        button.frame = container.bounds
        button.autoresizingMask = [.width, .height]
        container.addSubview(button)
        view = container
    }

    @objc private func handleClick() {
        onAction?()
    }
}
