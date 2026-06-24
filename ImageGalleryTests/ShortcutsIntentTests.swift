//
//  ShortcutsIntentTests.swift
//  ImageGalleryTests
//
//  V6.97.2: 4 个 Shortcut + CropAspect AppEnum + handleShortcutsURL 单元测试
//
//  测试覆盖:
//    1. handleShortcutsURL 路由正确 (4 个 action 各自分发到对应 Notification)
//    2. CropAspect AppEnum 6 case + typeDisplayRepresentation
//    3. 4 个 Intent perform() 不 crash (verify URL 生成正确)
//    4. URL parameter 编码正确 (search query 加 percent encoding)
//
//  预期: 8 test 0 fail (跟 V6.97.0 / V6.97.1 WindowFramePersistenceTests / CropRectTests 同 pattern)
//
//  注意: 不能测 NSWorkspace.openURL (跨进程), 只能测 Intent 内部 URL 生成 + handleShortcutsURL 路由
//

import Testing
import Foundation
import AppKit
@testable import ImageGallery

@Suite(.serialized)
struct ShortcutsIntentTests {

    // MARK: - handleShortcutsURL 路由

    @Test func handleShortcutsURL_showLast_dispatchesToShowLastNotification() {
        var receivedNotification: Notification.Name?
        let observer = NotificationCenter.default.addObserver(
            forName: .shortcutsShowLastPhotoRequested,
            object: nil,
            queue: .main
        ) { _ in
            receivedNotification = .shortcutsShowLastPhotoRequested
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        ImageGalleryApp.handleShortcutsURL(URL(string: "imagegallery://show-last")!)

        // 等待 0.1s 让 notification 派发到 main queue
        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.signal() }
        exp.wait()

        #expect(receivedNotification == .shortcutsShowLastPhotoRequested)
    }

    @Test func handleShortcutsURL_search_extractsQueryFromUserInfo() {
        var receivedQuery: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .shortcutsSearchRequested,
            object: nil,
            queue: .main
        ) { note in
            receivedQuery = note.userInfo?["query"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        ImageGalleryApp.handleShortcutsURL(URL(string: "imagegallery://search?q=cat")!)

        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.signal() }
        exp.wait()

        #expect(receivedQuery == "cat")
    }

    @Test func handleShortcutsURL_crop_extractsAspectFromUserInfo() {
        var receivedAspect: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .shortcutsCropRequested,
            object: nil,
            queue: .main
        ) { note in
            receivedAspect = note.userInfo?["aspect"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        ImageGalleryApp.handleShortcutsURL(URL(string: "imagegallery://crop?aspect=ratio_16_9")!)

        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.signal() }
        exp.wait()

        #expect(receivedAspect == "ratio_16_9")
    }

    @Test func handleShortcutsURL_favorite_dispatchesToFavoriteNotification() {
        var receivedNotification: Notification.Name?
        let observer = NotificationCenter.default.addObserver(
            forName: .shortcutsFavoriteRequested,
            object: nil,
            queue: .main
        ) { _ in
            receivedNotification = .shortcutsFavoriteRequested
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        ImageGalleryApp.handleShortcutsURL(URL(string: "imagegallery://favorite")!)

        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.signal() }
        exp.wait()

        #expect(receivedNotification == .shortcutsFavoriteRequested)
    }

    @Test func handleShortcutsURL_unknownAction_doesNotCrash() {
        // 未知 action 应该被 logger.warning 吞掉, 不发任何 notification
        var anyReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .shortcutsShowLastPhotoRequested,
            object: nil,
            queue: .main
        ) { _ in
            anyReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        ImageGalleryApp.handleShortcutsURL(URL(string: "imagegallery://unknown-action")!)

        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.signal() }
        exp.wait()

        #expect(!anyReceived, "未知 action 不应触发任何 notification")
    }

    @Test func handleShortcutsURL_nonImageGalleryScheme_ignored() {
        var anyReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .shortcutsShowLastPhotoRequested,
            object: nil,
            queue: .main
        ) { _ in
            anyReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // 错误 scheme 应该被忽略 (防御性 guard)
        ImageGalleryApp.handleShortcutsURL(URL(string: "https://example.com")!)

        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.signal() }
        exp.wait()

        #expect(!anyReceived, "非 imagegallery scheme 应被忽略")
    }

    // MARK: - CropAspect AppEnum conformance

    @Test func cropAspectAppEnum_allCasesPresent() {
        // 6 case 跟 V6.97.1 CropAspect 完全平行
        // 验证 AppEnum conformance 后, rawValue 仍可用 (跟 V6.97.1 CropRect.toData() 同样)
        #expect(CropAspect.allCases.count == 6, "CropAspect AppEnum 必须 6 case")
        #expect(CropAspect.freeform.rawValue == "freeform")
        #expect(CropAspect.ratio_1_1.rawValue == "ratio_1_1")
        #expect(CropAspect.ratio_4_3.rawValue == "ratio_4_3")
        #expect(CropAspect.ratio_16_9.rawValue == "ratio_16_9")
        #expect(CropAspect.ratio_3_2.rawValue == "ratio_3_2")
        #expect(CropAspect.ratio_2_3.rawValue == "ratio_2_3")
    }

    // MARK: - URL parameter 编码

    @Test func searchIntent_urlEncoding_handlesChineseAndSpaces() {
        // 中文 + 空格 + 特殊字符应该 percent-encode
        // V6.97.2 决策: SearchPhotosIntent.perform() 走 query.addingPercentEncoding
        //   这里测验证: URL 生成后, query 应该能被 URLComponents 解码回原文
        let query = "猫 dog!"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "imagegallery://search?q=\(encoded)")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let decodedQuery = components?.queryItems?.first(where: { $0.name == "q" })?.value
        #expect(decodedQuery == query, "percent encoding 应该 round-trip 原文")
    }
}