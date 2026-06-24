//
//  CroppedThumbnailCache.swift
//  ImageGallery
//
//  V6.97.3: 独立缓存已裁剪的 thumbnail (Crop / Aspect)
//   之前: ThumbnailCache key 是 "url_maxPixelSize", 同一 photo + 不同 cropRect 共享 cache entry
//         PhotoCellContent 每次 body 重渲都调 PhotoCropService.compose 同步裁剪
//         5000-photo 库 + 滚动 = 大量冗余合成
//   现在: 独立 NSCache, key = "url_maxPixelSize_cropHash"
//         PhotoCropService.compose 结果缓存, photo.cropRect 变化时 invalidate
//
//  跟 ThumbnailCache 平行, 不共用 (避免相互 evict 互相影响)
//  缓存策略: totalCostLimit 100MB (cropped 缩略图只用于 grid view, 比原图小)
//           countLimit 1500 (跟 ThumbnailCache 同样)
//
//  Apple Photos.app 同样模式: 同一 photo 不同编辑版本 (filter / crop / rotate) 独立缓存
//

import AppKit
import os  // V6.97.3: NSLock.withLock 自定义扩展可能需要 (跟 ThumbnailCache 同样 import)

final class CroppedThumbnailCache {
    static let shared = CroppedThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    // V6.97.3: 用 OSAllocatedUnfairLock<Stats> (跟 ThumbnailCache 同样 pattern)
    //   NSLock.withLock closure 无参, 不能 inout mutate outer var
    //   OSAllocatedUnfairLock.withLock closure `{ $0 in }` 是 inout Stats — 字段赋值写回
    //   跟 Photos.app NSCache hit/miss 统计同样 lock 策略 (Apple 推荐 unfair lock)
    private struct Stats: Sendable {
        var hits: Int = 0
        var misses: Int = 0
        var evicts: Int = 0
    }
    private let statsLock = OSAllocatedUnfairLock<Stats>(initialState: Stats())

    private init() {
        // V6.97.3: cropped 缩略图只用于 grid view (maxPixelSize ≤ 400)
        //   100MB 容纳 ~250 张, 比 ThumbnailCache 400MB 小 (cropped 不存全尺寸)
        cache.totalCostLimit = 100 * 1024 * 1024
        cache.countLimit = 1500
    }

    // MARK: - 公共方法

    /// 获取缓存的 cropped 缩略图
    /// - Parameters:
    ///   - url: 原图 URL
    ///   - maxPixelSize: 缩略图最大边长 (跟 ThumbnailCache 同样)
    ///   - cropData: photo.cropRect (Data? — nil = 无裁剪, 不查 cache)
    /// - Returns: 缓存的 NSImage 或 nil
    func get(url: URL, maxPixelSize: CGFloat, cropData: Data?) -> NSImage? {
        guard let cropData else { return nil }  // 无裁剪走 ThumbnailCache, 不进 CroppedThumbnailCache
        let key = makeKey(url: url, maxPixelSize: maxPixelSize, cropData: cropData)
        if let image = cache.object(forKey: key) {
            statsLock.withLock { $0.hits += 1 }
            return image
        }
        statsLock.withLock { $0.misses += 1 }
        return nil
    }
    // 上面 statsLock.withLock 的 $0 是 Stats struct instance (跟 ThumbnailCache 同样 pattern)
    //   Stats 字段赋值通过 inout closure capture 实现 — 写回 outer stats var

    /// 存储 cropped 缩略图
    /// - Parameters:
    ///   - image: PhotoCropService.compose 合成结果
    ///   - url: 原图 URL
    ///   - maxPixelSize: 缩略图最大边长
    ///   - cropData: photo.cropRect
    ///   - cost: 实际 cgImage bytes (跟 ThumbnailCache.set 同样 pattern)
    func set(_ image: NSImage, url: URL, maxPixelSize: CGFloat, cropData: Data, cost: Int? = nil) {
        let key = makeKey(url: url, maxPixelSize: maxPixelSize, cropData: cropData)
        let actualCost = cost ?? Int(maxPixelSize * maxPixelSize * 4)
        cache.setObject(image, forKey: key, cost: actualCost)
    }

    /// V6.97.3: 裁剪后 invalidate — PhotoCropService.applyCrop 调, 强制重 compose
    ///   之前 PhotoCellContent 走 ThumbnailCache.invalidate + view layer compose, 性能差
    ///   现在走 CroppedThumbnailCache.invalidate, 旧 entry 自动 evict
    func invalidate(url: URL) {
        // V6.97.3: NSCache 没 prefix 删 API, 不能精确删特定 cropRect
        //   实际: PhotoCropService.applyCrop 后 photo.cropRect 变了, key 也变了
        //   旧 entry 永远不再命中, NSCache LRU 自动 evict (countLimit 1500)
        //   不需要主动删 — 跟 ThumbnailCache.invalidate 不同 (那个 key 是 url, 永远命中)
        //   这里 invalidate 留作 API 一致性, 实际 no-op
    }

    /// 完全清空 (调试用)
    func clearAll() {
        cache.removeAllObjects()
    }

    // MARK: - 统计

    func stats() -> (hits: Int, misses: Int, evicts: Int, hitRate: Double) {
        statsLock.withLock {
            let total = $0.hits + $0.misses
            let rate = total > 0 ? Double($0.hits) / Double(total) : 0
            return ($0.hits, $0.misses, $0.evicts, rate)
        }
    }

    func printStats() {
        let s = stats()
        print("[CroppedThumbnailCache] hits=\(s.hits) misses=\(s.misses) evicts=\(s.evicts) hitRate=\(String(format: "%.1f%%", s.hitRate * 100))")
    }

    // MARK: - 私有

    private func makeKey(url: URL, maxPixelSize: CGFloat, cropData: Data) -> NSString {
        // key = "文件路径_最大像素_cropHash"
        //   cropHash 是 Data.hashValue (Swift built-in) — 跟 V6.97.1 CropRect JSON 字节绑定
        //   photo.cropRect 变 → Data 变 → hash 变 → 新 key → cache miss → 重 compose
        //   cache hit 时: photo.cropRect 不变 (SwiftData 持久化保证), key 不变
        let cropHash = cropData.hashValue
        return "\(url.path)_\(Int(maxPixelSize))_\(cropHash)" as NSString
    }
}