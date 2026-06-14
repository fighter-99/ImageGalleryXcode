//
//  ThumbnailCache.swift
//  ImageGallery
//
//  缩略图内存缓存。避免重复解码。
//  缓存策略：NSCache + 内存限制（400MB）+ 自动淘汰。
//

import Foundation
import AppKit

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        // V5.17: 200→400MB——600→1200px 后单图 ~5.76MB (1200²×4)
        //   200MB 仅能容纳 ~35 张；400MB 容纳 ~70 张（与 macOS Finder/Photos 类似）
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    // MARK: - 公共方法

    /// 获取缓存的图片
    func get(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let key = makeKey(url: url, maxPixelSize: maxPixelSize)
        return cache.object(forKey: key)
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

    // MARK: - 私有

    private func makeKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        // key = "文件路径_最大像素"
        return "\(url.path)_\(Int(maxPixelSize))" as NSString
    }
}
