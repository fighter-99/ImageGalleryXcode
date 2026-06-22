import Foundation
import SwiftUI
import SwiftData
import os

extension GridViewModel {
    // MARK: - P4.2: 批量重命名
    /// 模板: {n} {n:N} {originalName} (见 BatchRenameTemplate)
    /// - 规划阶段: prepareRenamePlans 渲染 + 去重 (within-batch + on-disk 双层)
    /// - 执行阶段: executeRenamePlans 走 undoManager.registerAction, 单步撤销整批
    /// - 错误处理: per-photo try, 失败计数, 单次 toast 汇总 (V6.08 教训: 不静默)
    /// V6.67 (Q2 god method 拆分): 拆成 prepareRenamePlans + executeRenamePlans,
    ///   batchRename 主体从 125 行 → 22 行 (只有 wiring), 2 helper 各 30-50 行
    func batchRename(template: String) {
        let photos = selectedPhotosInVisible
        guard !photos.isEmpty, let modelContext = core?.modelContext else { return }
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // 规划阶段: 渲染 + 去重 + 收集 Plan
        guard let result = prepareRenamePlans(template: trimmed, photos: photos) else { return }
        // 执行阶段: 注册 undoManager action + 弹 toast
        executeRenamePlans(plans: result.plans, collisionCount: result.collisionCount, modelContext: modelContext)
    }

    /// V6.67 (Q2): 批量重命名 — 规划阶段
    /// - 渲染 template + within-batch uniquify + on-disk collision check
    /// - V6.58 (audit P1.4): 撞名 _1.._9999 耗尽 → collisionCount++, 跳过这条 (其他 photo 仍 rename)
    /// - 返回 nil 表示没有可执行 plan (空 selection 或 template 全 fail)
    private func prepareRenamePlans(template: String, photos: [Photo]) -> (plans: [RenamePlan], collisionCount: Int)? {
        var collisionCount = 0
        var plans: [RenamePlan] = []
        var reserved = Set<String>()

        for (i, photo) in photos.enumerated() {
            let oldURL = photo.fileURL
            let oldFilename = photo.filename
            let ext = oldURL.pathExtension
            let originalBase = oldURL.deletingPathExtension().lastPathComponent

            // 1) render
            guard let rendered = try? BatchRenameTemplate.render(
                template: template, index: i + 1, totalCount: photos.count,
                originalFilename: originalBase
            ) else { continue }

            // 2) skip self-rename (template produces same name as original)
            if rendered == originalBase && ext == oldURL.pathExtension {
                reserved.insert("\(rendered).\(ext)")
                continue
            }

            // 3) uniquify (within-batch + on-disk)
            // V6.58 (audit P1.4): uniquify 现在 throws tooManyCollisions (极端 adversarial case)
            //   撞名 _1.._9999 都耗尽 → 跳过这条 (其他 photo 仍 rename), 弹 toast 告知用户
            let uniquifyResult: (baseName: String, ext: String)
            do {
                uniquifyResult = try BatchRenameTemplate.uniquify(
                    baseName: rendered, ext: ext, existingReserved: reserved,
                    onDiskCheck: { name in
                        let candidateURL = oldURL.deletingLastPathComponent()
                            .appendingPathComponent(name)
                        return FileManager.default.fileExists(atPath: candidateURL.path)
                    }
                )
            } catch BatchRenameTemplate.BatchRenameError.tooManyCollisions {
                collisionCount += 1
                continue
            } catch {
                // 其他 BatchRenameError (例如 unexpected 内部错误) — 跳过这条
                collisionCount += 1
                continue
            }
            let (finalBase, finalExt) = uniquifyResult
            reserved.insert("\(finalBase).\(finalExt)")
            plans.append(RenamePlan(
                photo: photo, oldURL: oldURL, oldFilename: oldFilename,
                newBase: finalBase, newExt: finalExt
            ))
        }
        guard !plans.isEmpty else { return nil }
        return (plans, collisionCount)
    }

