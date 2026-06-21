//
//  CopyNewKeyTests.swift
//  ImageGalleryTests
//
//  V6.62 (P3.1 + P3.2): 新 toast key 测试 — drag-drop fetch 失败提示
//  验证 Copy.toastBatchMoveFetchFailed 接受 reason 字符串并返回本地化结果
//

import Testing
import Foundation
@testable import ImageGallery

struct CopyNewKeyTests {

    @Test func toastBatchMoveFetchFailed_includesReason() {
        // 场景: drag-drop fetch 失败 (DB corruption), 用户看到具体原因
        let msg = Copy.toastBatchMoveFetchFailed("disk full")
        #expect(msg.contains("disk full"))
        #expect(msg.contains("失败") || msg.contains("fail"))
    }
}
