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
import SwiftData
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

// MARK: - PhotoSnapshot（撤销用的数据快照）

/// 照片数据的不可变快照，用于撤销删除等操作
struct PhotoSnapshot {
    let id: UUID
    let filename: String
    let fileURL: URL
    let importedAt: Date
    let fileSize: Int64
    let width: Int
    let height: Int
    let isFavorite: Bool
    let note: String
    let fileHash: String?
    let folderID: UUID?
    let tagIDs: [UUID]

    init(photo: Photo) {
        self.id = photo.id
        self.filename = photo.filename
        self.fileURL = photo.fileURL
        self.importedAt = photo.importedAt
        self.fileSize = photo.fileSize
        self.width = photo.width
        self.height = photo.height
        self.isFavorite = photo.isFavorite
        self.note = photo.note
        self.fileHash = photo.fileHash
        self.folderID = photo.folder?.id
        self.tagIDs = photo.tags.map { $0.id }
    }

    /// 在指定 ModelContext 中重建 Photo
    @MainActor
    func restore(in context: ModelContext) {
        let photo = Photo(
            filename: filename,
            fileURL: fileURL,
            fileSize: fileSize,
            width: width,
            height: height
        )
        photo.id = id
        photo.importedAt = importedAt
        photo.isFavorite = isFavorite
        photo.note = note
        photo.fileHash = fileHash

        // 恢复文件夹关联
        if let folderID = folderID {
            let descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.id == folderID })
            photo.folder = try? context.fetch(descriptor).first
        }

        // 恢复标签关联
        for tagID in tagIDs {
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == tagID })
            if let tag = try? context.fetch(descriptor).first {
                photo.tags.append(tag)
            }
        }

        context.insert(photo)
    }
}

// MARK: - SwiftUI Environment 集成

/// 让任何子 View 通过 @Environment 拿到 undoManager
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
