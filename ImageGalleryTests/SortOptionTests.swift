//
//  SortOptionTests.swift
//  ImageGalleryTests
//
//  V3.5.D：SortOption 单元测试。
//  覆盖所有 case 的 label/shortLabel/toggledDirection/apply,
//  防止以后加新 case 时漏改某个属性。
//

import Foundation
import Testing
@testable import ImageGallery

struct SortOptionTests {
    // MARK: - 标签完整性

    @Test func allCasesHaveNonEmptyLabel() {
        for option in SortOption.allCases {
            #expect(!option.label.isEmpty, "\(option.rawValue) 应该有非空 label")
        }
    }

    @Test func allCasesHaveNonEmptyShortLabel() {
        for option in SortOption.allCases {
            #expect(!option.shortLabel.isEmpty, "\(option.rawValue) 应该有非空 shortLabel")
        }
    }

    @Test func allCasesHaveNonEmptyDirectionIcon() {
        for option in SortOption.allCases {
            #expect(!option.directionIcon.isEmpty, "\(option.rawValue) 应该有非空 directionIcon")
        }
    }

    // MARK: - 短标签按字段聚合

    @Test func importedTimeShortLabelIsSame() {
        #expect(SortOption.importedAtDesc.shortLabel == "导入时间")
        #expect(SortOption.importedAtAsc.shortLabel == "导入时间")
    }

    @Test func filenameShortLabelIsSame() {
        #expect(SortOption.filenameAsc.shortLabel == "文件名")
        #expect(SortOption.filenameDesc.shortLabel == "文件名")
    }

    @Test func fileSizeShortLabelIsSame() {
        #expect(SortOption.fileSizeDesc.shortLabel == "文件大小")
        #expect(SortOption.fileSizeAsc.shortLabel == "文件大小")
    }

    // MARK: - 方向切换

    @Test func toggleDirectionInvertsAscDesc() {
        #expect(SortOption.importedAtDesc.toggledDirection == .importedAtAsc)
        #expect(SortOption.importedAtAsc.toggledDirection == .importedAtDesc)
        #expect(SortOption.filenameAsc.toggledDirection == .filenameDesc)
        #expect(SortOption.filenameDesc.toggledDirection == .filenameAsc)
        #expect(SortOption.fileSizeDesc.toggledDirection == .fileSizeAsc)
        #expect(SortOption.fileSizeAsc.toggledDirection == .fileSizeDesc)
    }

    @Test func customOrderToggleStaysSame() {
        // 自定义排序没有方向概念,切换应该保持
        #expect(SortOption.customOrder.toggledDirection == .customOrder)
    }

    // MARK: - 排序逻辑

    /// 创建带 importedAt 的测试 Photo
    private static func makePhoto(id: Int, daysAgo: Int, filename: String, fileSize: Int64) -> Photo {
        let photo = Photo(
            filename: filename,
            fileURL: URL(fileURLWithPath: "/tmp/\(filename)"),
            fileSize: fileSize,
            width: 100,
            height: 100
        )
        photo.importedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return photo
    }

    @Test func applyImportedAtDescReturnsNewestFirst() {
        let p1 = Self.makePhoto(id: 1, daysAgo: 10, filename: "a.jpg", fileSize: 100)
        let p2 = Self.makePhoto(id: 2, daysAgo: 1, filename: "b.jpg", fileSize: 100)
        let p3 = Self.makePhoto(id: 3, daysAgo: 5, filename: "c.jpg", fileSize: 100)
        let result = SortOption.importedAtDesc.apply(to: [p1, p2, p3])
        #expect(result.map { $0.filename } == ["b.jpg", "c.jpg", "a.jpg"])
    }

    @Test func applyImportedAtAscReturnsOldestFirst() {
        let p1 = Self.makePhoto(id: 1, daysAgo: 10, filename: "a.jpg", fileSize: 100)
        let p2 = Self.makePhoto(id: 2, daysAgo: 1, filename: "b.jpg", fileSize: 100)
        let p3 = Self.makePhoto(id: 3, daysAgo: 5, filename: "c.jpg", fileSize: 100)
        let result = SortOption.importedAtAsc.apply(to: [p1, p2, p3])
        #expect(result.map { $0.filename } == ["a.jpg", "c.jpg", "b.jpg"])
    }

    @Test func applyFileSizeDescReturnsLargestFirst() {
        let p1 = Self.makePhoto(id: 1, daysAgo: 0, filename: "small.jpg", fileSize: 100)
        let p2 = Self.makePhoto(id: 2, daysAgo: 0, filename: "big.jpg", fileSize: 1000)
        let p3 = Self.makePhoto(id: 3, daysAgo: 0, filename: "mid.jpg", fileSize: 500)
        let result = SortOption.fileSizeDesc.apply(to: [p1, p2, p3])
        #expect(result.map { $0.filename } == ["big.jpg", "mid.jpg", "small.jpg"])
    }

    @Test func applyFileSizeAscReturnsSmallestFirst() {
        let p1 = Self.makePhoto(id: 1, daysAgo: 0, filename: "small.jpg", fileSize: 100)
        let p2 = Self.makePhoto(id: 2, daysAgo: 0, filename: "big.jpg", fileSize: 1000)
        let p3 = Self.makePhoto(id: 3, daysAgo: 0, filename: "mid.jpg", fileSize: 500)
        let result = SortOption.fileSizeAsc.apply(to: [p1, p2, p3])
        #expect(result.map { $0.filename } == ["small.jpg", "mid.jpg", "big.jpg"])
    }

    @Test func applyFilenameAscAlphabetical() {
        let p1 = Self.makePhoto(id: 1, daysAgo: 0, filename: "banana.jpg", fileSize: 100)
        let p2 = Self.makePhoto(id: 2, daysAgo: 0, filename: "apple.jpg", fileSize: 100)
        let p3 = Self.makePhoto(id: 3, daysAgo: 0, filename: "cherry.jpg", fileSize: 100)
        let result = SortOption.filenameAsc.apply(to: [p1, p2, p3])
        #expect(result.map { $0.filename } == ["apple.jpg", "banana.jpg", "cherry.jpg"])
    }

    // MARK: - 自定义排序

    @Test func applyCustomOrderSortsBySortOrder() {
        let p1 = Self.makePhoto(id: 1, daysAgo: 0, filename: "a.jpg", fileSize: 100)
        let p2 = Self.makePhoto(id: 2, daysAgo: 0, filename: "b.jpg", fileSize: 100)
        let p3 = Self.makePhoto(id: 3, daysAgo: 0, filename: "c.jpg", fileSize: 100)
        // 故意打乱 sortOrder
        p1.sortOrder = 30
        p2.sortOrder = 10
        p3.sortOrder = 20
        let result = SortOption.customOrder.apply(to: [p1, p2, p3])
        #expect(result.map { $0.filename } == ["b.jpg", "c.jpg", "a.jpg"])
    }

    // MARK: - 完整性:case 数量 = 7(防漏 case)

    @Test func allCasesCountIsSeven() {
        // 3 字段 × 2 方向 + 1 customOrder = 7
        #expect(SortOption.allCases.count == 7)
    }
}
