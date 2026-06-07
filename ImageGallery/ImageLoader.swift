//
//  ImageLoader.swift
//  ImageGallery
//
//  安全的图片加载器。
//  - 先把文件读到内存 Data（读取完立刻释放文件句柄），不锁住原文件
//  - 用 ThumbnailCache 缓存缩略图，避免重复解码
//

import Foundation
import AppKit
import ImageIO

enum ImageLoader {
    /// 同步加载图片（带缓存）
    /// - V3.6.5 之前的版本（已被 loadImageAsync 取代，保留向后兼容）
    /// - 调用方：DetailView / ImmersivePhotoView / PhotoListView / PhotoTimelineView（一次性加载）
    /// - Parameters:
    ///   - url: 图片路径
    ///   - maxPixelSize: 最大像素（160 = 缩略图，2000 = 大图预览）
    /// - Returns: NSImage，加载失败返回 nil
    static func loadImage(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
        // 1. 先查缓存
        if let cached = ThumbnailCache.shared.get(url: url, maxPixelSize: maxPixelSize) {
            return cached
        }

        // 2. 缓存未命中，从磁盘加载
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let size = NSSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )
        let image = NSImage(cgImage: cgImage, size: size)

        // 3. 存入缓存
        ThumbnailCache.shared.set(image, url: url, maxPixelSize: maxPixelSize)

        return image
    }

    /// 异步加载图片（V3.6.26 NEW）
    /// - 缓存命中：立即返回（实际仍是同步，但通过 async 函数包装让调用方 .task 模式统一）
    /// - 缓存未命中：后台 actor 解码（不阻塞主线程）
    /// - 调用方：PhotoThumbnailView（缩略图滚动懒加载，频繁触发）
    static func loadImageAsync(at url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        // 1. 缓存命中立即返回
        if let cached = ThumbnailCache.shared.get(url: url, maxPixelSize: maxPixelSize) {
            return cached
        }

        // 2. 缓存未命中：后台线程解码
        // Task.detached 让 Data(contentsOf:) + ImageIO 都在非主线程跑
        return await Task.detached(priority: .userInitiated) {
            Self.loadImageSync(at: url, maxPixelSize: maxPixelSize)
        }.value
    }

    /// 后台线程同步加载（不经过缓存的内部版本）
    /// 给 loadImageAsync 调，不暴露给外部
    private static func loadImageSync(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let size = NSSize(
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )
        let image = NSImage(cgImage: cgImage, size: size)

        // 缓存（ThreadSafe：ThumbnailCache.shared 是 NSCache，线程安全）
        ThumbnailCache.shared.set(image, url: url, maxPixelSize: maxPixelSize)

        return image
    }
}
