//
//  Wave1A11yCrashTests.swift
//  ImageGalleryTests
//
//  V6.64.1 + V6.64.2: A11y + Crash Reporter 单元测试
//  - Copy.a11yShortcutPrefix / a11yActionOnSelectedHint 锁定
//  - AppVersion.shortString 锁定
//  - CrashReporter.logDirectory 路径正确
//  - SettingsLinks 真 URL (非 placeholder)
//

import Testing
import Foundation
@testable import ImageGallery

struct Wave1A11yCrashTests {

    // MARK: - Copy.a11y* (V6.64.1)

    @Test func a11yShortcutPrefixIsLocked() {
        // 锁定 VoiceOver help 前缀 "快捷键"——防未来改动破坏 toolbar a11y
        #expect(Copy.a11yShortcutPrefix == "快捷键")
    }

    @Test func a11yActionOnSelectedHintIncludesCount() {
        // "对 5 张照片执行操作" — destructive action VoiceOver hint
        let hint = Copy.a11yActionOnSelectedHint(5)
        #expect(hint.contains("5"))
        #expect(hint.contains("照片"))
    }

    // MARK: - Copy.helpRevealCrashLogs (V6.64.2)

    @Test func helpRevealCrashLogsIsLocked() {
        #expect(Copy.helpRevealCrashLogs.contains("Finder"))
        #expect(Copy.helpRevealCrashLogs.contains("崩溃") || Copy.helpRevealCrashLogs.contains("日志"))
    }

    // MARK: - AppVersion.shortString (V6.64.2)

    @Test func appVersionShortStringFormat() {
        // V6.64.2: shortString 用于 crash log header — "1.0 (1)"
        let v = AppVersion(marketing: "6.64", build: "100")
        #expect(v.shortString == "6.64 (100)")
    }

    // MARK: - SettingsLinks 真 URL (V6.64.2)

    @Test func settingsLinksPointToRealGitHubRepo() {
        // V6.64.2: 占位 "github.com/" 改为 fighter-99/ImageGalleryXcode
        //   之前是 placeholder (打开 GitHub root), 现在点开直接到真仓库
        #expect(SettingsLinks.projectHomepage.contains("fighter-99/ImageGalleryXcode"))
        #expect(SettingsLinks.helpDocs.contains("fighter-99/ImageGalleryXcode"))
        #expect(SettingsLinks.issueTracker.contains("fighter-99/ImageGalleryXcode"))
        #expect(SettingsLinks.issueTracker.contains("/issues"))
    }

    // MARK: - CrashReporter.logDirectory (V6.64.2)

    @Test func crashReporterLogDirectoryIsLibraryLogs() {
        // V6.64.2: ~/Library/Logs/ImageGallery/ — 跟 macOS Apple 系统 log 规范一致
        let dir = CrashReporter.logDirectory()
        let pathComponents = dir.pathComponents
        #expect(pathComponents.contains("Library"))
        #expect(pathComponents.contains("Logs"))
        #expect(pathComponents.contains("ImageGallery"))
    }
}
