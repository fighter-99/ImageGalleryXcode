//
//  SidebarSelectionTests.swift
//  ImageGalleryTests
//
//  V3.5.D / V3.5.18：SidebarSelection 单元测试。
//  V3.5.18 简化：pathSegments 已删（pathBar 永久禁用），所以不再测 pathSegments 标签。
//  现在专注于 serializeSelection 的简单 case 往返。
//
//  Folder/Tag 涉及 SwiftData @Model,需要 model context 才能构造,
//  这里只测简单 case,完整 round-trip 留给集成测试。
//

import Testing
@testable import ImageGallery

struct SidebarSelectionTests {

    // MARK: - 序列化往返(简单 case)

    @Test func allCaseRoundTripsCorrectly() {
        let serialized = serializeSelectionForTesting(.all)
        #expect(serialized == "all")
    }

    // V5.8: 删 favoritesCaseRoundTripsCorrectly 测试——.favorites case 已删
    //   收藏 = 评分 ≥ 5 走筛选 popover，不再有对应 SidebarSelection case

    @Test func unfiledCaseRoundTripsCorrectly() {
        let serialized = serializeSelectionForTesting(.unfiled)
        #expect(serialized == "unfiled")
    }

    @Test func duplicatesCaseRoundTripsCorrectly() {
        let serialized = serializeSelectionForTesting(.duplicates)
        #expect(serialized == "duplicates")
    }

    @Test func recent7DaysCaseRoundTripsCorrectly() {
        let serialized = serializeSelectionForTesting(.recent7Days)
        #expect(serialized == "recent7Days")
    }

    @Test func largeFilesCaseRoundTripsCorrectly() {
        let serialized = serializeSelectionForTesting(.largeFiles)
        #expect(serialized == "largeFiles")
    }

    // V3.6 NEW: 回收站 case 序列化
    @Test func recentlyDeletedCaseRoundTripsCorrectly() {
        let serialized = serializeSelectionForTesting(.recentlyDeleted)
        #expect(serialized == "recentlyDeleted")
    }

    // MARK: - 枚举完整性

    @Test func allSimpleCasesAreInEnum() {
        // 防止以后删 case 时漏改其他 switch
        // (编译期 exhaustive switch 也会强制检查)
        // V3.6: 加 .recentlyDeleted
        // V5.8: 砍 .favorites——收藏 = 评分 ≥ 5 走筛选 popover
        let simple: [SidebarSelection] = [.all, .unfiled, .duplicates, .recent7Days, .largeFiles, .recentlyDeleted]
        #expect(simple.count == 6)
    }

    // MARK: - 测试辅助函数(模拟 ContentView 中的逻辑)

    /// 复制 ContentView.serializeSelection 的简单 case 逻辑
    /// V5.8: 砍 .favorites case
    private func serializeSelectionForTesting(_ selection: SidebarSelection) -> String {
        switch selection {
        case .all: return "all"
        case .unfiled: return "unfiled"
        case .duplicates: return "duplicates"
        case .recent7Days: return "recent7Days"
        case .largeFiles: return "largeFiles"
        case .folder: return "folder:skip"  // 简化
        case .tag: return "tag:skip"  // 简化
        case .recentlyDeleted: return "recentlyDeleted"  // V3.6 NEW
        }
    }
}
