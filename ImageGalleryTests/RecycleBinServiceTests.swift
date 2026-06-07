//
//  RecycleBinServiceTests.swift
//  ImageGalleryTests
//
//  V3.6: RecycleBinService 单元测试
//  范围：
//  - itemsEligibleForPurge 纯函数（按 cutoffDate 过滤）
//  - TrashRetentionDays 契约（case 完整性 + displayName + 默认值 + rawValue 稳定）
//
//  不在范围（避免 in-memory ModelContext 的 SwiftData 复杂性，移到手动验证或阶段 5 扩展）：
//  - recycle/restore/purge 的 SwiftData 持久化路径
//

import Testing
import Foundation
@testable import ImageGallery

struct RecycleBinServiceTests {

    // MARK: - itemsEligibleForPurge

    @Test func itemsEligibleForPurgeFiltersByCutoff() {
        let now = Date()
        let photos = [
            makePhoto(trashedAt: now.addingTimeInterval(-86400 * 10)),   // 10 天前 → 不过期
            makePhoto(trashedAt: now.addingTimeInterval(-86400 * 40)),   // 40 天前 → 过期
            makePhoto(trashedAt: nil),                                    // 在图库 → 不过期
        ]
        let cutoff = now.addingTimeInterval(-86400 * 30)  // 30 天前为分界
        let eligible = RecycleBinService.itemsEligibleForPurge(
            among: photos, cutoffDate: cutoff
        )
        #expect(eligible.count == 1, "只有 40 天前的应该过期")
    }

    @Test func itemsEligibleForPurgeHandlesEmptyInput() {
        #expect(
            RecycleBinService.itemsEligibleForPurge(among: [], cutoffDate: Date()).isEmpty
        )
    }

    @Test func itemsEligibleForPurgeIncludesExactlyOnBoundary() {
        // 边界条件：trashedAt 恰好等于 cutoffDate 时不算过期（用 < 严格比较）
        let now = Date()
        let photos = [
            makePhoto(trashedAt: now),                                    // 刚刚 → 不过期
        ]
        let cutoff = now  // cutoff 恰好 = trashedAt
        let eligible = RecycleBinService.itemsEligibleForPurge(
            among: photos, cutoffDate: cutoff
        )
        #expect(eligible.isEmpty, "trashedAt == cutoffDate 不算过期")
    }

    @Test func itemsEligibleForPurgeHandlesAllExpired() {
        let now = Date()
        let photos = [
            makePhoto(trashedAt: now.addingTimeInterval(-86400 * 100)),
            makePhoto(trashedAt: now.addingTimeInterval(-86400 * 60)),
            makePhoto(trashedAt: now.addingTimeInterval(-86400 * 31)),
        ]
        let cutoff = now.addingTimeInterval(-86400 * 30)
        let eligible = RecycleBinService.itemsEligibleForPurge(
            among: photos, cutoffDate: cutoff
        )
        #expect(eligible.count == 3)
    }

    // MARK: - TrashRetentionDays 契约

    @Test func trashRetentionDaysHasFourCases() {
        #expect(TrashRetentionDays.allCases.count == 4)
    }

    @Test func trashRetentionDaysRawValuesAreStable() {
        // @AppStorage 用 rawValue 作 UserDefaults key，不能随便改
        #expect(TrashRetentionDays.oneDay.rawValue == 1)
        #expect(TrashRetentionDays.sevenDays.rawValue == 7)
        #expect(TrashRetentionDays.thirtyDays.rawValue == 30)
        #expect(TrashRetentionDays.ninetyDays.rawValue == 90)
    }

    @Test func trashRetentionDaysDefaultIsThirtyDays() {
        #expect(TrashRetentionDays.defaultValue == .thirtyDays)
    }

    @Test func trashRetentionDaysDisplayNameIsChineseWithDays() {
        #expect(TrashRetentionDays.oneDay.displayName == "1 天")
        #expect(TrashRetentionDays.sevenDays.displayName == "7 天")
        #expect(TrashRetentionDays.thirtyDays.displayName == "30 天")
        #expect(TrashRetentionDays.ninetyDays.displayName == "90 天")
    }

    @Test func trashRetentionDaysAllCasesHaveUniqueRawValue() {
        let raws = TrashRetentionDays.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    // MARK: - helpers

    /// 构造一个只设了 trashedAt 的 Photo（用于纯函数测试；不写入 SwiftData）
    private func makePhoto(trashedAt: Date?) -> Photo {
        // 用一个虚拟 fileURL（纯函数测试不读文件）
        let dummyURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).jpg")
        let photo = Photo(
            filename: "test.jpg",
            fileURL: dummyURL,
            fileSize: 0,
            width: 0,
            height: 0
        )
        photo.trashedAt = trashedAt
        return photo
    }
}
