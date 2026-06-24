//
//  WindowFramePersistenceTests.swift
//  ImageGalleryTests
//
//  V6.97.0 P3-2 fix: multi-window frame autosave 跨窗口覆盖 bug
//   单元测试 — 验证 AppDelegate 的 static frame 持久化 helper
//   (loadAllFrames / saveAllFrames / migrateLegacyFrameIfNeeded)
//
//  覆盖场景：
//  - loadAllFrames 默认空字典 (主 key 不存在)
//  - saveAllFrames → loadAllFrames round-trip
//  - 多 window 独立 frame (per-window key 互不覆盖 — bug 核心验证)
//  - backward compat: V3.7.1 老 4 key 存在 → migrate 到主 key
//  - backward compat: 老 4 key 缺失 → no-op
//  - backward compat: migrate 后老 4 key 全部清空
//  - backward compat: idempotent (二次调用 no-op)
//  - backward compat: 主 key 已有同 UUID frame → 保留 (不覆盖更晚写入)
//
//  跟 UserSettingsTests 同样用 FakeUserDefaults + @Suite(.serialized) 防并行污染
//  (memory: swift-testing-userdefaults-parallel-crash)
//

import Testing
import AppKit  // CGRect / NSRect
@testable import ImageGallery

@Suite(.serialized)
struct WindowFramePersistenceTests {

    // V6.97.0: isolated defaults — 跟 UserSettingsTests 同 pattern
    //   FakeUserDefaults 完全 in-memory, 0 cfprefsd 交互
    //   Type 标 FakeUserDefaults (不是 UserDefaults 基类) — clearAll() 是 subclass-only method
    private static let isolatedDefaults = FakeUserDefaults()

    private static func reset() {
        isolatedDefaults.clearAll()
    }

    // MARK: - loadAllFrames / saveAllFrames round-trip

    @Test func loadAllFrames_emptyDefaults_returnsEmpty() {
        Self.reset()
        let frames = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        #expect(frames.isEmpty)
    }

    @Test func saveAllFrames_then_loadAllFrames_roundTripsFrame() throws {
        Self.reset()
        let uuid = "main-window-uuid"
        let frame = CGRect(x: 100, y: 200, width: 1280, height: 800)
        AppDelegate.saveAllFrames([uuid: frame], defaults: Self.isolatedDefaults)
        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        #expect(loaded[uuid] == frame)
    }

    // MARK: - 多 window 独立 frame (bug 核心验证)

    @Test func multipleWindows_haveIndependentFrames() {
        Self.reset()
        let mainUUID = "main-uuid"
        let secondaryUUID = "secondary-uuid"
        let mainFrame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let secondaryFrame = CGRect(x: 1500, y: 100, width: 800, height: 600)

        // 模拟 V3.7.1 bug 场景: 先存主窗口, 再存副窗口, 看是否覆盖
        var frames: [String: CGRect] = [:]
        frames[mainUUID] = mainFrame
        AppDelegate.saveAllFrames(frames, defaults: Self.isolatedDefaults)

        frames[secondaryUUID] = secondaryFrame
        AppDelegate.saveAllFrames(frames, defaults: Self.isolatedDefaults)

        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        // V3.7.1 bug: 两个 window frame 互相覆盖, loaded 只有一个
        // V6.97.0 fix: 两个 frame 都保留
        #expect(loaded[mainUUID] == mainFrame, "主窗口 frame 必须独立保留")
        #expect(loaded[secondaryUUID] == secondaryFrame, "副窗口 frame 必须独立保留")
        #expect(loaded.count == 2)
    }

    @Test func resizeMainWindow_doesNotAffectSecondaryWindow() {
        Self.reset()
        let mainUUID = "main-uuid"
        let secondaryUUID = "secondary-uuid"
        let mainFrame1 = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let secondaryFrame = CGRect(x: 1500, y: 100, width: 800, height: 600)

        var frames: [String: CGRect] = [mainUUID: mainFrame1, secondaryUUID: secondaryFrame]
        AppDelegate.saveAllFrames(frames, defaults: Self.isolatedDefaults)

        // 模拟主窗口 resize — 写新 frame 到主 UUID
        let mainFrame2 = CGRect(x: 0, y: 0, width: 1400, height: 900)
        frames[mainUUID] = mainFrame2
        AppDelegate.saveAllFrames(frames, defaults: Self.isolatedDefaults)

        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        // 主窗口 frame 更新
        #expect(loaded[mainUUID] == mainFrame2, "主窗口新 frame 必须写入")
        // 副窗口 frame 不变 (V3.7.1 bug 表现: 副窗口 frame 会被覆盖成 mainFrame2)
        #expect(loaded[secondaryUUID] == secondaryFrame, "副窗口 frame 必须不变")
    }

