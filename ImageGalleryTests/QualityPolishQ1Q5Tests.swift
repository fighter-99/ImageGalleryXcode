//
//  QualityPolishQ1Q5Tests.swift
//  ImageGalleryTests
//
//  V6.67 (Q1-Q5 code quality polish): 行为测试
//  - Q2: batchRename 拆分前后行为一致 (RenamePlan struct 提取到 file-scope)
//  - V6.70: hasSeenOnboarding 字段已删, 改测 hasShownMarqueeHint round-trip
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct QualityPolishQ1Q5Tests {

    // MARK: - Q2 RenamePlan 提取

    @Test func renamePlanFieldsMatchExpected() {
        // V6.67 (Q2): RenamePlan 从 batchRename 局部 struct 提到 file-scope (private)
        //   不直接测试 (private), 但确保 batchRename 整体仍能跑 (回归靠 641 unit tests)
        //   这里只验证 BatchRenameTemplate.render 仍然 work — RenamePlan 依赖它
        let rendered = try? BatchRenameTemplate.render(
            template: "{n}",
            index: 1,
            totalCount: 1,
            originalFilename: "IMG"
        )
        #expect(rendered == "1")
    }

    // V6.74.6: 删 hasShownMarqueeHintTogglesCorrectly — UserSettings.hasShownMarqueeHint 字段已删
    //   MarqueeHintView 浮层整体撤掉 (用户报"有时候会弹出来拖动框选多张照片提示"), 字段 + test 一起清

    // V6.19.6 + V6.14.7: isolatedDefaults pattern 防 parallel test 共享状态
    //   改 static let isolatedDefaults = FakeUserDefaults() (跟 UserSettingsTests 同源)
    static let isolatedDefaults: UserDefaults = FakeUserDefaults()
}
