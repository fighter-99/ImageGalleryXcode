//
//  ImageGalleryUndoManager.swift
//  ImageGallery
//
//  V3.5 Phase 1 Step 4：撤销/重做管理器。
//  V3.6：删除走回收站（RecycleBinService），撤销管理器只服务于其他写操作。
//
//  设计要点：
//  - 基于 Foundation UndoManager
//  - 使用 Swift 5.9+ @Observable（自动观察）
//  - 写操作（移动/打标签/重命名等）前调用 registerAction
//  - 工具栏 ↶ / ↷ 按钮观察 canUndo / canRedo
//
//  V3.6 之后支持的撤销操作：
//  - 重命名
//  - 打标签
//  - 收藏切换
//  - 移动到文件夹
//
//  V3.6 不再支持（被回收站取代）：
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

    private let undoManager = UndoManager()

    init() {
        undoManager.levelsOfUndo = 50  // 最多保留 50 步
        undoManager.groupsByEvent = false
        updateState()
    }

    /// 执行操作并注册撤销（核心 API）
    /// - Parameters:
    ///   - description: 操作描述（显示在工具栏 tooltip）
    ///   - action: 实际执行的操作
    ///   - undo: 反向操作（撤销时执行）
    func registerAction(
        description: String,
        action: @escaping () -> Void,
        undo: @escaping () -> Void
    ) {
        // 注册反向操作
        undoManager.registerUndo(withTarget: self) { manager in
            undo()
            // 注册 redo：执行原 action
            manager.undoManager.registerUndo(withTarget: manager) { manager2 in
                action()
                manager2.registerAction(description: description, action: action, undo: undo)
            }
        }
        undoManager.setActionName(description)

        // 执行实际操作
        action()

        updateState()
    }

    /// 撤销
    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        updateState()
    }

    /// 重做
    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        updateState()
    }

    // 更新发布状态
    private func updateState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
        undoDescription = undoManager.undoActionName
        redoDescription = undoManager.redoActionName
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