    /// V6.67 (Q2): 批量重命名 — 执行阶段
    /// - 走 undoManager.registerAction, coalesceId="rename" 合并连续操作
    /// - per-photo try, 失败计数, 单次 toast 汇总
    private func executeRenamePlans(plans: [RenamePlan], collisionCount: Int, modelContext: ModelContext) {
        let count = plans.count
        // V6.36.3: coalesceId="rename" — 1s 内连续 batchRename 合并
        //   用 labeled closure 参数 (action/undo 显式 label) — coalesceId 必须在末位
        //   trailing closure 语法只能用在最后一个 closure 参数, 多个 closure 必须 labeled
        undoManager.registerAction(
            description: Copy.undoBatchRename(count),
            action: { [weak self] in
                var errors = 0
                for p in plans {
                    let newURL = p.oldURL.deletingLastPathComponent()
                        .appendingPathComponent("\(p.newBase).\(p.newExt)")
                    do {
                        try FileManager.default.moveItem(at: p.oldURL, to: newURL)
                        p.photo.filename = "\(p.newBase).\(p.newExt)"
                        p.photo.fileURL = newURL
                    } catch {
                        Logger.imageIO.error("batchRename 失败: \(p.oldURL.lastPathComponent, privacy: .public) → \(newURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                        errors += 1
                    }
                }
                modelContext.saveWithLog()
                // V6.58 (audit P1.4): 报告 collisionCount (极端撞名 _1.._9999 耗尽)
                //   加在 errors 之前, 区分 "重命名失败" vs "找不到 unique 名字"
                if collisionCount > 0 {
                    self?.enqueueToastHandler(Copy.toastBatchRenameCollisions(collisionCount), .warning, .long, nil)
                }
                if errors > 0 {
                    self?.enqueueToastHandler(Copy.toastBatchRenamePartialFail(errors), .error, .long, nil)
                } else if collisionCount == 0 {
                    self?.enqueueToastHandler(Copy.toastBatchRenameSuccess(count), .success, .long, nil)
                }
                _ = self
            },
            undo: { [weak self] in
                var undoErrors = 0
                for p in plans.reversed() {
                    let newURL = p.oldURL.deletingLastPathComponent()
                        .appendingPathComponent("\(p.newBase).\(p.newExt)")
                    do {
                        try FileManager.default.moveItem(at: newURL, to: p.oldURL)
                        p.photo.filename = p.oldFilename
                        p.photo.fileURL = p.oldURL
                    } catch {
                        Logger.imageIO.error("batchRename undo 失败: \(newURL.lastPathComponent, privacy: .public) → \(p.oldURL.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                        undoErrors += 1
                    }
                }
                modelContext.saveWithLog()
                if undoErrors > 0 {
                    self?.enqueueToastHandler(Copy.toastBatchRenameUndoPartialFail(undoErrors), .error, .long, nil)
                }
                _ = self
            },
            coalesceId: "rename"
        )
    }

    /// V6.67 (Q2): RenamePlan — 改名方案 (extracted from local struct in batchRename V6.58)
    /// 提到 file-scope 让 helper method 也能用
    private struct RenamePlan {
        let photo: Photo
        let oldURL: URL
        let oldFilename: String
        let newBase: String
        let newExt: String
    }

    /// V5.12: 批量评分
    /// V6.35.3: 加 undo + coalesceId="rate" — 1s 内连续评分合并 (Photos.app 行为)
    func batchSetRating(_ rating: Int) {
        let photosToRate = selectedPhotosInVisible
        guard !photosToRate.isEmpty, let modelContext = core?.modelContext else { return }
        // V6.35.3: capture 原 rating — undo 还原用
        let originalRatings = photosToRate.map { $0.rating }
        BatchSetRatingMath.applyRating(rating, count: photosToRate.count) { index, r in
            photosToRate[index].rating = r
        }
        modelContext.saveWithLog { [weak self] _ in
            self?.enqueueToastHandler("批量评分失败", .error, .long, nil)
        }
        // V6.35.3: register undo (coalesceId="rate" — 1s 窗合并连续评分)
        let capturedPhotos = photosToRate
        let capturedOriginals = originalRatings
        let capturedRating = rating
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            for (index, photo) in capturedPhotos.enumerated() where index < capturedOriginals.count {
                photo.rating = capturedOriginals[index]
            }
            if let modelContext = self.core?.modelContext {
                modelContext.saveWithLog { _ in }
            }
        }
        undoManager.registerUndoOnly(description: Copy.undoRate(rating), undo: undo, coalesceId: "rate")
    }

    /// 批量导出
    /// V6.67 (Q2 god method 拆分): 拆成 runExportPanel + executeExportCopy,
    ///   batchExport 主体从 33 行 → 11 行 (只有 wiring), 2 helper 各 10-15 行
    func batchExport() {
        let photosToExport = selectedPhotosInVisible
        guard !photosToExport.isEmpty else { return }
        // 1) 弹目录选择 panel
        guard let destDir = runExportPanel() else { return }
        // 2) copy 每张照片 + toast 汇总
        executeExportCopy(photos: photosToExport, destDir: destDir)
    }

    /// V6.67 (Q2): 弹 NSOpenPanel 让用户选导出目录
    /// - 返回 nil 表示用户取消
    /// - canChooseDirectories + canCreateDirectories: macOS 标准 export panel
    private func runExportPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = Copy.exportPanelTitle
        panel.prompt = "导出"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// V6.67 (Q2): 实际 copy 文件到 destDir
    /// - per-photo try, 失败 toast (单 photo), 成功累计 successCount
    /// - 末尾弹汇总 toast
    private func executeExportCopy(photos: [Photo], destDir: URL) {
        var successCount = 0
        for photo in photos {
            let destURL = destDir.appendingPathComponent(photo.filename)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let uniqueDest = uniqueDestinationForBatchExport(for: destURL)
                    try FileManager.default.copyItem(at: photo.fileURL, to: uniqueDest)
                } else {
                    try FileManager.default.copyItem(at: photo.fileURL, to: destURL)
                }
                successCount += 1
            } catch {
                enqueueToastHandler("导出失败：\(photo.filename)", .error, .long, nil)
            }
        }
        if successCount > 0 {
            enqueueToastHandler("已导出 \(successCount) 张图片", .success, .normal, nil)
        }
    }

    /// 避免导出时文件名冲突
    func uniqueDestinationForBatchExport(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        while true {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let candidate = dir.appendingPathComponent(newName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    /// 在 visiblePhotos ∩ selectedIDs 上执行 trash 操作
    /// V5.13: 注入 onError
    /// V6.29.1: 不显示 toast, 由 caller 自己决定 (e.g. batchDelete 走 undo toast, permanentDeleteSelected 走普通 toast)
    ///   返回操作的照片数 (caller 用来生成 toast message / undo description)
    @discardableResult
    func performOnSelectedTrash(
        _ operation: (RecycleBinService, [Photo]) -> Void
    ) -> Int {
        let photos = selectedPhotosInVisible
        guard !photos.isEmpty, let modelContext = core?.modelContext else { return 0 }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [weak self] error in
                self?.enqueueToastHandler(
                    Copy.recycleBinOperationFailed(error.localizedDescription),
                    .error,
                    .long
                , nil)
            }
        )
        operation(service, photos)
        let count = photos.count
        selection = .empty
        return count
    }

    /// 恢复选中的照片 (从回收站)
    /// V6.29.1: 不走 undo toast (V1 简化: 恢复操作少, ⌘Z 不需要做撤销恢复的反向)
    ///   走普通 success toast
    func restoreSelectedFromTrash() {
        let count = performOnSelectedTrash({ svc, photos in photos.forEach { svc.restore($0) } })
        if count > 0 {
            enqueueToastHandler("已恢复 \(count) 张图片", .success, .normal, nil)
        }
    }

    /// 永久删除选中的照片
    /// V6.29.1: 不走 undo toast (永久删除无法恢复, 文件已从磁盘删除)
    ///   走普通 toast
    func permanentDeleteSelected() {
        let count = performOnSelectedTrash({ svc, photos in svc.purgeAll(photos) })
        if count > 0 {
            enqueueToastHandler("已永久删除 \(count) 张图片", .info, .normal, nil)
        }
    }

    /// 清空回收站
    func emptyTrash() {
        let trashed = allPhotos.filter { $0.isInTrash }
        guard !trashed.isEmpty, let modelContext = core?.modelContext else { return }
        RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [weak self] error in
                self?.enqueueToastHandler("清空回收站失败：\(error.localizedDescription)", .error, .long, nil)
            }
        ).purgeAll(trashed)
        let count = trashed.count
        selection = .empty
        enqueueToastHandler("已清空回收站（\(count) 张）", .info, .normal, nil)
    }

    /// V3.6.15: 重复图清理
    func keepNewestPerDuplicateGroup() {
        let visible = visiblePhotos.filter { !$0.isInTrash }
        let purgeable = PhotoStats.duplicatesToPurge(in: visible)
        guard !purgeable.isEmpty, let modelContext = core?.modelContext else { return }
        let service = RecycleBinService(
            storage: .shared,
            modelContext: modelContext,
            onError: { [weak self] error in
                self?.enqueueToastHandler("批量移到回收站失败：\(error.localizedDescription)", .error, .long, nil)
            }
        )
        for photo in purgeable { service.recycle(photo) }
        enqueueToastHandler("已移到回收站 \(purgeable.count) 张重复图", .info, .normal, nil)
    }
}
