import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

extension GridViewModel {

    // MARK: - 单张操作

    /// 复制到剪贴板（支持多选）
    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let urls: [URL]
        if !selection.selectedIDs.isEmpty {
            urls = selectedPhotosInVisible.map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            urls = [photo.fileURL]
        } else {
            return
        }
        // V6.20.3 (code audit fix #8): 用 NSPasteboardItem + 多 type representation
        //   之前 `writeObjects(urls as [NSURL])` 只声明 fileURL promise — Photoshop/Pixelmator
        //   等专业 app 找不到 image bytes (kUTTypeImage), copy → paste 失败
        //   现在每个 URL 一个 NSPasteboardItem, 声明 .fileURL (Finder 接) + auto-detect image type (专业 app 接)
        //   writeObjects([NSPasteboardItem]) 自动 handle 多 item
        let items: [NSPasteboardItem] = urls.map { url in
            let item = NSPasteboardItem()
            // fileURL promise — Finder / Messages 接
            item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType.fileURL)
            // 自动检测 image type — Photoshop / Pixelmator / Preview 接
            if let uti = UTType(filenameExtension: url.pathExtension.lowercased()),
               uti.conforms(to: .image) {
                item.setString(url.absoluteString, forType: NSPasteboard.PasteboardType(uti.identifier))
            }
            return item
        }
        pasteboard.writeObjects(items)
        enqueueToastHandler(Copy.copiedToPasteboard(urls.count), .success, .normal, nil)
    }

    /// V6.19.0 (P0 #1): 多图分享 — NSSharingServicePicker (Photos.app 范式)
    ///   返回 URL 数组给 caller 显示 picker (SwiftUI .popover, 跟 ShareLink 单图互补)
    ///   selection 空 / 单图时退化为 ShareLink 单图 cell 菜单 (CellContextMenuModifier)
    ///   无 selection 时给提示 toast, 不报错
    func shareSelectedURLs() -> [URL] {
        let urls: [URL]
        if !selection.selectedIDs.isEmpty {
            urls = selectedPhotosInVisible.map { $0.fileURL }
        } else if let photo = singleSelectedPhoto {
            urls = [photo.fileURL]
        } else {
            enqueueToastHandler(Copy.toastSelectShareFirst, .info, .normal, nil)
            return []
        }
        return urls
    }

    /// V6.22.1 (P2 #2): 旋转选中照片 (顺时针 / 逆时针 90°)
    ///   - 写 EXIF orientation 到原文件 (lossy 重编码, JPEG/HEIC 通常不可察觉)
    ///   - 失效 ThumbnailCache (旧 thumbnail 是旧方向)
    ///   - Toast 提示成功数
    ///   - selection 空时 toast 提示用户先选图 (跟 shareSelected 一致 UX)
    ///   - Photos.app 范式: 旋转是 in-place file 修改, 无 undo (用户可 export 原图 + 重新 import 复原)
    func rotateSelected(clockwise: Bool) {
        let photos = selectedPhotosInVisible
        guard !photos.isEmpty else {
            enqueueToastHandler(Copy.toastSelectRotateFirst, .info, .normal, nil)
            return
        }
        // V6.35.3: capture 旋转前 orientation (每张图) — undo 还原用
        struct Snapshot { let photo: Photo; let original: PhotoOrientation? }
        let snapshots: [Snapshot] = photos.map { photo in
            Snapshot(photo: photo, original: readOrientation(url: photo.fileURL))
        }
        var successCount = 0
        for photo in photos {
            // 读取当前 EXIF orientation (V6.22.1: 用 CGImageSource 读 metadata)
            let current = readOrientation(url: photo.fileURL) ?? .up
            let new = clockwise ? current.rotated90Clockwise() : current.rotated90CounterClockwise()
            // 写新 orientation 到文件 + 失效 cache
            if PhotoRotationService.applyOrientation(new, to: photo.fileURL) {
                PhotoRotationService.invalidateThumbnail(for: photo.fileURL)
                successCount += 1
            }
        }
        let message = Copy.toastRotated(successCount)
        enqueueToastHandler(message, successCount == photos.count ? .success : .warning, .normal, nil)

        // V6.35.3: register undo (coalesceId="rotate" — 1s 内连续旋转合并)
        //   Photos.app 行为: 连转 5 张 = 1 个 undo, ⌘Z 一次撤销整批
        let capturedSnapshots = snapshots
        let capturedCount = successCount
        let undo: () -> Void = { [weak self] in
            guard let self else { return }
            for snap in capturedSnapshots where snap.original != nil {
                if let original = snap.original,
                   PhotoRotationService.applyOrientation(original, to: snap.photo.fileURL) {
                    PhotoRotationService.invalidateThumbnail(for: snap.photo.fileURL)
                }
            }
            self.enqueueToastHandler(Copy.toastUndoRotate(capturedCount), .info, .normal, nil)
        }
        undoManager.registerUndoOnly(description: Copy.undoRotate(capturedCount), undo: undo, coalesceId: "rotate")
    }

    /// V6.22.1: 读 EXIF orientation — 用 CGImageSourceCopyPropertiesAtIndex
    ///   返回 nil 表示无 orientation tag (default .up)
    private func readOrientation(url: URL) -> PhotoOrientation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let raw = props[kCGImagePropertyOrientation] as? UInt32 else { return nil }
        return PhotoOrientation(rawValue: raw)
    }

    /// V6.19.5 (P0 #16): 朗读选中照片 (Speech menu, macOS Edit > Speech 范式)
    ///   - selection 空 → toast 提示
    ///   - 1 张 → 读 "已选 1 张照片, 文件名 XXX"
    ///   - N 张 → 读 "已选 N 张照片, 第一张 XXX"
    ///   zh-CN 语音; AVSpeechSynthesizer 一次性 utterance (不持久 synthesizer)
    func speakSelection() {
        let photos = selectedPhotosInVisible
        guard !photos.isEmpty else {
            enqueueToastHandler(Copy.toastSelectSpeakFirst, .info, .normal, nil)
            return
        }
        let message: String
        if photos.count == 1 {
            message = Copy.speakOnePhoto(photos[0].filename)
        } else {
            message = Copy.speakMultiplePhotos(photos.count, firstFilename: photos[0].filename)
        }
        let utterance = AVSpeechUtterance(string: message)
        // V6.20.3 (code audit fix #13): voice fallback chain — zh-CN → 当前 locale → en-US → system default
        let voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
            ?? AVSpeechSynthesisVoice()
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        // V6.20.2 (code audit fix #4): 用 stable synthesizer 实例 + stop 上一个 utterance
        speechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        speechSynthesizer.speak(utterance)
    }

    /// 进入沉浸式查看
    func enterImmersive(_ photo: Photo) {
        if let idx = visiblePhotos.firstIndex(where: { $0.id == photo.id }) {
            immersiveIndex = idx
            immersivePhoto = photo
        }
    }

    /// V4.49.1: ⌘↩ Return 触发进入沉浸式
    func enterImmersiveFromSelection() {
        guard let photo = singleSelectedPhoto else { return }
        enterImmersive(photo)
    }

    /// 清除所有筛选
    func resetFilters() {
        searchText = ""
        core?.sidebarSelection = .all
        core?.filterState = .empty
    }

    /// Delete 键处理
    func handleDelete() {
        if !selection.selectedIDs.isEmpty {
            showingBatchDeleteConfirm = true
        } else if singleSelectedPhoto != nil {
            deleteSinglePhoto()
        }
    }

    /// V4.36.6: 3 视图共用 tap 处理
    func handleTap(_ photo: Photo) {
        let modifiers = NSEvent.modifierFlags
        let modifier: ClickModifier = {
            if modifiers.contains(.command) { return .command }
            if modifiers.contains(.shift) { return .shift }
            return .plain
        }()
        let photoIDs = visiblePhotos.map { $0.id }
        let outcome = MultiSelectMath.handleTap(
            state: selection,
            photoID: photo.id,
            modifier: modifier,
            photoIDs: photoIDs
        )
        switch outcome {
        case .singleSelect(let s), .toggleMultiSelect(let s), .rangeSelect(let s):
            selection = s
        }
    }

    /// 上一张
    func goPrev() {
        guard canPrev,
              let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        let newID = visiblePhotos[idx - 1].id
        selection = selection.selectingSingle(newID)
    }

    /// 下一张
    func goNext() {
        guard canNext,
              let id = selection.singleSelectedID,
              let idx = visiblePhotos.firstIndex(where: { $0.id == id }),
              idx < visiblePhotos.count - 1 else { return }
        let newID = visiblePhotos[idx + 1].id
        selection = selection.selectingSingle(newID)
    }

    /// ⌘+ 放大
    func zoomIn() {
        if let next = ThumbnailDensity.larger(than: thumbnailSize) {
            thumbnailSize = next.size
        }
    }

    /// ⌘- 缩小
    func zoomOut() {
        if let prev = ThumbnailDensity.smaller(than: thumbnailSize) {
            thumbnailSize = prev.size
        }
    }

    /// V6.14.8: ⌘0 reset zoom — 清 liveThumbnailSize, 回到 stored default
    ///   之前是 `thumbnailSize = settings.thumbnailSize` no-op (V6.14.7 修 stale test 时发现)
    func resetThumbnailSize() {
        liveThumbnailSize = nil
    }

    /// V4.37.1: Quick Look——V5.42 改走 enterImmersiveFromSelection
    func showQuickLook() {
        enterImmersiveFromSelection()
    }

}
