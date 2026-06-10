//
//  MultiSelectMathTests.swift
//  ImageGalleryTests
//
//  V3.6.30：MultiSelectMath 纯函数测试。
//  V3.6.52: 重构——内嵌的 SelectionState 搬到 Models/SelectionState.swift；
//           commandClickDoesNotChangeSelectedPhotoID 改名 commandClickClearsDetailPanel
//           并改断言——⌘+点击后 selectedPhotoID 强制为 nil（X2 行为下沉到 seam）。
//
//  覆盖：
//  - handleTap × 6：plain 单选 / ⌘+新增 / ⌘+删除 / ⌘+清详情 / ⇧+正向 range / ⇧+反向 range / ⇧+lastID=nil 退化
//  - computeRangeSelection × 4：正向 / 反向 / lastID=nil 退化 / 单元素 range
//
//  测试模式：参考 DragReorderMathTests——纯函数，零依赖。
//  V3.6.28 教训：computeHits 接 [Photo] 引发 Swift Testing 并行 @MainActor 测试时
//  SwiftData in-memory 容器共享状态冲突。这里 handleTap 接 [UUID]，零 SwiftData 依赖。
//

import Foundation
import Testing
@testable import ImageGallery

struct MultiSelectMathTests {

    // MARK: - 辅助

    /// V3.6.30: 5 张图 [A, B, C, D, E] 的 ID 数组
    private func fivePhotoIDs() -> [UUID] {
        (0..<5).map { _ in UUID() }
    }

    // MARK: - handleTap: plain click

