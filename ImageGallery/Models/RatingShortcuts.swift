//
//  RatingShortcuts.swift
//  ImageGallery
//
//  V5.13：⌘0-⌘5 评分快捷键的路由表——纯数据，测试不需 SwiftUI。
//  ContentKeyboardShortcuts 用此表生成 6 个隐藏 Button。
//
//  // TODO V5.14：⌘1/⌘3/⌘4/⌘5 与 sidebar 快捷键有潜在冲突（plan agent 标记 latent bug，本次不修）
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
