//
//  PhotoOrientationTests.swift
//  ImageGalleryTests
//
//  V6.58 (audit P1.2): horizontalFlip parity 改 + 旋转方向保持测试
//

import Testing
@testable import ImageGallery

struct PhotoOrientationTests {

    // V6.58: 水平 flip 应该只改 parity (mirrored ↔ non-mirrored), 不改旋转方向
    @Test func horizontalFlip_togglesParityOnly() {
        #expect(PhotoOrientation.up.horizontalFlip == .upMirrored)
        #expect(PhotoOrientation.upMirrored.horizontalFlip == .up)
        #expect(PhotoOrientation.down.horizontalFlip == .downMirrored)
        #expect(PhotoOrientation.downMirrored.horizontalFlip == .down)
        // V6.58 fix: 之前 .left → .rightMirrored (错误, 改了旋转方向). 现在保持 .left
        #expect(PhotoOrientation.left.horizontalFlip == .leftMirrored)
        #expect(PhotoOrientation.leftMirrored.horizontalFlip == .left)
        #expect(PhotoOrientation.right.horizontalFlip == .rightMirrored)
        #expect(PhotoOrientation.rightMirrored.horizontalFlip == .right)
    }

    // V6.58: 双 flip 应回原方向
    @Test func horizontalFlip_isInvolution() {
        for orientation in [PhotoOrientation.up, .down, .left, .right,
                            .upMirrored, .downMirrored, .leftMirrored, .rightMirrored] {
            #expect(orientation.horizontalFlip.horizontalFlip == orientation,
                    "double horizontal flip should be identity for \(orientation)")
        }
    }
}