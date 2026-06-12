//
//  SwiftDataLogging.swift
//  ImageGallery
//
//  V4.9.4 NEW: SwiftData 统一错误处理 + os.Logger 封装
//
//  之前 26 处 try? modelContext.save() 静默吞错——保存失败用户无感知
//  改成 ModelContext.saveWithLog() 统一封装：
//  - 成功 → 不做任何事（@discardableResult）
//  - 失败 → Logger.swiftData.error 输出 + 返回 false（调用方可选处理）
//
//  后续要加：
//  - ModelContext.deleteWithLog(_:) 一致的删除日志
//  - ModelContext.fetchWithLog<T>(...) 带 fallback 的 fetch
//

import Foundation
import SwiftData
import os

// MARK: - Subsystem 标识

extension Logger {
    /// V4.9.4: SwiftData 持久化错误日志
    ///   在 Console.app 过滤 subsystem "com.iridescent.ImageGallery" 可看到所有 SwiftData 操作
    ///   category: swiftData
    static let swiftData = Logger(
        subsystem: "com.iridescent.ImageGallery",
        category: "swiftData"
    )

    /// V4.9.4: 图片加载错误日志
    ///   V4.9.5 async loadImageAsync 失败时用这个 log
    static let imageIO = Logger(
        subsystem: "com.iridescent.ImageGallery",
        category: "imageIO"
    )

    /// V4.9.4: 回收站操作错误日志
    ///   RecycleBinService.recycle / restore / permanentDelete 失败时用
    static let recycleBin = Logger(
        subsystem: "com.iridescent.ImageGallery",
        category: "recycleBin"
    )

    /// V5.13.1: 临时 popover 定位诊断日志（修完 bug 删）
    static let popoverDebug = Logger(
        subsystem: "com.iridescent.ImageGallery",
        category: "popoverDebug"
    )
}

// MARK: - SwiftData ModelContext 统一错误处理

extension ModelContext {
    /// V4.9.4: 统一 SwiftData save 错误处理
    /// - 成功：返回 true
    /// - 失败：Logger.swiftData.error 输出 + 返回 false
    /// - 用 @discardableResult：调用方可忽略返回值
    ///
    /// 用法：
    /// ```swift
    /// // 之前: try? modelContext.save()
    /// // 现在: modelContext.saveWithLog()
    ///
    /// // 如需知道是否成功：
    /// let success = modelContext.saveWithLog()
    /// ```
    @discardableResult
    func saveWithLog(onError: ((Error) -> Void)? = nil) -> Bool {
        do {
            try save()
            return true
        } catch {
            Logger.swiftData.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
            onError?(error)
            return false
        }
    }
}
