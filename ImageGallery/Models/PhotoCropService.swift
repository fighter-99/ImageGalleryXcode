//
//  PhotoCropService.swift
//  ImageGallery
//
//  V6.97.1: Crop / Aspect (P0 #5) 服务
//
//  复用 V6.94.1 MarkupService 完整 pattern:
//   - applyCrop: 写 photo.cropRect + register undo + save context
//   - compose: 显示时裁剪原图 (NSImage + cropData → cropped NSImage)
//   - 不改原图文件 (PhotoStorage 路径), crop 独立存 SwiftData
//   - undo coalesceId="crop" (1s 窗内连续裁剪合并, 跟 markup/rotate 模式一致)
//
//  跟 MarkupService 区别:
//   - 数据是 normalized CGRect JSON (≤100 bytes), 不是 NSBezierPath plist
//   - compose 走 NSImage.draw(from:operation:) extract region, 不是 stroke overlay
//   - invalidate thumbnail cache (cropped 缩略图独立 cache, key 加 cropRect hash)
//

import Foundation
import AppKit
import SwiftData

enum PhotoCropService {
    @MainActor
    static func applyCrop(
        _ data: Data?,
        to photo: Photo,
        in context: ModelContext
    ) {
        photo.cropRect = data
        // V6.97.1: invalidate thumbnail — 下次 render 重新合成 (裁剪后缩略图独立)
        ThumbnailCache.shared.invalidate(url: photo.fileURL)
        do {
            try context.save()
        } catch {
            NSLog("V6.97.1: failed to save cropRect: \(error)")
        }
        // V6.97.1: undo register 留给 caller (GridViewModel.cropSelected) 负责
        //   跟 V6.22.1 rotateSelected pattern 一致 — caller 拿完整 snapshot + control
        //   避免 service 跟 caller 双重 register
    }

    // V6.97.1: 合成裁剪图 — 用 NSImage.draw(from:operation:) extract region
    //   cropData 是 JSON-encoded CropRect (normalized 0-1)
    //   没有 cropData / CropRect 解析失败 / .fullImage → 返 baseImage
    @MainActor
    static func compose(baseImage: NSImage, cropData: Data?) -> NSImage {
        guard let cropRect = CropRect.fromData(cropData) else { return baseImage }
        // .fullImage 早返 — 跟 reset crop 行为一致
        guard !cropRect.isFullImage else { return baseImage }

        let imageSize = baseImage.size
        let pixelRect = cropRect.pixelRect(in: imageSize)

        // 边界保护 — cropRect 越界 (图片后期 rotate 缩放) 截到图内
        let safeRect = pixelRect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !safeRect.isNull, !safeRect.isEmpty else { return baseImage }

        let cropped = NSImage(size: safeRect.size)
        cropped.lockFocus()
        baseImage.draw(
            in: NSRect(origin: .zero, size: safeRect.size),
            from: safeRect,
            operation: .copy,
            fraction: 1.0
        )
        cropped.unlockFocus()
        return cropped
    }
}
