//
//  ImageLoaderTests.swift
//  ImageGalleryTests
//
//  V5.17: ThumbnailCache + ImageLoader 关键行为测试
//  镜像 MasonryMathTests pattern（无 @MainActor pure 测试）
//  避 V5.14 helper-method bug
//

import Testing
import Foundation
import AppKit
@testable import ImageGallery

struct ImageLoaderTests {
    // MARK: - ThumbnailCache key 行为

    @Test func thumbnailCacheKeyIncludesPixelSize() {
        // V5.17: 验证不同 maxPixelSize 生成不同 cache key
        // 600px 旧 entry 与 1200px 新 entry 共存不冲突
        let url = URL(fileURLWithPath: "/tmp/test_image.jpg")
        let _ = ThumbnailCache.shared  // 确保 init 触发

        // 通过 ImageLoader 间接验 key（不能直接调 private makeKey）
        // 改用 set/get 一张临时图片，验不同 maxPixelSize 独立缓存
        let img1 = NSImage(size: NSSize(width: 10, height: 10))
        ThumbnailCache.shared.set(img1, url: url, maxPixelSize: 600)
        let cached1 = ThumbnailCache.shared.get(url: url, maxPixelSize: 600)
        let cached2 = ThumbnailCache.shared.get(url: url, maxPixelSize: 1200)

        // 600px key 命中
        #expect(cached1 != nil, "600px cache 应命中")
        // 1200px key 不命中（独立 key）
        #expect(cached2 == nil, "1200px cache 独立——不应命中 600px entry")

        // 清缓存防污染
        ThumbnailCache.shared.set(NSImage(size: .zero), url: url, maxPixelSize: 1200)
    }

    @Test func thumbnailCacheKeyIncludesURL() {
        // V5.17: 不同 URL 独立缓存
        let url1 = URL(fileURLWithPath: "/tmp/cache_test_a.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/cache_test_b.jpg")
        let imgA = NSImage(size: NSSize(width: 10, height: 10))
        ThumbnailCache.shared.set(imgA, url: url1, maxPixelSize: 600)

        let cachedA = ThumbnailCache.shared.get(url: url1, maxPixelSize: 600)
        let cachedB = ThumbnailCache.shared.get(url: url2, maxPixelSize: 600)

        #expect(cachedA != nil, "url1 缓存应命中")
        #expect(cachedB == nil, "url2 独立 key——不应命中 url1 缓存")

        // 清缓存
        ThumbnailCache.shared.set(NSImage(size: .zero), url: url1, maxPixelSize: 600)
    }

    // MARK: - ImageLoader 错误处理

    @Test func imageLoaderNonExistentURLReturnsNil() {
        // V5.17: 不存在 URL → 加载返回 nil（不崩溃）
        let badURL = URL(fileURLWithPath: "/tmp/nonexistent_image_\(UUID().uuidString).jpg")
        // .task 闭包需 @MainActor；用 Task + await
        let exp = Task { @MainActor in
            await ImageLoader.loadImageAsync(at: badURL, maxPixelSize: 600)
        }
        // 同步等待——Task.detached 给 .value 走 MainActor
        let result = runBlockingAsync { await exp.value }
        #expect(result == nil, "不存在 URL 应返回 nil 不崩溃")
    }

    // MARK: - ImageLoader 尺寸限制

    @Test func imageLoaderCapsLoadedImageToMaxPixelSize() async {
        // V5.17: 写入大图 + 用 maxPixelSize=200 加载 → 验证返回图 ≤ 200px
        // 写一个 800x600 PNG 临时文件
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLoaderTest_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 用 NSImage 画 800x600 红图
        let big = NSImage(size: NSSize(width: 800, height: 600))
        big.lockFocus()
        NSColor.red.set()
        NSBezierPath.fill(NSRect(origin: .zero, size: NSSize(width: 800, height: 600)))
        big.unlockFocus()

        guard let tiff = big.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create PNG from NSImage")
            return
        }
        do {
            try pngData.write(to: tmp)
        } catch {
            Issue.record("Failed to write PNG: \(error)")
            return
        }

        // 加载 with maxPixelSize=200 → 应 < 200px
        let loaded = await ImageLoader.loadImageAsync(at: tmp, maxPixelSize: 200)
        #expect(loaded != nil)
        if let img = loaded {
            let maxDim = max(img.size.width, img.size.height)
            // 0.5 容差（向上取整到下个像素）
            #expect(maxDim <= 200.5, "加载图最大边 ≤ 200px (实际 \(img.size))")
        }
    }

    // MARK: - helper

    /// 同步等待 async 闭包返回（用于非 async 测试上下文）
    private func runBlockingAsync<T>(_ operation: @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T!
        Task.detached {
            result = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}
