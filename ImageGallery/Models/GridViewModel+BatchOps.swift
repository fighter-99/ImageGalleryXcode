import SwiftUI
import os

extension GridViewModel {
    // MARK: - 批量 + Trash 操作

    /// V4.1.0 l: 切换侧栏 section 时清选中
    func clearSelectionOnFilterChange() {
        if !selection.isEmpty {
            selection = .empty
        }
    }

    /// V3.6: 删除单张 = 移到回收站
    /// V6.29.1: undo = restore from trash (Photos.app 撤销范式)
    func deleteSinglePhoto() {
        guard let photo = singleSelectedPhoto else { return }
        let count = performOnSelectedTrash({ svc, photos in svc.recycle(photos[0]) })
        guard count > 0 else { return }
        NotificationCenter.default.post(name: .gridModelDidChange, object: nil)
        let capturedPhoto = photo
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            guard let modelContext = self.core?.modelContext else { return }
            RecycleBinService(storage: .shared, modelContext: modelContext).restore(capturedPhoto)
        }
        // 同步: undoManager push + toast undoAction (⌘Z + 点 [撤销] 都能恢复)
        undoManager.registerUndoOnly(description: Copy.undoDeleteOne, undo: undo)
        enqueueToastHandler(
            Copy.movedToRecycleBin(1, retentionDays: settings.trashRetentionDays),
            .info,
            .normal,
            undo
        )
    }

    /// V3.6: 批量删除
    /// V6.29.1: undo = 全部 restore from trash (Photos.app 撤销范式)
    func batchDelete() {
        // 提前 capture photos (performOnSelectedTrash 会清 selection)
        let photos = selectedPhotosInVisible
        guard !photos.isEmpty else { return }
        let count = performOnSelectedTrash({ svc, photos in photos.forEach { svc.recycle($0) } })
        guard count > 0 else { return }
        NotificationCenter.default.post(name: .gridModelDidChange, object: nil)
        let capturedPhotos = photos
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            guard let modelContext = self.core?.modelContext else { return }
            let service = RecycleBinService(storage: .shared, modelContext: modelContext)
            for photo in capturedPhotos {
                service.restore(photo)
            }
            self.enqueueToastHandler(Copy.toastRestored(capturedPhotos.count), .success, .normal, nil)
        }
        // 同步: undoManager push + toast undoAction
        undoManager.registerUndoOnly(description: Copy.undoDeleteMany(count), undo: undo)
        enqueueToastHandler(
            Copy.toastMovedToRecycleBinCount(count),
            .info,
            .normal,
            undo
        )
    }

    /// 批量移动到文件夹
    ///
    /// V6.14.10: 恢复 `undoManager.registerAction` — UndoManager 重做 (自写 stack, 避开
    ///   Foundation.UndoManager 的 run loop 交互死锁)。V6.14.4 砍, V6.14.10 拿回来。
    ///   闭包用 `[weak self]` 避免 ContentViewModel 强引用环 (cycle 仍存在
    ///   undoStack 持 entry, entry 持闭包, 但 self 是 weak → self 释放时闭包失效,
    ///   undo 调用时不做事不崩)。
    func batchMove(to folder: Folder?) {
        let photosToMove = selectedPhotosInVisible
        guard !photosToMove.isEmpty, let modelContext = core?.modelContext else { return }
        let oldFolders = photosToMove.map { $0.folder }
        let count = photosToMove.count
        let folderName = folder?.name ?? Copy.folderNameUnfiledFallback

        // V6.36.3: coalesceId="move" — 1s 内连续 batchMove 合并 (Photos.app 行为)
        undoManager.registerAction(
            description: Copy.undoMoveToFolder(count, folderName: folderName),
            action: { [weak self] in
                for photo in photosToMove {
                    photo.folder = folder
                }
                modelContext.saveWithLog()
                self?.selection = .empty
            },
            undo: { [weak self] in
                for (photo, oldFolder) in zip(photosToMove, oldFolders) {
                    photo.folder = oldFolder
                }
                modelContext.saveWithLog()
                _ = self  // 强引用 self 进闭包, 防止 self 释放时 undo 操作失败
            },
            coalesceId: "move"
        )
    }

    /// 批量加标签
    func batchAddTag(_ tag: Tag) {
        let photosToTag = selectedPhotosInVisible
        guard let modelContext = core?.modelContext else { return }
        for photo in photosToTag {
            if !photo.tags.contains(where: { $0.id == tag.id }) {
                photo.tags.append(tag)
            }
        }
        modelContext.saveWithLog()
    }

}
