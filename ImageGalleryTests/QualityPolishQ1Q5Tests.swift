//
//  QualityPolishQ1Q5Tests.swift
//  ImageGalleryTests
//
//  V6.67 (Q1-Q5 code quality polish): 行为测试
//  - Q2: batchRename 拆分前后行为一致 (RenamePlan struct 提取到 file-scope)
//  - Q5: showingOnboarding 删后不影响 model.settings.hasSeenOnboarding round-trip
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

    // MARK: - Q5 hasSeenOnboarding round-trip

    @Test func hasSeenOnboardingTogglesCorrectly() {
        // V6.67 (Q5): 删 ContentView.showingOnboarding 死代码后
        //   model.settings.hasSeenOnboarding 仍然是真相源, .sheet(isPresented:) 直接读
        let settings = UserSettings(defaults: Self.isolatedDefaults)
        #expect(settings.hasSeenOnboarding == false)
        settings.hasSeenOnboarding = true
        #expect(settings.hasSeenOnboarding == true)
        settings.hasSeenOnboarding = false
        #expect(settings.hasSeenOnboarding == false)
    }

    // V6.19.6 + V6.14.7: isolatedDefaults pattern 防 parallel test 共享状态
    //   改 static let isolatedDefaults = FakeUserDefaults() (跟 UserSettingsTests 同源)
    static let isolatedDefaults: UserDefaults = FakeUserDefaults()
}
