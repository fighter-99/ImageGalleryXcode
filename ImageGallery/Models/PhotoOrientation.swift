//
//  PhotoOrientation.swift
//  ImageGallery
//
//  V6.22.1 (P2 #2): Rotate/flip — EXIF orientation wrapper
//   - Swift 包装 CGImagePropertyOrientation (UInt32 raw value)
//   - 提供 .degrees 转换 (90/180/270)
//   - rotation 通过 CGImageDestination 重写 EXIF + invalidate ThumbnailCache
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// V6.22.1: 包装 CGImagePropertyOrientation — 跟 SwiftData 持久化无关 (无 schema field)
//   旋转只写 EXIF orientation 到文件, ThumbnailCache 自动 invalidate
/// 旋转角度枚举 (Photos.app 范式: 90° 增量旋转 + 水平/垂直 flip)
enum PhotoOrientation: UInt32, CaseIterable {
    case up = 1
    case down = 3
    case left = 8          // 逆时针 90° / 顺时针 270°
    case right = 6         // 顺时针 90° / 逆时针 270°
    case upMirrored = 2
    case downMirrored = 4
    case leftMirrored = 5  // 水平 flip
    case rightMirrored = 7 // 垂直 flip

    /// 顺时针 90° 增量旋转
    func rotated90Clockwise() -> PhotoOrientation {
        switch self {
        case .up: return .right
        case .right: return .down
        case .down: return .left
        case .left: return .up
        case .upMirrored: return .rightMirrored
        case .rightMirrored: return .downMirrored
        case .downMirrored: return .leftMirrored
        case .leftMirrored: return .upMirrored
        }
    }

    /// 逆时针 90° 增量旋转
    func rotated90CounterClockwise() -> PhotoOrientation {
        switch self {
        case .up: return .left
        case .left: return .down
        case .down: return .right
        case .right: return .up
        case .upMirrored: return .leftMirrored
        case .leftMirrored: return .downMirrored
        case .downMirrored: return .rightMirrored
        case .rightMirrored: return .upMirrored
        }
    }

    /// 水平 flip (左右镜像)
    // V6.58 (audit P1.2): 之前 `.left → .rightMirrored` 错误 — 水平 flip 是 parity 改变
    //   (mirrored ↔ non-mirrored), 不应改旋转方向. 之前实现让用户得到旋转+翻转
    //   (180° 偏离意图). 现在保持旋转方向, 只切 mirrored.
    var horizontalFlip: PhotoOrientation {
        switch self {
        case .up: return .upMirrored
        case .down: return .downMirrored
        case .left: return .leftMirrored
        case .right: return .rightMirrored
        case .upMirrored: return .up
        case .downMirrored: return .down
        case .leftMirrored: return .left
        case .rightMirrored: return .right
        }
    }

    /// 垂直 flip (上下镜像)
    var verticalFlip: PhotoOrientation {
        switch self {
        case .up: return .downMirrored
        case .down: return .upMirrored
        case .left: return .leftMirrored
        case .right: return .rightMirrored
        case .upMirrored: return .down
        case .downMirrored: return .up
        case .leftMirrored: return .left
        case .rightMirrored: return .right
        }
    }
}

/// V6.22.1: EXIF orientation 写入文件 + ThumbnailCache invalidate
/// - 写入临时文件 (.rotate.tmp) + atomic rename, 防止写入失败损坏原图
/// - JPEG/HEIC/PNG 都用 CGImageDestination 重写 (lossy 重编码, 但 JPEG/HEIC 通常不可察觉)
/// - 旋转后必须 invalidate ThumbnailCache (旧 thumbnail 缓存是旧方向)
enum PhotoRotationService {
    static func applyOrientation(_ orientation: PhotoOrientation, to url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        // 确定文件类型 (跟原文件一致)
        guard let utType = UTType(filenameExtension: url.pathExtension.lowercased())?.identifier else { return false }
        // 临时文件 .rotate.tmp, atomic rename 成功后删除
        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).rotate.tmp")
        // 清理旧 tmp 文件 (上次失败残留)
        try? FileManager.default.removeItem(at: tmpURL)
        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, utType as CFString, 1, nil) else { return false }
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation.rawValue
        ]
        CGImageDestinationAddImageFromSource(dest, source, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return false }
        // atomic rename (replaceItemAt 保留 inode + permissions)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
    }

    /// ThumbnailCache invalidate — 旋转后旧 thumbnail 缓存是旧方向
    /// V6.22.1: 加 invalidate 方法 (之前 cache 没暴露)
    static func invalidateThumbnail(for url: URL) {
        ThumbnailCache.shared.invalidate(url: url)
    }
}