//
//  ToastInfoTests.swift
//  ImageGalleryTests
//
//  V5.13：ToastInfo V5.13 升级后行为测试。
//  - id 唯一性（每次 init 变 UUID）
//  - Duration.seconds 三档时长
//  - 自定义 == 忽略 id（plan agent 风险 #1 治本）
//  - Identifiable conformance
//

import Testing
import Foundation
@testable import ImageGallery

struct ToastInfoTests {
    // MARK: - id 唯一性

    @Test func idIsUniqueAcrossInstances() {
        let a = ToastInfo(message: "hi", type: .info)
        let b = ToastInfo(message: "hi", type: .info)
        #expect(a.id != b.id)
    }

    @Test func idIsUUIDType() {
        // 编译期 + 运行时验证 id 是 UUID
        let a = ToastInfo(message: "hi", type: .info)
        let id: UUID = a.id
        #expect(UUID(uuidString: id.uuidString) == id)
    }

    // MARK: - Duration 时长

    @Test func durationShortIsTwoSeconds() {
        #expect(ToastInfo.Duration.short.seconds == 2)
    }

    @Test func durationNormalIsTwoPointFiveSeconds() {
        #expect(ToastInfo.Duration.normal.seconds == 2.5)
    }

    @Test func durationLongIsFiveSeconds() {
        #expect(ToastInfo.Duration.long.seconds == 5)
    }

    @Test func durationIsEquatable() {
        #expect(ToastInfo.Duration.short == ToastInfo.Duration.short)
        #expect(ToastInfo.Duration.short != ToastInfo.Duration.long)
        #expect(ToastInfo.Duration.normal != .long)
    }

    // MARK: - 自定义 == 忽略 id（关键：plan agent 风险 #1 治本）

    @Test func equalityIgnoresId() {
        let a = ToastInfo(message: "hi", type: .info)
        let b = ToastInfo(message: "hi", type: .info)
        // a.id != b.id（unique），但 a == b（业务语义相同）
        #expect(a.id != b.id)
        #expect(a == b)
    }

    @Test func equalityDistinguishesMessage() {
        let a = ToastInfo(message: "hi", type: .info)
        let b = ToastInfo(message: "bye", type: .info)
        #expect(a != b)
    }

    @Test func equalityDistinguishesType() {
        let a = ToastInfo(message: "hi", type: .info)
        let b = ToastInfo(message: "hi", type: .error)
        #expect(a != b)
    }

    @Test func equalityDistinguishesDuration() {
        let a = ToastInfo(message: "hi", type: .info, duration: ToastInfo.Duration.short)
        let b = ToastInfo(message: "hi", type: .info, duration: ToastInfo.Duration.long)
        #expect(a != b)
    }

    // MARK: - Default

    @Test func defaultDurationIsNormal() {
        let a = ToastInfo(message: "hi", type: .info)
        #expect(a.duration == .normal)
    }

    // MARK: - Identifiable conformance

    @Test func identifiableConformance() {
        // 编译期已通过 Identifiable；运行时验证 id 可作 SwiftUI ForEach key
        let a = ToastInfo(message: "hi", type: .info)
        let b = ToastInfo(message: "hi", type: .info)
        // 不同 id 可在 ForEach 中区分（这是 Day 4 队列去重/替换的关键）
        #expect(a.id != b.id)
    }
}
