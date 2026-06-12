//
//  SaveWithLogErrorTests.swift
//  ImageGalleryTests
//
//  V5.14: saveWithLog(onError:) 签名（V5.13 Day 5 加）测试。
//  重点测 success path + nil 兼容 + 闭包签名——save 失败难造（plan 风险 #4）。
//
//  V5.14 关键发现：helper 方法（private/static）在 @MainActor struct 内
//  触发现有 test bundle 失败。DebugTest 验证 inline 模式稳定——全 inline。
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
struct SaveWithLogErrorTests {
    // MARK: - 成功路径

    @Test func saveWithLogReturnsTrueOnSuccess() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SWLE1_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        let result = context.saveWithLog()
        #expect(result == true, "SwiftData save 成功应返回 true")
    }

    @Test func saveWithLogOnErrorNotCalledOnSuccess() throws {
        // 成功路径不调 onError
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SWLE2_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var called = false
        let result = context.saveWithLog { _ in called = true }
        #expect(result == true)
        #expect(called == false, "成功不应调 onError")
    }

    // MARK: - nil 兼容

    @Test func saveWithLogWithNilOnErrorIsNoOp() throws {
        // V5.13 Day 5 设计：onError: ((Error) -> Void)? = nil 默认
        // 24 处旧 call site 都靠这个默认 nil 编译通过
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SWLE3_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        let result = context.saveWithLog(onError: nil)
        #expect(result == true, "onError=nil 时 save 仍正常返回 true")
    }

    @Test func saveWithLogSignatureAcceptsClosure() throws {
        // 编译期已验：onError 参数 + 默认 nil
        // 运行时验：传 closure 不破坏 save 逻辑
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Photo.self, Folder.self, Tag.self,
            configurations: config
        )
        let context = container.mainContext
        let p = Photo(
            filename: "test.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/SWLE4_\(UUID().uuidString).jpg"),
            fileSize: 0, width: 0, height: 0
        )
        context.insert(p)
        try context.save()
        var captured: Error?
        let result = context.saveWithLog { error in captured = error }
        #expect(result == true)
        #expect(captured == nil, "成功路径不传 error 给 closure")
    }
}
