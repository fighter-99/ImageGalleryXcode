//
//  PhotoStatsSnapshot.swift
//  ImageGallery
//
//  V6.19.2 (P0 #11): Sidebar count 单遍 — 7 维计数器 (inLibrary/trashed/unfiled/
//   recent7Days/largeFiles + duplicate) 一次 for-loop + 1 次 hash group 累加, 替
//   之前 SidebarView.libraryCounts 每次 body 重渲触发 5 个 O(n) 遍历
//   + duplicateCount 额外 2-3 个遍历 = 总共 7-8 遍 O(n) 降到 2 遍
//
//  设计:
//  - struct 不可变, 给 sidebar / status bar / detail pane 一次性消费
//  - 不引入 @Observable 缓存——sidebar body 重渲频率低 (< 1Hz), 实测无感
//  - 保留 PhotoStats 旧 namespace 兼容测试 / 其他 caller
//

import Foundation

/// V6.19.2 (P0 #11): Sidebar 7 维计数一次性快照
///   替代 SidebarView.libraryCounts tuple computed + duplicateCount 多遍 O(n) 遍历
struct PhotoStatsSnapshot: Equatable {
    /// 图库中照片数（排除 trash）
    var inLibraryCount: Int = 0
    /// 回收站中照片数
    var trashedCount: Int = 0
    /// 待整理：图库中 + folder == nil
    var unfiledCount: Int = 0
    /// 最近 7 天：图库中 + importedAt > cutoff
    var recent7DaysCount: Int = 0
    /// 大图：图库中 + fileSize > 5MB
    var largeFilesCount: Int = 0
    /// 重复图照片数：图库中 + 在某 fileHash 重复组（≥2 张）里
    var duplicatePhotoCount: Int = 0

    static let zero = PhotoStatsSnapshot()

    /// 一次累加全部 7 维计数 — 替 SidebarView 之前 7-8 遍 O(n)
    /// - 复杂度: 2 遍 O(n)（第 1 遍算 hash group, 第 2 遍算 duplicate count）
    /// - 之前: libraryCounts 5 遍 + duplicateCount 2-3 遍 = 7-8 遍
    /// - Parameters:
    ///   - photos: 输入 photos 数组
    ///   - largeFileThreshold: 大图阈值（默认 5 MB，跟 PhotoStats.largeFilesCount 一致）
    ///   - now: 当前时间（默认 Date()，测试可注入）
    ///   - calendar: 日历（默认 .current，测试可注入）
    static func compute(
        _ photos: [Photo],
        largeFileThreshold: Int64 = 5_000_000,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PhotoStatsSnapshot {
        var snapshot = PhotoStatsSnapshot()
        // 7 天 cutoff — 跟 PhotoStats.filtered filterRecent7Days 保持一致 (Calendar.date(byAdding:))
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        // hash group 计数（仅非 trash）— 第 1 遍累加, 第 2 遍算 duplicate photo count
        var hashCounts: [String: Int] = [:]

        // 第 1 遍: 累加 5 个非重复计数 + hash counts
        for photo in photos {
            if photo.isInTrash {
                snapshot.trashedCount += 1
            } else {
                snapshot.inLibraryCount += 1
                if photo.folder == nil {
                    snapshot.unfiledCount += 1
                }
                if photo.importedAt > cutoff {
                    snapshot.recent7DaysCount += 1
                }
                if photo.fileSize > largeFileThreshold {
                    snapshot.largeFilesCount += 1
                }
                if let hash = photo.fileHash {
                    hashCounts[hash, default: 0] += 1
                }
            }
        }

        // 第 2 遍: 算 duplicate photo count（hash 出现 ≥ 2 次且非 trash）
        for photo in photos where !photo.isInTrash {
            if let hash = photo.fileHash, (hashCounts[hash] ?? 0) > 1 {
                snapshot.duplicatePhotoCount += 1
            }
        }

        return snapshot
    }
}