//
//  ImageGalleryUndoManager.swift
//  ImageGallery
//
//  V3.5 Phase 1 Step 4：撤销/重做管理器。
//  V3.6：删除走回收站（RecycleBinService），撤销管理器只服务于其他写操作。
//
//  V6.14.10：重做 — 不用 Foundation.UndoManager, 改自写 stack
//    原因: V6.14.4 发现 Foundation.UndoManager.registerUndo(withTarget:) 跟 Swift Testing
//    @MainActor + ModelContainer + run loop 组合死锁 (BatchTests 60s+ 超时)
//    自写 stack 避开 run loop 交互 (Foundation.UndoManager 观察主 run loop 的
//    NSWindowWillClose / NSWindowDidResignKey notifications, 测试环境不跑这个循环 → 死锁)
//
//  设计要点：
//  - 自写 [Entry] undo/redo stack, 50 步限制
//  - @MainActor + @Observable (同 V3.5)
//  - API 跟旧版兼容: registerAction / undo / redo / canUndo / canRedo / 描述
//  - 接受调用方传 action + undo 闭包, 不强捕获 self (调用方用 [weak self])
//
//  当前支持的撤销操作：
//  - 重命名
//  - 打标签
//  - 收藏切换
//  - 移动到文件夹 (V6.14.10 恢复 batchMove / performMove undo)
//
//  当前不支持（被回收站取代）：
//  - 删除照片（→ 移到回收站；恢复从回收站恢复）
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class ImageGalleryUndoManager {
    // UndoManager 状态（@Observable 自动追踪）
    private(set) var canUndo: Bool = false
    private(set) var canRedo: Bool = false
    private(set) var undoDescription: String = ""
    private(set) var redoDescription: String = ""

    // V6.14.10: 自写 stack, 不用 Foundation.UndoManager
    //   entry 持 3 个闭包: 描述 + undo + redo
    //   强引用环仍存在 (caller 闭包可能捕获 self), 但 50 步上限, 不无限增长
    //   关键差异: 无 run loop 交互, 测试环境不卡
    private struct Entry {
        let description: String
        let undo: () -> Void
        let redo: () -> Void
    }
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private let maxLevels: Int = 50

    init() {
        updateState()
    }

    /// 执行操作并注册撤销（核心 API）
    /// - Parameters:
    ///   - description: 操作描述（显示在工具栏 tooltip）
    ///   - action: 实际执行的操作
    ///   - undo: 反向操作（撤销时执行）
    ///
    /// **V6.14.10 注意**: 调用方应使用 `[weak self]` 捕获 self, 避免强引用环。
    ///   旧版 Foundation.UndoManager 也有这问题, 但加上 run loop 交互 → 死锁。
    ///   新版无 run loop 交互, 但 retain cycle 仍存在 (测试内存会涨, 50 步上限安全)。
    func registerAction(
        description: String,
        action: @escaping () -> Void,
        undo: @escaping () -> Void
    ) {
        let entry = Entry(description: description, undo: undo, redo: action)
        undoStack.append(entry)
        if undoStack.count > maxLevels {
            undoStack.removeFirst()
        }
        // 任何新 action 清空 redo stack (标准 undo 行为)
        redoStack.removeAll()

        // 执行实际操作
        action()

        updateState()
    }

    /// 撤销
    func undo() {
        guard let entry = undoStack.popLast() else { return }
        entry.undo()
        redoStack.append(entry)
        if redoStack.count > maxLevels {
            redoStack.removeFirst()
        }
        updateState()
    }

    /// 重做
    func redo() {
        guard let entry = redoStack.popLast() else { return }
        entry.redo()
        undoStack.append(entry)
        if undoStack.count > maxLevels {
            undoStack.removeFirst()
        }
        updateState()
    }

    /// 清空 (app 关闭 / 重置状态时调)
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateState()
    }

    // 更新发布状态
    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        undoDescription = undoStack.last?.description ?? ""
        redoDescription = redoStack.last?.description ?? ""
    }
}

// MARK: - SwiftUI Environment 集成

/// 让任何子 View 通过 @Environment 拿到 undoManager
/// （V3.5 Phase 2：被 DetailView 的"添加/移除标签"、"重命名" 撤销逻辑使用）
private struct UndoManagerEnvironmentKey: EnvironmentKey {
    @MainActor static let defaultValue: ImageGalleryUndoManager? = nil
}

extension EnvironmentValues {
    /// 撤销/重做管理器（可选，调用前需检查 nil）
    var undoManager: ImageGalleryUndoManager? {
        get { self[UndoManagerEnvironmentKey.self] }
        set { self[UndoManagerEnvironmentKey.self] = newValue }
    }
}

// MARK: - FocusedValue 桥接（V4.7.0 NEW：让 Edit menu commands 访问 undoManager）
//
// SwiftUI commands 修饰符在 Scene 层级运行，无法直接拿到 ContentView 的 @State undoManager。
// 用 FocusedValue 桥接：
// - ContentView 用 .focusedSceneValue(\.imageGalleryUndoManager, undoManager) 暴露
// - ImageGalleryApp.commands 用 @FocusedValue(\.imageGalleryUndoManager) 接收
//
// 为什么用 .focusedSceneValue 而非 .focusedValue：
// - .focusedValue 跟随当前 focus（如 TextField 焦点），focus 切走时 key 失效
// - .focusedSceneValue 跟随 window scene，undoManager 是 window 级状态，
//   跨 focus 都应可用（如用户在搜索框输入时也能 ⌘Z 撤销）
//
// 重新刷新的机制：ContentView @State undoManager 改变时（@Observable 自动追踪
// canUndo/canRedo/undoDescription），View 重渲染，.focusedSceneValue 重新应用，
// commands 里的 @FocusedValue 也跟随更新——菜单 label 和 disabled 状态实时联动。
//
struct ImageGalleryUndoManagerFocusedValueKey: FocusedValueKey {
    typealias Value = ImageGalleryUndoManager
}

extension FocusedValues {
    /// 撤销/重做管理器（commands 用）——V4.7.0 NEW
    ///
    /// 在 ContentView 用 `.focusedSceneValue(\.imageGalleryUndoManager, undoManager)` 暴露
    /// 在 commands 用 `@FocusedValue(\.imageGalleryUndoManager) var undoManager` 接收
    var imageGalleryUndoManager: ImageGalleryUndoManager? {
        get { self[ImageGalleryUndoManagerFocusedValueKey.self] }
        set { self[ImageGalleryUndoManagerFocusedValueKey.self] = newValue }
    }
}

// MARK: - V4.7.0 NEW: ContentView body 辅助 modifier
//
// 把 .focusedSceneValue 抽到独立 extension 避免 ContentView body 链过长
// 触发 SwiftUI type-check 超时（V3.6.17/6.23 教训——body 临界点 ~200 行）
//
// 用法：在 ContentView body 链里加 `.exposeUndoManager(undoManager)`
// 等价于 `.focusedSceneValue(\.imageGalleryUndoManager, undoManager)`
//
extension View {
    /// V4.7.0: 暴露 undoManager 给 Edit menu commands
    /// - Parameter manager: ContentView 持有的 ImageGalleryUndoManager 实例
    /// - Returns: view 修饰了 .focusedSceneValue(\.imageGalleryUndoManager, manager) 的版本
    func exposeUndoManager(_ manager: ImageGalleryUndoManager) -> some View {
        focusedSceneValue(\.imageGalleryUndoManager, manager)
    }
}
