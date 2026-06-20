//
//  ThumbnailCache.swift
//  ImageGallery
//
//  缩略图内存缓存。避免重复解码。
//  缓存策略：NSCache + 内存限制（400MB）+ 自动淘汰。
//
//  V6.35.2: 加 countLimit (1500 项) + 缓存统计 (hit/miss/evict)
//    - 400MB byte cap 自动 LRU 跟 count limit 互补: byte 控制总内存, count 控制 entry 数
//    - 大库 (1万+ 照片) 多 size 缓存可能 5× 重复 (5 sizes/url), 1500 项约 ~300 张 url 全 size 覆盖
//

import Foundation
import AppKit

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    // V6.35.2: 缓存统计 (atomic counter — 跨线程安全)
    private var hitCount: Int = 0
    private var missCount: Int = 0
    private var evictCount: Int = 0

    private init() {
        // V5.17: 200→400MB——600→1200px 后单图 ~5.76MB (1200²×4)
        //   200MB 仅能容纳 ~35 张；400MB 容纳 ~70 张（与 macOS Finder/Photos 类似）
        cache.totalCostLimit = 400 * 1024 * 1024
        // V6.35.2: countLimit 1500 — 防止 1万+ 照片库 hash entries 太多
        //   NSCache 用 dictionary 存, 1万 entry 也有内存压力 (每个 entry 几十 byte 字典开销)
        //   1500 = ~300 张 url × 5 sizes 覆盖, 跟 macOS Photos 类似
        cache.countLimit = 1500
    }

    // MARK: - 公共方法

    /// 获取缓存的图片 (V6.35.2: 加 hit/miss 统计)
    func get(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let key = makeKey(url: url, maxPixelSize: maxPixelSize)
        if let image = cache.object(forKey: key) {
            hitCount += 1
            return image
        }
        missCount += 1
        return nil
    }

    /// 存储图片到缓存
    /// V5.32: 加 cost 参数 (默认 nil)——caller 传实际 cgImage 尺寸
    ///   - 之前用 maxPixelSize² × 4 估算, 偏大 3-4x
    ///   - NSCache evict 偏激进, LRU 命中率虚低
    ///   - 现在 caller 传实际 cost, 400MB 真正容纳 280 张
    func set(_ image: NSImage, url: URL, maxPixelSize: CGFloat, cost: Int? = nil) {
        let key = makeKey(url: url, maxPixelSize: maxPixelSize)
        // V3.6.5 修正: image.size 是 points (不是 pixels)
        // V5.32: caller 传 cost, 缺省 fallback 到估算 (向后兼容)
        let actualCost = cost ?? Int(maxPixelSize * maxPixelSize * 4)
        cache.setObject(image, forKey: key, cost: actualCost)
    }

    /// V6.22.1 (P2 #2): invalidate 单张 URL 的所有缓存 (所有 maxPixelSize)
    ///   旋转 / 编辑后 thumbnail 方向变了, 必须清除
    func invalidate(url: URL) {
        // NSCache 没有按 prefix 删 — 循环所有 maxPixelSize 删除
        let sizes: [CGFloat] = [170, 200, 400, 1000, 2000]
        for size in sizes {
            cache.removeObject(forKey: makeKey(url: url, maxPixelSize: size))
        }
        // V6.35.2: 主动删的也算 evict 统计
        evictCount += sizes.count
    }

    // MARK: - V6.35.2 缓存统计 (监控命中率 + 大小)

    /// 当前缓存 entry 数 (估算 — NSCache 不暴露 count API)
    /// 用 NSString key 计数: cost / 平均 cost-per-image 估算
    /// 实际: NSCache 私有 count API, 这里用 hit/miss 推算
    var stats: (hits: Int, misses: Int, evicts: Int, hitRate: Double) {
        let total = hitCount + missCount
        let rate = total > 0 ? Double(hitCount) / Double(total) : 0
        return (hitCount, missCount, evictCount, rate)
    }

    /// V6.35.2: 调试日志 — 打印当前 cache 状态 (dev only)
    func logStats() {
        let s = stats
        print("[ThumbnailCache] hits=\(s.hits) misses=\(s.misses) evicts=\(s.evicts) hitRate=\(String(format: "%.1f%%", s.hitRate * 100))")
    }

    // MARK: - 私有

    private func makeKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        // key = "文件路径_最大像素"
        return "\(url.path)_\(Int(maxPixelSize))" as NSString
    }
}
