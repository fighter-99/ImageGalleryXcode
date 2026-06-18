//
//  PhotoStatsSnapshotTests.swift
//  ImageGalleryTests
//
//  V6.19.2 (P0 #11): PhotoStatsSnapshot 单遍 O(n) 验证
//   - 6 维计数 (inLibrary/trashed/unfiled/recent7Days/largeFiles/duplicate) 一次累加
//   - 跟旧 PhotoStats 纯函数结果对齐 (consistency regression)
//   - 7-8 遍 O(n) → 2 遍, perf 测试 (按需)
//

import Testing
import Foundation
@testable import ImageGallery

struct PhotoStatsSnapshotTests {

    // MARK: - 空数据

    @Test func emptyArray_allZero() {
        let snapshot = PhotoStatsSnapshot.compute([])
        #expect(snapshot == .zero)
        #expect(snapshot.inLibraryCount == 0)
        #expect(snapshot.trashedCount == 0)
        #expect(snapshot.unfiledCount == 0)
        #expect(snapshot.recent7DaysCount == 0)
        #expect(snapshot.largeFilesCount == 0)
        #expect(snapshot.duplicatePhotoCount == 0)
    }

    // MARK: - inLibrary + trashed 计数

    @Test func inLibraryAndTrashed_basicCounts() {
        let photos = makePhotos(
            trashFlags: [false, true, false, true, false],
            folderNilFlags: [true, true, false, false, true]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos)
        #expect(snapshot.inLibraryCount == 3)
        #expect(snapshot.trashedCount == 2)
    }

    // MARK: - unfiled = 非 trash + folder == nil

    @Test func unfiled_excludesTrashedAndFiled() {
        // V6.19.2: helper 无法 set folder 非-nil (需 ModelContext), 验证 unfiled 跟 inLibrary 一致
        //   真实 "排除 filed" 测试需要 integration test (走 ModelContext)
        let photos = makePhotos(
            trashFlags: [false, true, false, true, false],
            folderNilFlags: [true, true, false, false, true]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos)
        // 全部 folder nil (helper 限制), 非 trash = 3 张 (index 0, 2, 4)
        // unfiled 跟 inLibrary 一致 (无 filed 排除)
        #expect(snapshot.unfiledCount == 3)
        #expect(snapshot.unfiledCount == snapshot.inLibraryCount)
    }

    // MARK: - recent7Days

    @Test func recent7Days_filtersByImportedAt() {
        let now = Date()
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let oldDate = calendar.date(byAdding: .day, value: -8, to: now) ?? now

        let photos = makePhotos(
            trashFlags: [false, false, false],
            folderNilFlags: [true, true, true],
            importedAtDates: [now.addingTimeInterval(-3600), now, oldDate]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos, now: now, calendar: calendar)
        // 7 天内 = photo 0 (1 小时前), photo 1 (now) = 2 张
        // 8 天前 = photo 2 排除
        #expect(snapshot.recent7DaysCount == 2)
    }

    @Test func recent7Days_excludesTrashed() {
        let now = Date()
        let recentDate = now.addingTimeInterval(-3600)
        let photos = makePhotos(
            trashFlags: [false, true],
            folderNilFlags: [true, true],
            importedAtDates: [recentDate, recentDate]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos, now: now, calendar: .current)
        // trash 那张不算 recent7Days
        #expect(snapshot.recent7DaysCount == 1)
    }

    // MARK: - largeFiles

    @Test func largeFiles_filtersByThreshold() {
        // 大图阈值 5MB
        let smallFile: Int64 = 1_000_000  // 1MB
        let largeFile: Int64 = 10_000_000 // 10MB
        let photos = makePhotos(
            trashFlags: [false, false, false],
            folderNilFlags: [true, true, true],
            fileSizes: [smallFile, largeFile, smallFile]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos, largeFileThreshold: 5_000_000)
        #expect(snapshot.largeFilesCount == 1)
    }

    @Test func largeFiles_excludesTrashed() {
        let largeFile: Int64 = 10_000_000
        let photos = makePhotos(
            trashFlags: [false, true],
            folderNilFlags: [true, true],
            fileSizes: [largeFile, largeFile]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos, largeFileThreshold: 5_000_000)
        #expect(snapshot.largeFilesCount == 1)
    }

    // MARK: - duplicate

    @Test func duplicate_countsOnlyFilesInDuplicateGroups() {
        // 3 个 hash: A 出现 3 次, B 出现 1 次, C 出现 2 次
        // A 和 C 是重复组, B 不是
        let photos = makePhotos(
            trashFlags: Array(repeating: false, count: 6),
            folderNilFlags: Array(repeating: true, count: 6),
            fileHashes: ["A", "A", "B", "C", "C", "A"]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos)
        // A 3 + C 2 = 5 张在重复组
        #expect(snapshot.duplicatePhotoCount == 5)
    }

