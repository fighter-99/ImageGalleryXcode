//
//  CropRectTests.swift
//  ImageGalleryTests
//
//  V6.97.1 (P0 #5): Crop / Aspect — 单元测试 CropRect JSON round-trip + 6 preset + pixelRect 转换
//
//  跟 V6.97.0 WindowFramePersistenceTests 同 pattern:
//   - JSON encoded format 稳定 (跟 V6.97.0 imageGalleryWindowFrames 主 key 风格一致)
//   - 6 个 preset ratio 锁值 (1, 4/3, 16/9, 3/2, 2/3, nil for freeform)
//   - pixelRect 转换精度 (normalized 0-1 → pixel CGRect)
//   - isFullImage 判定 (.fullImage 跟 nil data 行为一致)
//
//  预期: 8 test 0 fail
//

import Testing
import Foundation  // Data / JSONSerialization
import CoreGraphics
@testable import ImageGallery

@Suite(.serialized)
struct CropRectTests {

    // MARK: - JSON round-trip

    @Test func toData_thenFromData_roundTripsRect() {
        let original = CropRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6, aspect: .ratio_16_9)
        let data = original.toData()
        #expect(data != nil, "toData 应该返非 nil")
        let restored = CropRect.fromData(data)
        #expect(restored == original, "round-trip 后 CropRect 应等值")
    }

    @Test func toData_doesNotIncludeExtraKeys() throws {
        // V6.97.0 教训: 持久化 JSON 不能有多余字段 (backward compat)
        let crop = CropRect(x: 0, y: 0, width: 1, height: 1, aspect: .freeform)
        let data = try #require(crop.toData())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 必须只有 5 个 key: x, y, width, height, aspect
        #expect(json.count == 5, "CropRect JSON 应只有 5 个 key")
        #expect(json["x"] != nil)
        #expect(json["y"] != nil)
        #expect(json["width"] != nil)
        #expect(json["height"] != nil)
        #expect(json["aspect"] != nil)
    }

    @Test func fromData_nilData_returnsNil() {
        let restored = CropRect.fromData(nil)
        #expect(restored == nil)
    }

    @Test func fromData_corruptJSON_returnsNil() {
        let corrupt = Data("not valid json".utf8)
        let restored = CropRect.fromData(corrupt)
        #expect(restored == nil, "损坏 JSON 应返 nil (跟 V6.94.1 MarkupService 同 fail-soft pattern)")
    }

    // MARK: - 6 preset ratio 锁值

    // V6.97.1 修法: 用 epsilon 比较 替代 ==
    //   原因: CGFloat 跨平台 (macOS Double / iOS Float) + Swift 6 编译期常量折叠
    //   IEEE 754 浮点精度下, 4.0/3.0 跟 (a/b) 算的 1.3333 末位 bit 不一定相同
    //   4 个 fail 精准命中 4 个非整除 ratio (4/3, 16/9, 3/2, 2/3), 1.0 跟 nil 都 pass
    //   → 100% 是 Double precision 问题, 不是逻辑问题
    private func ratioEquals(_ lhs: CGFloat?, _ rhs: Double, eps: Double = 1e-9) -> Bool {
        guard let lhs else { return false }
        return abs(Double(lhs) - rhs) < eps
    }

    @Test func aspectRatio_values() {
        // 跟 Photos Sonoma+ 真版 6 个 preset 1:1 (跟 plan 决策一致)
        #expect(CropAspect.freeform.ratio == nil, "freeform = nil (无约束)")
        #expect(CropAspect.ratio_1_1.ratio == 1.0, "1:1 = 1.0")
        #expect(ratioEquals(CropAspect.ratio_4_3.ratio, 4.0 / 3.0), "4:3 ≈ 1.333...")
        #expect(ratioEquals(CropAspect.ratio_16_9.ratio, 16.0 / 9.0), "16:9 ≈ 1.777...")
        #expect(ratioEquals(CropAspect.ratio_3_2.ratio, 3.0 / 2.0), "3:2 = 1.5")
        #expect(ratioEquals(CropAspect.ratio_2_3.ratio, 2.0 / 3.0), "2:3 ≈ 0.666...")
    }

    @Test func aspect_allCases_count6() {
        // 锁 6 个 preset 数量 — 跟 Photos 真版 1:1
        #expect(CropAspect.allCases.count == 6)
    }

    // MARK: - pixelRect 转换

    @Test func pixelRect_normalizedToPixels() {
        let crop = CropRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25, aspect: .freeform)
        let imageSize = CGSize(width: 1000, height: 800)
        let pixels = crop.pixelRect(in: imageSize)
        // x = 0.25 * 1000 = 250, y = 0.5 * 800 = 400, w = 0.5 * 1000 = 500, h = 0.25 * 800 = 200
        #expect(pixels.origin.x == 250)
        #expect(pixels.origin.y == 400)
        #expect(pixels.size.width == 500)
        #expect(pixels.size.height == 200)
    }

    @Test func pixelRect_zeroSizeImage_returnsEmpty() {
        // 边界: 0 大小图片 — pixelRect 应该也是 0/empty
        let crop = CropRect(x: 0, y: 0, width: 1, height: 1, aspect: .freeform)
        let pixels = crop.pixelRect(in: CGSize(width: 0, height: 0))
        #expect(pixels.size.width == 0)
        #expect(pixels.size.height == 0)
    }

    // MARK: - isFullImage 判定

    @Test func isFullImage_fullImage_isTrue() {
        // Photos.app "Reset" 行为触发条件
        #expect(CropRect.fullImage.isFullImage == true)
    }

    @Test func isFullImage_partialCrop_isFalse() {
        let partial = CropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8, aspect: .ratio_1_1)
        #expect(partial.isFullImage == false)
    }
}
