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

        // V5.32: 用实际 cgImage 尺寸算 cost——之前用 maxPixelSize² × 4 估算偏大
        //   - 1 张 800×600 portrait 实际 1.92MB (vs 估算 5.76MB) — 3x 误差
        //   - 估算偏大 → NSCache 实际只容纳 ~50 张 (声称 70) — LRU 命中率虚低
        //   - 实际尺寸更准 → 400MB 容纳 ~280 张 (真实数, 之前被骗)
        let actualCost = cgImage.width * cgImage.height * 4  // RGBA
        ThumbnailCache.shared.set(image, url: url, maxPixelSize: maxPixelSize, cost: actualCost)

        return image
    }

    /// V6.22.0 (P2 #12): Thumbnail warmup — 启动后批量预热最近 N 张 thumbnail
    /// - 启动后 (ContentView .task 触发) 异步批量 prefetch, 用户进入 grid 立刻看到缩略图
    /// - 并行 4 个 TaskGroup (避免内存爆 + CPU spike)
    /// - 缓存命中后下次访问 O(1), 启动 + scroll 流畅度提升
    /// - 跟 ThumbnailCache 协同: 预热结果直接进 NSCache, 走 LRU 替换
    /// - URL 失败的图片跳过 (data 损坏 / 文件被删)
    static func warmupThumbnails(urls: [URL], maxPixelSize: CGFloat) async {
        // V6.22.0: batch size 4 — 并行 4 个 task 平衡速度 + 内存
        //   50 URLs × ~2MB = ~100MB 解码峰值, batch 4 让 4 × 2MB = 8MB 峰值
        let batchSize = 4
        let batches = stride(from: 0, to: urls.count, by: batchSize).map {
            Array(urls[$0..<min($0 + batchSize, urls.count)])
        }
        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask {
                        _ = await Self.loadImageAsync(at: url, maxPixelSize: maxPixelSize)
                    }
                }
            }
        }
    }
}