    @Test func plainClickSingleSelects() {
        // 5 张图，状态空
        let ids = fivePhotoIDs()
        let state = SelectionState()
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[2],  // 点 C
            modifier: .plain,
            photoIDs: ids
        )
        // 期望：.singleSelect，selectedIDs = [C.id]，lastSelectedID = C.id，selectedPhotoID = C.id
        if case .singleSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[2]])
            #expect(s.lastSelectedID == ids[2])
            #expect(s.selectedPhotoID == ids[2])
        } else {
            Issue.record("Expected .singleSelect")
        }
    }

    // MARK: - handleTap: ⌘+click

    @Test func commandClickAddsToMultiSelect() {
        let ids = fivePhotoIDs()
        let state = SelectionState(selectedIDs: [ids[0]])  // 已选 A
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[2],  // ⌘+点 C
            modifier: .command,
            photoIDs: ids
        )
        // 期望：.toggleMultiSelect，selectedIDs = {A, C}，lastSelectedID = C
        if case .toggleMultiSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[0], ids[2]])
            #expect(s.lastSelectedID == ids[2])
        } else {
            Issue.record("Expected .toggleMultiSelect")
        }
    }

    @Test func commandClickRemovesFromMultiSelect() {
        // 关键不变量：⌘+点击已选的图 = 移除
        let ids = fivePhotoIDs()
        let state = SelectionState(
            selectedIDs: [ids[0], ids[2]],  // 已选 {A, C}
            lastSelectedID: ids[0]
        )
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[2],  // ⌘+点 C（已选）
            modifier: .command,
            photoIDs: ids
        )
        if case .toggleMultiSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[0]], "⌘+点击已选应移除")
            #expect(s.lastSelectedID == ids[2])
        } else {
            Issue.record("Expected .toggleMultiSelect")
        }
    }

    @Test func commandClickClearsDetailPanel() {
        // V3.6.52: 重构——⌘+点击后 selectedPhotoID 强制为 nil（X2 行为下沉到 seam）
        //   之前 seam 不变 selectedPhotoID，但消费者 applyTapOutcome 强制设 nil
        //   ——seam 与消费者行为不一致。本次下沉到 seam，单一真相源
        let ids = fivePhotoIDs()
        let state = SelectionState(
            selectedIDs: [ids[0]],
            selectedPhotoID: ids[1]  // 当前详情面板是 B
        )
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[3],  // ⌘+点 D
            modifier: .command,
            photoIDs: ids
        )
        if case .toggleMultiSelect(let s) = outcome {
            #expect(s.selectedPhotoID == nil, "⌘+点击应清空 selectedPhotoID（详情面板隐藏）")
            // selectedIDs 仍正确 toggle（B 不在选中 → 加入）
            #expect(s.selectedIDs == [ids[0], ids[3]], "⌘+点击应把 D 加入多选")
        } else {
            Issue.record("Expected .toggleMultiSelect")
        }
    }

    // MARK: - handleTap: ⇧+click

    @Test func shiftClickRangeSelectForward() {
        // 5 张图，先单选 A，再 ⇧+点 D → 应选 {A, B, C, D}
        let ids = fivePhotoIDs()
        let state = SelectionState(
            selectedIDs: [ids[0]],
            lastSelectedID: ids[0]  // A 是 last
        )
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[3],  // ⇧+点 D
            modifier: .shift,
            photoIDs: ids
        )
        if case .rangeSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[0], ids[1], ids[2], ids[3]], "正向 range 应选 A..D")
            #expect(s.lastSelectedID == ids[3])
            #expect(s.selectedPhotoID == nil, "⇧+点击应清掉 selectedPhotoID")
        } else {
            Issue.record("Expected .rangeSelect")
        }
    }

    @Test func shiftClickRangeSelectBackward() {
        // 5 张图，先单选 D，再 ⇧+点 B → 应选 {B, C, D}
        let ids = fivePhotoIDs()
        let state = SelectionState(
            selectedIDs: [ids[3]],
            lastSelectedID: ids[3]  // D 是 last
        )
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[1],  // ⇧+点 B
            modifier: .shift,
            photoIDs: ids
        )
        if case .rangeSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[1], ids[2], ids[3]], "反向 range 应选 B..D")
            #expect(s.lastSelectedID == ids[1])
        } else {
            Issue.record("Expected .rangeSelect")
        }
    }

    @Test func shiftClickWithNilLastSelectedIDDegenerates() {
        // 退化：lastSelectedID = nil（首次点），⇧+点 B → selectedIDs = [B]
        let ids = fivePhotoIDs()
        let state = SelectionState()  // 全部默认 = 空
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[1],  // ⇧+点 B
            modifier: .shift,
            photoIDs: ids
        )
        if case .rangeSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[1]], "lastID=nil 退化路径")
            #expect(s.lastSelectedID == ids[1])
        } else {
            Issue.record("Expected .rangeSelect")
        }
    }

    // MARK: - handleTap: 互斥（不应出现 ⌘+⇧）

    @Test func plainClickClearsMultiSelect() {
        // plain click 应该清掉多选
        let ids = fivePhotoIDs()
        let state = SelectionState(
            selectedIDs: [ids[0], ids[1], ids[2]],  // 已选 {A, B, C}
            lastSelectedID: ids[2]
        )
        let outcome = MultiSelectMath.handleTap(
            state: state,
            photoID: ids[4],  // plain 点 E
            modifier: .plain,
            photoIDs: ids
        )
        if case .singleSelect(let s) = outcome {
            #expect(s.selectedIDs == [ids[4]], "plain click 应清空多选")
        } else {
            Issue.record("Expected .singleSelect")
        }
    }

    // MARK: - computeRangeSelection（直接测 seam）

    @Test func rangeSelectionForward() {
        let ids = fivePhotoIDs()
        let hits = MultiSelectMath.computeRangeSelection(
            photoIDs: ids,
            lastID: ids[0],
            targetID: ids[3]
        )
        #expect(hits == [ids[0], ids[1], ids[2], ids[3]])
    }

    @Test func rangeSelectionBackward() {
        let ids = fivePhotoIDs()
        let hits = MultiSelectMath.computeRangeSelection(
            photoIDs: ids,
            lastID: ids[3],
            targetID: ids[1]
        )
        #expect(hits == [ids[1], ids[2], ids[3]])
    }

    @Test func rangeSelectionSingleElement() {
        // lastID == targetID → range 退化为单元素
        let ids = fivePhotoIDs()
        let hits = MultiSelectMath.computeRangeSelection(
            photoIDs: ids,
            lastID: ids[2],
            targetID: ids[2]
        )
        #expect(hits == [ids[2]])
    }

    @Test func rangeSelectionDegenerateNilLast() {
        // lastID = nil → 退化，返回 [targetID]
        let ids = fivePhotoIDs()
        let hits = MultiSelectMath.computeRangeSelection(
            photoIDs: ids,
            lastID: nil,
            targetID: ids[1]
        )
        #expect(hits == [ids[1]])
    }
}