    // MARK: - backward compat: V3.7.1 老 4 key → 主 key

    @Test func migrateLegacyFrame_writesToCurrentID_andRemovesLegacyKeys() {
        Self.reset()
        // 模拟 V3.7.1 持久化的 4 个老 key
        Self.isolatedDefaults.set(1200.0, forKey: "imageGalleryWindowSizeW")
        Self.isolatedDefaults.set(900.0, forKey: "imageGalleryWindowSizeH")
        Self.isolatedDefaults.set(100.0, forKey: "imageGalleryWindowPosX")
        Self.isolatedDefaults.set(200.0, forKey: "imageGalleryWindowPosY")
        let legacyFrame = CGRect(x: 100, y: 200, width: 1200, height: 900)

        let newUUID = "new-main-uuid"
        AppDelegate.migrateLegacyFrameIfNeeded(defaults: Self.isolatedDefaults, currentID: newUUID)

        // 老 frame 写到主 key 的 newUUID
        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        #expect(loaded[newUUID] == legacyFrame, "老 frame 必须迁到新 UUID")
        // 4 个老 key 全部清空
        #expect(Self.isolatedDefaults.object(forKey: "imageGalleryWindowSizeW") == nil)
        #expect(Self.isolatedDefaults.object(forKey: "imageGalleryWindowSizeH") == nil)
        #expect(Self.isolatedDefaults.object(forKey: "imageGalleryWindowPosX") == nil)
        #expect(Self.isolatedDefaults.object(forKey: "imageGalleryWindowPosY") == nil)
    }

    @Test func migrateLegacyFrame_noLegacyKeys_isNoOp() {
        Self.reset()
        let newUUID = "new-main-uuid"
        AppDelegate.migrateLegacyFrameIfNeeded(defaults: Self.isolatedDefaults, currentID: newUUID)
        // 主 key 没写入 (老 key 不存在 = 没东西可迁移)
        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        #expect(loaded.isEmpty, "无老 key 时不应写入主 key")
    }

    @Test func migrateLegacyFrame_idempotent_secondCallNoOp() {
        Self.reset()
        Self.isolatedDefaults.set(1200.0, forKey: "imageGalleryWindowSizeW")
        Self.isolatedDefaults.set(900.0, forKey: "imageGalleryWindowSizeH")
        Self.isolatedDefaults.set(100.0, forKey: "imageGalleryWindowPosX")
        Self.isolatedDefaults.set(200.0, forKey: "imageGalleryWindowPosY")

        let firstUUID = "first-uuid"
        AppDelegate.migrateLegacyFrameIfNeeded(defaults: Self.isolatedDefaults, currentID: firstUUID)

        // 第二次调用 (用不同 UUID) — 老 key 已被删, 应该 no-op
        let secondUUID = "second-uuid"
        AppDelegate.migrateLegacyFrameIfNeeded(defaults: Self.isolatedDefaults, currentID: secondUUID)

        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        // 只迁到 firstUUID (第一次调用), secondUUID 不应有 frame
        #expect(loaded[firstUUID] != nil, "第一次调用应迁到 firstUUID")
        #expect(loaded[secondUUID] == nil, "第二次调用 (老 key 已删) 应 no-op")
        #expect(loaded.count == 1)
    }

    @Test func migrateLegacyFrame_preservesExistingFrameForCurrentID() {
        Self.reset()
        // 模拟场景: 已经有用户调过 saveAllFrames 写入 frame, 之后才检测到老 key
        let existingUUID = "existing-uuid"
        let existingFrame = CGRect(x: 50, y: 50, width: 1000, height: 700)
        AppDelegate.saveAllFrames([existingUUID: existingFrame], defaults: Self.isolatedDefaults)

        // 然后发现 V3.7.1 老 key 存在 (理论上不会发生, 但 defensive)
        Self.isolatedDefaults.set(1200.0, forKey: "imageGalleryWindowSizeW")
        Self.isolatedDefaults.set(900.0, forKey: "imageGalleryWindowSizeH")
        Self.isolatedDefaults.set(100.0, forKey: "imageGalleryWindowPosX")
        Self.isolatedDefaults.set(200.0, forKey: "imageGalleryWindowPosY")
        let legacyFrame = CGRect(x: 100, y: 200, width: 1200, height: 900)

        // 调 migrate 用同 UUID — 现有 frame 保留 (不覆盖用户当前 frame)
        AppDelegate.migrateLegacyFrameIfNeeded(defaults: Self.isolatedDefaults, currentID: existingUUID)

        let loaded = AppDelegate.loadAllFrames(defaults: Self.isolatedDefaults)
        #expect(loaded[existingUUID] == existingFrame, "现有 frame 应保留, 不被老 frame 覆盖")
        #expect(loaded[existingUUID] != legacyFrame)
    }
}
