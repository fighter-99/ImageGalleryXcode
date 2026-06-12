//
//  RatingShortcuts.swift
//  ImageGallery
//
//  V5.13：⌘0-⌘5 评分快捷键的路由表——纯数据，测试不需 SwiftUI。
//  ContentKeyboardShortcuts 用此表生成 6 个隐藏 Button。
//
//  V5.15：⌘1-6 sidebar smart folder 快捷键已删（ContentKeyboardShortcuts.swift:59-75）
//    ⌘0-5 独占 rating 快捷键，无冲突
//
//  V5.13.1：用 SwiftUI 的 KeyEquivalent + EventModifiers（不引 NSEvent）保持 .keyboardShortcut 调用 0 转换
//

import SwiftUI

enum RatingShortcuts {
    /// ⌘0 清除评分 + ⌘1-⌘5 设为 N 星（仿 macOS Photos 标准）
    static let routes: [(key: KeyEquivalent, modifiers: EventModifiers, rating: Int)] = [
        (KeyEquivalent("0"), .command, 0),
        (KeyEquivalent("1"), .command, 1),
        (KeyEquivalent("2"), .command, 2),
        (KeyEquivalent("3"), .command, 3),
        (KeyEquivalent("4"), .command, 4),
        (KeyEquivalent("5"), .command, 5)
    ]
}
