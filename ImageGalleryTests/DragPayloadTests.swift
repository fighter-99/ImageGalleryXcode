//
//  DragPayloadTests.swift
//  ImageGalleryTests
//
//  V3.6.29：DragPayload 纯函数测试。
//
//  覆盖 DragPayload.build 的关键不变量（与 V3.6.27 inline 实现对齐）：
//  - uuidData 是 photo.id.uuidString 的 UTF-8 字节
//  - fileURL 等于 photo.fileURL
//  - suggestedName 等于 photo.filename
//
//  测试模式：参考 DragReorderMathTests——纯函数，零依赖（不需要 SwiftData container）。
//  V3.6.28 教训：computeHits 接 [Photo] 引发 Swift Testing 并行 @MainActor 测试时
//  SwiftData in-memory 容器共享状态冲突。这里 DragPayload.build 接 Photo，但我们只读
//  photo 的几个简单属性，不创建 ModelContainer，避开冲突。
//

import Foundation
import Testing
@testable import ImageGallery

struct DragPayloadTests {

    // MARK: - 辅助

    /// V3.6.29：构造测试用 Photo（不插 ModelContainer——只读 id/fileURL/filename，
    /// 避开 V3.6.28 那种 SwiftData in-memory 并行冲突）
    private func makePhoto(
        filename: String = "test.jpg",
        fileURL: URL = URL(fileURLWithPath: "/tmp/DragPayloadTest.jpg")
    ) -> Photo {
        Photo(
            filename: filename,
            fileURL: fileURL,
            fileSize: 1024,
            width: 100,
            height: 100
        )
    }

    // MARK: - uuidData

    @Test func uuidDataIsUTF8OfPhotoIDUUIDString() {
        // 不变量：uuidData == photo.id.uuidString 的 UTF-8 字节
        // 侧栏 drop 时按 utf8 解码回 UUID
        let photo = makePhoto()
        let payload = DragPayload.build(for: photo)

        let expectedUUIDString = photo.id.uuidString
        let expectedData = expectedUUIDString.data(using: .utf8)

        #expect(payload.uuidData == expectedData)
    }

    @Test func uuidDataIsValidUTF8RoundTrip() {
        // 端到端：uuidData 用 utf8 解码回去 = 原始 UUID 字符串
        let photo = makePhoto()
        let payload = DragPayload.build(for: photo)

        let decoded = String(data: payload.uuidData, encoding: .utf8)
        #expect(decoded == photo.id.uuidString)
    }

    // MARK: - fileURL

    @Test func fileURLEqualsPhotoFileURL() {
        let customURL = URL(fileURLWithPath: "/Users/test/Pictures/photo.jpg")
        let photo = makePhoto(fileURL: customURL)
        let payload = DragPayload.build(for: photo)

        #expect(payload.fileURL == customURL)
    }

    // MARK: - suggestedName

    @Test func suggestedNameEqualsPhotoFilename() {
        let customName = "vacation_2024.jpg"
        let photo = makePhoto(filename: customName)
        let payload = DragPayload.build(for: photo)

        #expect(payload.suggestedName == customName)
    }

    // MARK: - Equatable

    @Test func equatableWhenFieldsMatch() {
        // 同一 photo build 两次（id 由 init 自动生成）应该相等
        let photo = makePhoto()
        let a = DragPayload.build(for: photo)
        let b = DragPayload.build(for: photo)
        #expect(a == b)
    }
}
