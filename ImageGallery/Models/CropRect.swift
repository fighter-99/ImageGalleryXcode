//
//  CropRect.swift
//  ImageGallery
//
//  V6.97.1: Crop / Aspect (P0 #5) — 裁剪矩形
//
//  设计原则 (跟 V6.94.1 MarkupService + V6.97.0 Frame persistence JSON pattern 一致):
//  - normalized 0-1 坐标 (跟图片像素无关, resolution-independent)
//  - 持久化: JSON-encoded, ≤100 bytes
//  - Photos.app 内部 Crop metadata 同样用相对坐标
//
//  用法:
//    let data = CropRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6, aspect: .ratio_16_9).toData()
//    let crop = CropRect.fromData(data)
//    let pixelRect = CGRect(cropRect * imageSize)  // 显示时转换
//

import Foundation
import CoreGraphics  // V6.97.1: CGRect.integral / CGRect init 需要 CoreGraphics

struct CropRect: Codable, Equatable {
    /// normalized origin X (0 = 左, 1 = 右), Photos.app 范式
    var x: Double
    /// normalized origin Y (0 = 上, 1 = 下) — Photos/Preview 坐标
    var y: Double
    /// normalized width (0...1)
    var width: Double
    /// normalized height (0...1)
    var height: Double
    /// preset aspect ratio used during cropping (影响 display 但不参与 rect 计算)
    ///   .freeform = 用户自由拖拽, 不约束比例
    var aspect: CropAspect

    init(x: Double, y: Double, width: Double, height: Double, aspect: CropAspect = .freeform) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.aspect = aspect
    }

    /// 整个图 (未裁剪) — Photos.app "Reset Crop" 行为
    static let fullImage = CropRect(x: 0, y: 0, width: 1, height: 1, aspect: .freeform)

    // MARK: - JSON persistence (跟 V6.97.0 Frame JSON pattern 对齐)

    /// 序列化为 Data (JSON encoded)
    ///   失败时返 nil (V6.94.1 MarkupService 同 pattern, 失败 swallow)
    func toData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// 反序列化 (JSON decoded)
    ///   失败 / nil data 返 nil
    static func fromData(_ data: Data?) -> CropRect? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CropRect.self, from: data)
    }

    // MARK: - 坐标转换

    /// normalized rect → pixel rect (给定 imageSize)
    ///   integral 后用于 NSImage.draw(from:) 等 AppKit API
    func pixelRect(in imageSize: CGSize) -> CGRect {
        CGRect(
            x: x * Double(imageSize.width),
            y: y * Double(imageSize.height),
            width: width * Double(imageSize.width),
            height: height * Double(imageSize.height)
        ).integral
    }

    /// 检查 rect 是否覆盖整个图 (Photos.app "Reset" 触发条件)
    var isFullImage: Bool {
        x <= 0 && y <= 0 && width >= 1 && height >= 1
    }
}
