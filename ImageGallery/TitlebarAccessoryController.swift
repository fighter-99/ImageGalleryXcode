//
//  TitlebarAccessoryController.swift
//  ImageGallery
//
//  V4.37.3 NEW: NSWindow titlebar 右上角小按钮（macOS Photos.app ⓘ 风格）
//  V4.37.4: 状态感知 + 动态 tooltip——保持与项目其他风格统一
//
//  Photos.app / Mail.app / Notes.app 都有 titlebar 右上角小按钮：
//    - Photos.app: ⓘ 显示/隐藏详情面板（按下时变填充 + 强调色）
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
//  V4.37.4 状态感知模式（仿 V4.36.x Filter 按钮 didSet → updateBadge 模式）：
//    - 外部状态（showDetail）通过 setActive(_:) 推入
//    - 图标 inactiveSymbol ↔ activeSymbol 切换
//    - tint 强调色 vs 系统默认
//    - tooltip 反映当前操作
//    - 与 Photos.app 风格完全一致
//

import AppKit

/// V4.37.3 + V4.37.4: titlebar 右上角按钮的 NSTitlebarAccessoryViewController 包装
/// Photos.app ⓘ 风格：状态感知 toggle 按钮
///
/// V4.37.4 通用化：双 symbol 参数 + setActive + setTooltip
///   - inactiveSymbol: 默认状态 SF Symbol（如 "info.circle"）
///   - activeSymbol: 激活状态 SF Symbol（如 "info.circle.fill"）
///   - 状态由外部驱动（ContentView.showDetail 通过 .onChange 推入）
@MainActor
final class TitlebarAccessoryController: NSTitlebarAccessoryViewController {
    /// 点击按钮时触发（V4.37.3: 接 ContentView.showDetail toggle）
    private var onAction: (() -> Void)?

    /// V4.37.4: 双 symbol + label 持久化用于切换 icon
    private let inactiveSymbol: String
    private let activeSymbol: String
    private let label: String

    /// V4.37.4: 当前激活状态——决定 icon + tint
    private var isActive: Bool = false

    /// V4.37.4: 弱引用 NSButton 用于 setActive / setTooltip 状态更新
    /// weak 避免 NSTitlebarAccessoryViewController ↔ NSButton retain cycle
    private weak var button: NSButton?

    /// V4.37.4: 通用初始化——双 SF Symbol + 可达性描述 + tooltip + action closure
    ///   inactiveSymbol: 默认状态 SF Symbol 名（如 "info.circle"）
    ///   activeSymbol: 激活状态 SF Symbol 名（如 "info.circle.fill"）
    ///   accessibilityLabel: VoiceOver 念出（必须）
    ///   tooltip: hover 显示（V4.37.4: 后续可由 setTooltip 动态更新）
    ///   onAction: 点击时调
    init(
        inactiveSymbol: String,
        activeSymbol: String,
        accessibilityLabel: String,
        tooltip: String,
        onAction: @escaping () -> Void
    ) {
        self.inactiveSymbol = inactiveSymbol
        self.activeSymbol = activeSymbol
        self.label = accessibilityLabel
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
        loadViewProgrammatically(tooltip: tooltip)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// V4.37.4: 手写 view 装载——NSTitlebarAccessoryViewController 通常配 NIB，但项目惯例
    /// 是手写（参考 ToolbarController.makeSimpleItem 手写 NSButton）
    /// V4.37.4: NSButton 直接作 view（删 V4.37.3 28×24 NSView container）
    ///   NSButton intrinsic size 由 bezel style + content 决定，与 Photos.app titlebar 按钮
    ///   实际尺寸一致（28×22pt 左右），无需硬编码
    private func loadViewProgrammatically(tooltip: String) {
        let button = NSButton()
        button.bezelStyle = .recessed  // V4.37.3: 与 NSToolbar 内 5 actions 视觉一致
        button.toolTip = tooltip
        button.target = self
        button.action = #selector(handleClick)
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateButtonImage()  // V4.37.4: 初始化时同步 icon
        self.button = button
        view = button
    }

    /// V4.37.4: 同步 icon + tint——所有 setActive 调用走这里
    ///   icon: inactiveSymbol ↔ activeSymbol（info.circle ↔ info.circle.fill）
    ///   tint: 系统默认（nil）↔ .controlAccentColor（强调色）
    private func updateButtonImage() {
        let symbol = isActive ? activeSymbol : inactiveSymbol
        button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        // V4.37.4: 激活时 tint 强调色（Photos.app 同款——按下时 ⓘ 变蓝）
        // nil = 系统默认（保持与 NSToolbar 5 actions 一致——它们也不主动 tint）
        button?.contentTintColor = isActive ? .controlAccentColor : nil
    }

    /// V4.37.4 NEW: 切换激活状态——Photos.app ⓘ 同款 toggle 视觉
    ///   ContentView 在 .onChange(of: showDetail) 调，外部真相源驱动
    ///   与 V4.36.x Filter 按钮 didSet → updateBadge 模式同思路
    ///   内部维护 isActive + 调 updateButtonImage 同步
    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        updateButtonImage()
    }

    /// V4.37.4 NEW: 动态更新 tooltip——V4.36.x Filter 按钮模式
    ///   "显示信息面板（⌘I）" / "隐藏信息面板（⌘I）" 反映当前状态
    ///   加 ⌘I 快捷键提示——用户 hover 看到快捷键发现性提升
    func setTooltip(_ tooltip: String) {
        button?.toolTip = tooltip
    }

    @objc private func handleClick() {
        onAction?()
    }
}
