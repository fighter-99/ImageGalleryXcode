//
//  RecentPhotosStore.swift
//  ImageGallery
//
//  V4.36.x: 工具栏 Mac 原生感增强——File > Open Recent 菜单
//  跟踪最近导入的照片（最多 20 个），存储到 UserDefaults
//  macOS 标准：File > Open Recent 菜单项，点击 → 在 Finder 中显示
//
//  工作流：
//  - 用户导入照片 → ImageImporter 调 recordImport(_:) 添加
//  - File > Open Recent 菜单展示最近导入
//  - 点击 recent → NSWorkspace.activateFileViewerSelecting 揭示文件
//

import AppKit
import Foundation
import Observation  // V6.11: @Observable (macOS 14+)

/// 跟踪最近导入的照片 URL（最多 20 个）
/// V4.36.x: 给 File > Open Recent 菜单提供数据
/// V6.11: @Observable 升级——V6.08 #24 留, 之前 RecentPhotosStoreObservable 包装
///   类 + @ObservedObject 跟项目其他 model 风格不一致 (ContentViewModel/PhotoStats
///   都用 @Observable)。直接给 RecentPhotosStore 加 @Observable 即可, 删包装类
@MainActor
@Observable
final class RecentPhotosStore {
    static let shared = RecentPhotosStore()

    /// UserDefaults key
    private static let storageKey = "recentPhotos.paths"

    /// 最多保留 20 个
    private let maxCount = 20

    // V6.11: 去掉 private(set)——@Observable 跟踪读写, 外部只读
    //   模式跟 ContentViewModel 一致 (model 直接 @Observable, 不需要包装)
    var urls: [URL] = []

    private init() {
        load()
    }

    /// 记录导入的 URL（去重 + 最新在前 + 截断到 20）
    func recordImport(_ url: URL) {
        // 去重：移除已存在的同路径
        urls.removeAll { $0.path == url.path }
        // 最新在前
        urls.insert(url, at: 0)
        // 截断
        if urls.count > maxCount {
        urls = Array(urls.prefix(maxCount))
        }
        save()
    }

    /// 记录多个 URL
    func recordImports(_ newURLs: [URL]) {
        for url in newURLs {
            urls.removeAll { $0.path == url.path }
            urls.insert(url, at: 0)
        }
        if urls.count > maxCount {
            urls = Array(urls.prefix(maxCount))
        }
        save()
    }

    /// 清空所有
    func clear() {
        urls.removeAll()
        save()
    }

    /// 在 Finder 中揭示文件
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 持久化

    private func load() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        urls = paths.compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() {
        let paths = urls.map { $0.path }
        UserDefaults.standard.set(paths, forKey: Self.storageKey)
    }
}
