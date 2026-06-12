//
//  VisualEffectMaterial.swift
//  ImageGallery
//
//  V4.57.0 NEW: SwiftUI wrapper for NSVisualEffectView
//    仿 V4.45.0 popover transl material 范式
//    Photos.app 风格——chrome 浮动在大图上, transl material 让背景色透过来
//
//  V4.45.0 范式（已 FilterPopover 验证）：
//    - material = .popover       // macOS 专门为 popover 设计的材质
//    - state = .followsWindowActiveState  // 跟窗口 active 状态走
//    - blendingMode = .withinWindow  // 暗色下不"闷" (V4.47.0 修复)
//
//  用途：ImmersivePhotoView 顶部/底部 chrome 升级 transl material pill
//    之前是 LinearGradient 渐变带（黑色 60% → 透明）
//    现在是 NSVisualEffectView .popover 胶囊——macOS Photos 实际风格
//
//  Why NSViewRepresentable 而非 SwiftUI .background(Material)：
//    - SwiftUI 14+ Material 是 .regular/.thin/.thick/.ultraThin/.ultraThick/.bar
//    - **没有 .popover 类型**（V4.45.0 时已确认）
//    - 且 SwiftUI Material 无法控制 .followsWindowActiveState / .withinWindow
//    - NSVisualEffectView 才能实现 Photos 风格 transl 效果
//
//  踩坑（V4.45.0 验证）：
//    - NSVisualEffectView 没有 contentView 属性——直接 addSubview 即可
//    - state 实际是 .followsWindowActiveState（camelCase）而非 .followWindow
//    - blendingMode 二选一：.behindWindow 受窗口内容色偏；.withinWindow 独立 blend
//

import SwiftUI
import AppKit

/// V4.57.0: NSVisualEffectView SwiftUI 桥
///   仿 V4.45.0 + V4.47.0 popover transl material 范式
///   默认值与 V4.45.0 验证通过的 FilterPopover 设置一致
struct VisualEffectMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let state: NSVisualEffectView.State
    let blendingMode: NSVisualEffectView.BlendingMode

    init(
        material: NSVisualEffectView.Material = .popover,
        state: NSVisualEffectView.State = .followsWindowActiveState,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    ) {
        self.material = material
        self.state = state
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = state
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = state
        nsView.blendingMode = blendingMode
    }
}
