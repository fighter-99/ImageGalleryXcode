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
    func set(_ image: NSImage, url: URL, maxPixelSize: CGFloat) {
        let key = makeKey(url: url, maxPixelSize: maxPixelSize)
        // V3.6.5 修正：image.size 是 points（不是 pixels）。HiDPI 屏幕像素数 = points² × scaleFactor²
        // 用 maxPixelSize（请求的像素上限）做 cost 上界估算更准
        let maxPixels = Int(maxPixelSize * maxPixelSize)
        let cost = maxPixels * 4  // RGBA = 4 bytes/pixel
        cache.setObject(image, forKey: key, cost: cost)
    }

    // MARK: - 私有

    private func makeKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        // key = "文件路径_最大像素"
        return "\(url.path)_\(Int(maxPixelSize))" as NSString
    }
}
