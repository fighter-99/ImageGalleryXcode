//
//  CrashReporter.swift
//  ImageGallery
//
//  V6.64.2 (可用性 + UX): 崩溃日志捕获
//
//  设计:
//  - 监听 uncaught exception + POSIX 信号 (SIGSEGV / SIGABRT / SIGBUS / SIGFPE / SIGILL)
//  - 写 ~/Library/Logs/ImageGallery/crash-<timestamp>.log
//  - log 内容: 异常名 + reason + call stack + 系统版本 + app version
//  - 不发邮件 (隐私), 让用户主动 Help 菜单 "在 Finder 中显示崩溃日志" 附给 bug report
//
//  Photos 真版行为: macOS Sonoma+ Photos.app 有匿名 crash report (NSUserNotification),
//    ImageGallery 没接入 Crashlytics / Sentry — 不传任何用户数据, 本地 log 让用户决定
//
//  Swift 实现注意:
//  - NSSetUncaughtExceptionHandler / signal() 都接 C function pointer (@convention(c))
//  - Swift closure 不能 capture context (报错 "C function pointer cannot be formed from closure")
//  - 用全局 @_cdecl 函数 + 全局静态变量传递信息
//

import Foundation
import AppKit
import os.log

// MARK: - V6.64.2: 全局 @_cdecl handler + 全局变量传递
//
//  Swift @_cdecl 函数不能放 enum 内 (enum 是 value type), 放 file-level.
//  全局变量是 process 唯一的, 多次 install() 会覆盖 (设计意图: idempotent 防重挂)

private var crashType: String = ""
private var crashName: String = ""
private var crashReason: String = ""
private var crashStack: String = ""

/// V6.64.2: C 兼容的 uncaught exception handler — @_cdecl 函数名固定
@_cdecl("imageGalleryUncaughtExceptionHandler")
private func handleUncaughtException(_ exception: NSException) {
    crashType = "UncaughtException"
    crashName = exception.name.rawValue
    crashReason = exception.reason ?? ""
    crashStack = exception.callStackSymbols.joined(separator: "\n")
    CrashReporter.writeCrashLogFile()
}

/// V6.64.2: C 兼容的 signal handler
@_cdecl("imageGallerySignalHandler")
private func handleSignal(_ sig: Int32) {
    crashType = "Signal"
    // 通过 sig 反推名字 (SIGSEGV / SIGABRT 等)
    crashName = signalName(sig)
    crashReason = "Signal \(sig) received"
    crashStack = Thread.callStackSymbols.joined(separator: "\n")
    CrashReporter.writeCrashLogFile()
    // 调 SIG_DFL 让系统正常处理 (terminate + 产生 core dump 供 Xcode 查看)
    Darwin.signal(sig, SIG_DFL)
    raise(sig)
}

/// V6.64.2: sig → 名字
private func signalName(_ sig: Int32) -> String {
    switch sig {
    case SIGSEGV: return "SIGSEGV"
    case SIGABRT: return "SIGABRT"
    case SIGBUS:  return "SIGBUS"
    case SIGFPE:  return "SIGFPE"
    case SIGILL:  return "SIGILL"
    default:      return "SIG\(sig)"
    }
}

// MARK: - V6.64.2: CrashReporter enum (公开 API)

enum CrashReporter {
    /// V6.64.2: 启动 crash reporter (调一次即可, 通常在 AppDelegate.applicationDidFinishLaunching)
    /// - 安全 idempotent: 多次调用不会重复挂 handler (UserDefaults 标记)
    static func install() {
        let key = "crashReporterInstalled"
        guard UserDefaults.standard.bool(forKey: key) == false else { return }
        UserDefaults.standard.set(true, forKey: key)

        // 1. uncaught exception handler
        NSSetUncaughtExceptionHandler(handleUncaughtException)

        // 2. POSIX signal handler (5 个致命信号)
        Darwin.signal(SIGSEGV, handleSignal)
        Darwin.signal(SIGABRT, handleSignal)
        Darwin.signal(SIGBUS, handleSignal)
        Darwin.signal(SIGFPE, handleSignal)
        Darwin.signal(SIGILL, handleSignal)

        os_log("CrashReporter installed", log: .default, type: .info)
    }

    /// V6.64.2: 写 crash log 文件 + os_log — 由全局 @_cdecl handler 调用
    ///   - 文件路径: ~/Library/Logs/ImageGallery/crash-<unix-timestamp>.log
    ///   - 内容: 类型 + 名称 + reason + call stack + 系统版本 + app 版本
    static func writeCrashLogFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let iso = formatter.string(from: Date())

        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = AppVersion.current.shortString

        let body = """
        ============================
        ImageGallery Crash Report
        ============================
        Time:     \(iso) (unix \(timestamp))
        Type:     \(crashType)
        Name:     \(crashName)
        Reason:   \(crashReason.isEmpty ? "(none)" : crashReason)
        macOS:    \(systemVersion)
        App:      ImageGallery \(appVersion)

        --- Call stack ---
        \(crashStack)

        --- End of report ---
        """

        let logsDir = logDirectory()
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent("crash-\(timestamp).log")
        try? body.write(to: logFile, atomically: true, encoding: .utf8)

        // 也写 os_log 供 Console.app
        os_log("Crash: %{public}@", log: .default, type: .fault, body)
    }

    /// V6.64.2: ~/Library/Logs/ImageGallery/ 目录
    static func logDirectory() -> URL {
        let home = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return home.appendingPathComponent("Logs/ImageGallery", isDirectory: true)
    }

    /// V6.64.2: 在 Finder 打开 log 目录 — Help 菜单 "在 Finder 中显示崩溃日志" 调用
    @MainActor
    static func revealLogsInFinder() {
        let dir = logDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}