//
//  ContentView+SettingsChrome.swift
//  ImageGallery
//
//  V5.51-2: 从 ContentView.swift 抽出 applySettingsChrome modifier
//  原位置 ContentView.swift:1674-1689
//  V3.5.18 引入，V4.13.0 简化撤回 onOpenSettings/showSettings 参数
//

import SwiftUI

// MARK: - V3.5.18：设置面板 chrome helper
//
// V4.13.0: 撤回 onOpenSettings + showSettings 参数——⌘, 现在走 Settings scene
//   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 路径
//   简化后只应用强调色（.tint + .environment(\.appAccent)）
//
// 抽出 modifier 到独立 generic extension，避免 body 链超长触发
// Swift 编译器的 "unable to type-check this expression in reasonable time" 错误。
// 同样模式可复用：任何"挂在已有视图链尾端"的 modifier 都能用此技巧。
extension View {
    func applySettingsChrome(tintColor: Color) -> some View {
        self
            .tint(tintColor)
            .environment(\.appAccent, tintColor)
    }
}