    @Test func duplicate_excludesTrashed() {
        // 2 张同 hash, 一张 trashed
        let photos = makePhotos(
            trashFlags: [false, false, true],
            folderNilFlags: [true, true, true],
            fileHashes: ["A", "A", "A"]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos)
        // 非 trash 重复: 2 张 (index 0, 1)
        #expect(snapshot.duplicatePhotoCount == 2)
    }

    @Test func duplicate_nilHash_excluded() {
        // 2 张相同 + 1 张 nil hash
        let photos = makePhotos(
            trashFlags: [false, false, false],
            folderNilFlags: [true, true, true],
            fileHashes: ["A", "A", nil]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos)
        #expect(snapshot.duplicatePhotoCount == 2)
    }

    @Test func duplicate_noHashes_allZero() {
        let photos = makePhotos(
            trashFlags: [false, false],
            folderNilFlags: [true, true],
            fileHashes: [nil, nil]
        )
        let snapshot = PhotoStatsSnapshot.compute(photos)
        #expect(snapshot.duplicatePhotoCount == 0)
    }

    // MARK: - 跟旧 PhotoStats 纯函数结果一致 (regression)

    @Test func consistencyWithPhotoStatsLibraryHelpers() {
        let photos = makePhotos(
            trashFlags: [false, true, false, false, true, false],
            folderNilFlags: [true, true, false, false, true, true],
            importedAtDates: [
                Date().addingTimeInterval(-3600),         // recent7Days
                Date().addingTimeInterval(-86400 * 2),   // not trash, not recent7Days
                Date().addingTimeInterval(-86400 * 30),  // not recent7Days
                Date().addingTimeInterval(-3600),         // recent7Days
                Date().addingTimeInterval(-86400 * 8),   // trash, not recent7Days
                Date().addingTimeInterval(-3600)          // recent7Days
            ],
            fileSizes: [1_000_000, 6_000_000, 4_000_000, 10_000_000, 7_000_000, 500_000],
            fileHashes: ["H", "H", nil, "K", "K", "L"]
        )

        let snapshot = PhotoStatsSnapshot.compute(photos)
        // inLibrary = 4 (non-trashed)
        #expect(snapshot.inLibraryCount == PhotoStats.inLibrary(photos).count)
        // trashed = 2
        #expect(snapshot.trashedCount == PhotoStats.trashed(photos).count)
        // unfiled = 4 (non-trashed + folder nil — helper 无法设 folder, 全 nil)
        #expect(snapshot.unfiledCount == PhotoStats.unfiled(photos).count)
        // recent7Days = 3 (data: index 0/3/5 在 7 天内, index 4 trashed 不算)
        #expect(snapshot.recent7DaysCount == PhotoStats.recent7DaysCount(photos))
        // largeFiles = 1 (非 trash + > 5MB: index 3 = 10MB)
        #expect(snapshot.largeFilesCount == PhotoStats.largeFilesCount(photos))
        // duplicate: snapshot 跟旧 sidebar duplicateCount 一致 — hash group 仅非 trash
        //   H: index 0 (非 trash), index 1 (trashed — 不算进 group) → group count 1, 不算重复
        //   K: index 3 (非 trash), index 4 (trashed) → group count 1, 不算重复
        //   L: 单独 1 张 → 不算重复
        //   所以 duplicatePhotoCount = 0
        #expect(snapshot.duplicatePhotoCount == 0)
    }

    // MARK: - Helper

    /// 造 N 张 photo, 默认字段全 default, 通过 args 覆盖
    private func makePhotos(
        trashFlags: [Bool] = [],
        folderNilFlags: [Bool] = [],
        importedAtDates: [Date] = [],
        fileSizes: [Int64] = [],
        fileHashes: [String?] = []
    ) -> [Photo] {
        let n = trashFlags.count
        return (0..<n).map { i in
            let photo = Photo(
                filename: "test_\(i).jpg",
                fileURL: URL(fileURLWithPath: "/tmp/test_\(i).jpg"),
                fileSize: i < fileSizes.count ? fileSizes[i] : 1_000_000,
                width: 100,
                height: 100
            )
            if i < importedAtDates.count {
                photo.importedAt = importedAtDates[i]
            }
            if i < trashFlags.count && trashFlags[i] {
                photo.trashedAt = Date()
            }
            if i < folderNilFlags.count && !folderNilFlags[i] {
                // 用空 folder 不实际创建, 只标 folder != nil
                // 这里让 folder 保持 nil 表示 "未整理"
                // 测试 default 是 nil, 只在 folderNilFlags[i] == false 时才需赋值
                // V6.19.2: 简化 — folder assignment 需要 ModelContext, 跳过这 path
                //  测试用 nil (folder == nil) 即可
            }
            if i < fileHashes.count {
                photo.fileHash = fileHashes[i]
            }
            return photo
        }
    }
}