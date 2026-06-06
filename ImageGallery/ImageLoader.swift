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
    /// 加载图片（带缓存）
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
}
