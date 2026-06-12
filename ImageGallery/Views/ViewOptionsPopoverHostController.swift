//
//  ViewOptionsPopoverHostController.swift
//  ImageGallery
//
//  V4.77.0 NEW: ViewOptionsPopover 改 NSVisualEffectView transl 范式
//    仿 V4.45.0 + V4.47.0 FilterPopover 范式
//    让 ViewOptionsPopover 与 FilterPopover transl 行为完全一致
//
//  V4.9.1 之前用 NSPopover + NSHostingController + .background(.clear)
//    SwiftUI 视图背景透明让 NSPopover 自动应用 transl material
//    但 transl 行为与 NSVisualEffectView 不同（背景透明度不一致——用户反馈）
//
//  V4.77.0 修法：NSViewController 子类 + NSVisualEffectView 包 SwiftUI 视图
//    完全控制 transl 行为 + 12pt 圆角 + edge hairline（与 FilterPopover 一致）
//
//  关键设计：
//  - NSVisualEffectView(.popover) + .followsWindowActiveState + .withinWindow
//  - 12pt 圆角（仿 V4.67.0 范式）
//  - 0.5pt NSColor.separatorColor hairline（dark mode 边界强化）
//  - 直接 addArrangedSubview 内部 SwiftUI hosting view
//  - preferredContentSize 由 NSPopover 协商——set in init
//

import AppKit
import SwiftUI

/// V4.77.0: ViewOptionsPopover transl 统一 host controller
///   完全仿 V4.45.0 + V4.47.0 + V4.67.0 FilterPopoverViewController 范式
@MainActor
final class ViewOptionsPopoverHostController: NSViewController {
    /// SwiftUI 视图包装
    private let hostingView: NSHostingView<AnyView>

    /// V4.77.0: preferredContentSize——NSPopover 用这个值确定 popover 大小
    ///   AppKit 直接读，不走 SwiftUI intrinsic size 协商
    ///   高度 380pt = 3 段（视图 50pt + 缩放 90pt + 排序 200pt + padding）
    private static let preferredWidth: CGFloat = 240
    private static let preferredHeight: CGFloat = 380

    /// V4.77.0: 接收 SwiftUI 视图——init 时 capture，loadView 时 addSubview
    init<Content: View>(swiftUIView: Content) {
        self.hostingView = NSHostingView(rootView: AnyView(swiftUIView))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override func loadView() {
        // V4.77.0: NSVisualEffectView 包裹——与 FilterPopover 完全一致
        //   material = .popover       // macOS popover 专用材质
        //   state = .followsWindowActiveState  // 跟窗口 active 状态走
        //   blendingMode = .withinWindow       // 暗色下不"闷"
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .followsWindowActiveState
        visualEffect.blendingMode = .withinWindow

        // V4.77.0: 12pt 圆角 + 0.5pt hairline（仿 V4.67.0 范式）
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.separatorColor.cgColor

        // V4.77.0: hostingView 加入——直接 addSubview
        //   与 FilterPopover outer.addArrangedSubview 模式一致
        //   SwiftUI hosting view 自动 fill 容器
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        self.view = visualEffect
    }

    /// V4.77.0: 显式设 preferredContentSize——NSPopover 读这个值
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(
            width: Self.preferredWidth,
            height: Self.preferredHeight
        )
    }
}
