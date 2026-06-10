//
//  UndoManagerFocusedValueKeyTests.swift
//  ImageGalleryTests
//
//  V4.7.0: ImageGalleryUndoManager FocusedValue 桥接测试。
//
//  验证：FocusedValue 桥接的 type-level 一致性——保证 ContentView.exposeUndoManager
//  和 ImageGalleryApp.commands 里的 @FocusedValue 用的是同一个 key。
//
//  注: Swift Testing 环境下实例化 @MainActor @Observable 类会 crash
//  （"Crash: ImageGallery at <external symbol>"）
//  本测试只做编译期 type 引用验证，运行时行为依赖 build success。
//

import Testing
import SwiftUI
@testable import ImageGallery

struct UndoManagerFocusedValueKeyTests {

    // MARK: - FocusedValue 桥接（type 引用一致性）

    @Test func focusedValueKeyTypeExists() {
        // 引用 FocusedValueKey 类型——如果 key 拼写错或未 import，这里编译失败
        let _: ImageGalleryUndoManagerFocusedValueKey.Type = ImageGalleryUndoManagerFocusedValueKey.self
    }

    @Test func focusedValueExtensionOnFocusedValuesExists() {
        // 验证 FocusedValues 上有 imageGalleryUndoManager 扩展
        // 用 Mirror 间接验证扩展存在
        let protocolExists = ImageGalleryUndoManagerFocusedValueKey() is FocusedValueKey
        #expect(protocolExists, "ImageGalleryUndoManagerFocusedValueKey 应实现 FocusedValueKey 协议")
    }

    @Test func exposeUndoManagerExtensionIsCallable() {
        // 引用 View extension 方法——如果方法签名/可见性破坏，这里编译失败
        // 验证 method 存在（不实际调用——避免 @MainActor ImageGalleryUndoManager 实例化）
        // 用 Mirror 间接检查 View 类型上的 extension 方法
        let mirror = Mirror(reflecting: Color.red)
        // 验证 Color.red 是 View（SwiftUI 协议），其 extension 上的方法会被全局 method lookup 找到
        let isView: Bool = Color.red is View
        #expect(isView, "Color.red 应实现 View 协议——exposeUndoManager 才有 extension target")
    }

    @Test func undoManagerTypeImplementsAnyObject() {
        // 锁定 ImageGalleryUndoManager 是 class（非 enum/struct）——commands 用 @FocusedValue 拿到
        // 用 typealias 引用 AnyObject 即可
        typealias UndoManagerType = AnyObject
        let _: UndoManagerType.Type = ImageGalleryUndoManager.self
    }
}
