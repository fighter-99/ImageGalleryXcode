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

    // MARK: - V6.70: hasShownMarqueeHint round-trip (替代已删的 hasSeenOnboarding test)

    @Test func hasShownMarqueeHintTogglesCorrectly() {
        // V6.70 (Onboarding removal): hasSeenOnboarding 字段删, 改测同样 bool flag round-trip
        //   hasShownMarqueeHint 控制 MarqueeHintView 首次显示 (V6.21.0 加), 同 UserDefaults flag pattern
        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.hasShownMarqueeHint == false)
        settings.hasShownMarqueeHint = true
        #expect(settings.hasShownMarqueeHint == true)
        settings.hasShownMarqueeHint = false
        #expect(settings.hasShownMarqueeHint == false)
    }

    // V6.19.6 + V6.14.7: isolatedDefaults pattern 防 parallel test 共享状态
    //   改 static let isolatedDefaults = FakeUserDefaults() (跟 UserSettingsTests 同源)
    static let isolatedDefaults: UserDefaults = FakeUserDefaults()
}
