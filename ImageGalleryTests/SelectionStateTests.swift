//
//  SelectionStateTests.swift
//  ImageGalleryTests
//
//  V3.6.52：SelectionState 派生/批量方法的纯函数测试。
//
//  覆盖（13 个 @Test）：
//  - 派生查询 × 6：isEmpty / hasSelection / isMultiSelect / singleSelectedID (3 cases) / contains
//  - 批量过滤 × 2：selectedPhotos(in:) / selectedPhotos(in:) 空匹配
//  - 状态变更 × 5：cleared / selectingSingle / toggling add+remove / removing
//
//  测试模式：参考 MultiSelectMathTests——纯函数，零 SwiftData 依赖。
//  V3.6.28 教训：纯函数 seam 不接 [Photo]——本次 selectedPhotos(in:) 接 [Photo]
//  但只读其 .id 字段，仍是 SwiftData-agnostic，测试用本地构造的 stub 即可。
//

import Foundation
import Testing
@testable import ImageGallery

struct SelectionStateTests {

    // MARK: - 辅助

    /// 5 张图 [A, B, C, D, E] 的 ID 数组
    private func fivePhotoIDs() -> [UUID] {
        (0..<5).map { _ in UUID() }
    }

    /// 5 个 [Photo] stub——SwiftData @Model 类 init 内部 self.id = UUID()，不可覆盖
    /// 所以测试用例总是从 stubs.map(\.id) 派生 ID，避免依赖具体值
    /// 注意：这些 stub 不入 SwiftData context（不调 modelContext.insert）
    /// 所以不会触发并发冲突（V3.6.28 教训）
    private func fivePhotoStubs() -> [Photo] {
        (0..<5).map { _ in Photo(
            filename: "stub.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/stub.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        ) }
    }

    // MARK: - 派生查询

    @Test func emptyStateIsEmpty() {
        let s = SelectionState()
        #expect(s.isEmpty)
        #expect(!s.hasSelection)
        #expect(!s.isMultiSelect)
        #expect(s.singleSelectedID == nil)
    }

    @Test func onlySelectedPhotoIDIsHasSelection() {
        // 只有 selectedPhotoID，没有 selectedIDs → hasSelection 为 true，isMultiSelect 为 false
        let id = UUID()
        let s = SelectionState(selectedPhotoID: id)
        #expect(!s.isEmpty)
        #expect(s.hasSelection)
        #expect(!s.isMultiSelect)
        #expect(s.singleSelectedID == id, "selectedPhotoID 单独存在时应作为 single")
    }

    @Test func onlySelectedIDsIsHasSelection() {
        let ids = fivePhotoIDs()
        let s = SelectionState(selectedIDs: [ids[2]])
        #expect(!s.isEmpty)
        #expect(s.hasSelection)
        #expect(!s.isMultiSelect, "1 张不算多选")
        #expect(s.singleSelectedID == ids[2])
    }

    @Test func multiSelectIsMultiSelect() {
        let ids = fivePhotoIDs()
        let s = SelectionState(selectedIDs: [ids[0], ids[1], ids[2]])
        #expect(s.isMultiSelect)
        #expect(s.hasSelection)
        #expect(!s.isEmpty)
        // 关键：多选时 singleSelectedID 强制为 nil（与原 singleSelectedID 派生逻辑一致）
        #expect(s.singleSelectedID == nil, ">1 张时 singleSelectedID 应为 nil")
    }

    @Test func singleSelectedIDPrefersSelectedIDsFirst() {
        // selectedIDs 优先于 selectedPhotoID（与 V3.6.30 原 singleSelectedID 派生一致）
        let ids = fivePhotoIDs()
        let s = SelectionState(
            selectedIDs: [ids[2]],
            selectedPhotoID: ids[4]
        )
        #expect(s.singleSelectedID == ids[2], "selectedIDs.first 优先于 selectedPhotoID")
    }

    @Test func containsChecksSetMembership() {
        let ids = fivePhotoIDs()
        let s = SelectionState(selectedIDs: [ids[1], ids[3]])
        #expect(s.contains(ids[1]))
        #expect(s.contains(ids[3]))
        #expect(!s.contains(ids[0]))
        #expect(!s.contains(ids[2]))
        #expect(!s.contains(ids[4]))
    }

    // MARK: - 批量过滤

    @Test func selectedPhotosFiltersAndPreservesOrder() {
        // selectedPhotos(in:) 保持输入顺序（不重排）
        let stubs = fivePhotoStubs()
        // 选中 {C, A}（顺序：A, B, C, D, E）→ 期望返回顺序 [A, C]
        let s = SelectionState(selectedIDs: [stubs[2].id, stubs[0].id])
        let result = s.selectedPhotos(in: stubs)
        #expect(result.map(\.id) == [stubs[0].id, stubs[2].id], "保持输入顺序")
        #expect(result.count == 2)
    }

    @Test func selectedPhotosEmptyWhenNoMatch() {
        let stubs = fivePhotoStubs()
        let s = SelectionState(selectedIDs: [UUID()])  // 随机 ID 不在 stubs 里
        let result = s.selectedPhotos(in: stubs)
        #expect(result.isEmpty, "无匹配时返回空数组（不抛错）")
    }

    // MARK: - singlePhoto(in:) — V3.6.52 优化

    @Test func singlePhotoReturnsMatchedSingleSelection() {
        // 单选（selectedIDs.count == 1）→ 返回匹配 photo
        let stubs = fivePhotoStubs()
        let s = SelectionState(selectedIDs: [stubs[2].id])
        #expect(s.singlePhoto(in: stubs)?.id == stubs[2].id)
    }

    @Test func singlePhotoReturnsMatchedDetailPanelWhenIDsEmpty() {
        // 边界：selectedIDs 空但 selectedPhotoID 有值（detail panel 还指着某图）
        let stubs = fivePhotoStubs()
        let s = SelectionState(selectedPhotoID: stubs[1].id)
        #expect(s.singlePhoto(in: stubs)?.id == stubs[1].id)
    }

    @Test func singlePhotoReturnsNilForMultiSelect() {
        // 关键不变量：>1 张时 singlePhoto 必须为 nil（多选隐藏 detail）
        let stubs = fivePhotoStubs()
        let s = SelectionState(
            selectedIDs: [stubs[0].id, stubs[1].id],
            selectedPhotoID: stubs[0].id  // 即使 selectedPhotoID 还在，也应被 multi 压过
        )
        #expect(s.singlePhoto(in: stubs) == nil, "多选时 singlePhoto 应为 nil")
    }

    @Test func singlePhotoReturnsNilWhenNotInPhotos() {
        // 单选但 photo 不在传入的 photos 里（典型场景：sidebar 切换后旧选中不在新 visible）
        let stubs = fivePhotoStubs()
        let orphanID = UUID()
        let s = SelectionState(selectedIDs: [orphanID])
        #expect(s.singlePhoto(in: stubs) == nil, "photo 不在 photos 里应返回 nil")
    }

    @Test func singlePhotoEmptySelection() {
        // 完全无选中 → nil
        let stubs = fivePhotoStubs()
        let s = SelectionState()
        #expect(s.singlePhoto(in: stubs) == nil)
    }

    // MARK: - 状态变更

    @Test func clearedReturnsEmpty() {
        let ids = fivePhotoIDs()
        let s = SelectionState(
            selectedIDs: [ids[0], ids[1]],
            lastSelectedID: ids[0],
            selectedPhotoID: ids[1]
        )
        let cleared = s.cleared
        #expect(cleared.isEmpty)
        #expect(cleared.selectedIDs.isEmpty)
        #expect(cleared.lastSelectedID == nil)
        #expect(cleared.selectedPhotoID == nil)
        // 原 state 不变（值语义）
        #expect(s.selectedIDs.count == 2, "原 state 应保持不变")
    }

    @Test func emptyStaticMatchesCleared() {
        // .empty static 与 .cleared 应等价
        #expect(SelectionState.empty.isEmpty)
        #expect(SelectionState.empty == SelectionState().cleared)
    }

    @Test func selectingSingleReplacesAllFields() {
        let ids = fivePhotoIDs()
        let old = SelectionState(
            selectedIDs: [ids[0], ids[1]],
            lastSelectedID: ids[0],
            selectedPhotoID: ids[1]
        )
        let newID = ids[3]
        let single = old.selectingSingle(newID)
        #expect(single.selectedIDs == [newID], "单选清空多选并设自己")
        #expect(single.lastSelectedID == newID)
        #expect(single.selectedPhotoID == newID, "单选激活详情面板")
    }

    @Test func togglingAddThenRemove() {
        let ids = fivePhotoIDs()
        let initial = SelectionState()
        // 第一次 toggle：加入
        let added = initial.toggling(ids[2])
        #expect(added.selectedIDs == [ids[2]])
        #expect(added.lastSelectedID == ids[2])
        // 第二次 toggle：移除
        let removed = added.toggling(ids[2])
        #expect(removed.selectedIDs.isEmpty)
        #expect(removed.lastSelectedID == ids[2], "lastSelectedID 始终更新为本次操作 ID")
    }

    @Test func togglingPreservesOtherIDs() {
        // toggle 只能改变目标 ID，其他 ID 不动
        let ids = fivePhotoIDs()
        let initial = SelectionState(selectedIDs: [ids[0], ids[2]])
        let result = initial.toggling(ids[4])
        #expect(result.selectedIDs == [ids[0], ids[2], ids[4]])
    }

    @Test func removingAlsoClearsRelatedFields() {
        let ids = fivePhotoIDs()
        let s = SelectionState(
            selectedIDs: [ids[0], ids[1], ids[2]],
            lastSelectedID: ids[1],
            selectedPhotoID: ids[1]
        )
        let after = s.removing(ids[1])
        #expect(after.selectedIDs == [ids[0], ids[2]])
        #expect(after.lastSelectedID == nil, "被移除的 ID 若 == lastSelectedID → 清空")
        #expect(after.selectedPhotoID == nil, "被移除的 ID 若 == selectedPhotoID → 清空")
    }

    @Test func removingNonLastIDPreservesRelatedFields() {
        // 移除一个不在 lastSelectedID / selectedPhotoID 的 ID——不连带清空
        let ids = fivePhotoIDs()
        let s = SelectionState(
            selectedIDs: [ids[0], ids[1], ids[2]],
            lastSelectedID: ids[2],
            selectedPhotoID: ids[2]
        )
        let after = s.removing(ids[0])
        #expect(after.selectedIDs == [ids[1], ids[2]])
        #expect(after.lastSelectedID == ids[2])
        #expect(after.selectedPhotoID == ids[2])
    }

    @Test func settingAllReplacesSelectedIDs() {
        let stubs = fivePhotoStubs()
        let old = SelectionState(
            selectedIDs: [UUID()],  // 任意旧 ID
            lastSelectedID: UUID(),
            selectedPhotoID: UUID()
        )
        let newAll = old.settingAll(in: stubs)
        #expect(newAll.selectedIDs == Set(stubs.map(\.id)))
        #expect(newAll.lastSelectedID == nil, "全选后 lastSelectedID 重置")
        #expect(newAll.selectedPhotoID == nil, "全选后详情面板隐藏")
    }

    @Test func settingAllWithEmptyInputClears() {
        // 空数组 settingAll = 全清空
        let s = SelectionState(selectedIDs: [UUID()])
        let cleared = s.settingAll(in: [])
        #expect(cleared.selectedIDs.isEmpty)
    }

    // MARK: - 值语义不变性

    @Test func mutationsReturnNewValue() {
        // 所有变更方法必须返回新值，原值不变（值语义）
        let ids = fivePhotoIDs()
        let s = SelectionState(selectedIDs: [ids[0]])
        let _ = s.toggling(ids[1])
        let _ = s.selectingSingle(ids[2])
        let _ = s.removing(ids[0])
        let _ = s.cleared
        let _ = s.settingAll(in: fivePhotoStubs())
        // 原值始终是 [ids[0]]
        #expect(s.selectedIDs == [ids[0]], "所有变更必须不修改原值")
    }
}
