//
//  PopoverChrome.swift
//  ImageGallery
//
//  V4.80.0 NEW: 抽 NSVisualEffectView transl 范式为 static helper
//    解决 2 处 inline 重复（FilterPopoverViewController + ViewOptionsPopoverHostController）
//    为 Phase 1-4 FilterPopover 拆 2 层重构预备
//
//  V4.45.0 + V4.47.0 + V4.67.0 + V4.77.0 精修 transl 范式：
//    - material = .popover       // macOS popover 专用材质
//    - state = .followsWindowActiveState  // 跟窗口 active 状态走
//    - blendingMode = .withinWindow       // 暗色下不"闷"
//    - 12pt 圆角（V4.67.0 范式）
//    - 0.5pt NSColor.separatorColor hairline（V4.67.0 dark mode 强化）
//
//  Why 抽 helper：
//    - FilterPopoverViewController L102-112 + ViewOptionsPopoverHostController L53-62 完全重复
//    - Phase 2+ 拆 2 层 popover 还需要 4 个二级 popover——5 处复制粘贴不管理
//    - helper 内部 token 化（V4.79.0 hostCornerRadius/hostBorderWidth）——token 化是设计语言
//

import AppKit

extension NSVisualEffectView {
    /// V4.80.0: popover transl host 视觉范式——返回配置好的 NSVisualEffectView
    ///   使用方式：
    ///   ```swift
    ///   let host = NSVisualEffectView.popoverHost()
    ///   host.addSubview(contentView)
    ///   // 设约束 fill host
    ///   self.view = host
    ///   ```
    ///   与 V4.45.0 FilterPopoverViewController + V4.77.0 ViewOptionsPopoverHostController 完全一致
    static func popoverHost() -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.state = .followsWindowActiveState
        v.blendingMode = .withinWindow
        v.wantsLayer = true
        v.layer?.cornerRadius = PopoverStyle.hostCornerRadius  // 12pt
        v.layer?.borderWidth = PopoverStyle.hostBorderWidth  // 0.5pt
        v.layer?.borderColor = NSColor.separatorColor.cgColor
        return v
    }
}
