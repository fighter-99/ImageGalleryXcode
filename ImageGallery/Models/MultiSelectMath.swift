//
//  MultiSelectMath.swift
//  ImageGallery
//
//  V3.6.30：把 PhotoGridView 的多选点击交互（handleTap + rangeSelect）抽成可测试的纯函数 seam。
//
//  设计要点：
//  - 零 SwiftData 依赖——只接 [UUID] 和 [Photo] 不在 seam 里
//  - 与 V3.6.28 教训对齐：避免在纯函数 seam 里接 [Photo]（会引发 Swift Testing
//    并行 @MainActor 测试时 SwiftData in-memory 共享状态冲突）
//  - 调用方仍负责读 NSEvent.modifierFlags 并转换为 ClickModifier，
//    这样纯函数可以脱离 AppKit 直接测试
//

import Foundation

// MARK: - 状态抽象

/// V3.6.30：多选交互状态的可测试抽象。
///
/// 抽自 ContentView.swift:36-41 的 @State 字段：
/// - selectedPhoto: Photo?  →  selectedPhotoID: UUID?
/// - selectedIDs: Set<UUID>  →  selectedIDs: Set<UUID>
/// - lastSelectedID: UUID?  →  lastSelectedID: UUID?
///
/// 把 Photo 替换为 UUID 是有意为之——避免 seam 依赖 SwiftData @Model。
struct SelectionState: Equatable {
    var selectedIDs: Set<UUID>
    var lastSelectedID: UUID?
    var selectedPhotoID: UUID?

    init(
        selectedIDs: Set<UUID> = [],
        lastSelectedID: UUID? = nil,
        selectedPhotoID: UUID? = nil
    ) {
        self.selectedIDs = selectedIDs
        self.lastSelectedID = lastSelectedID
        self.selectedPhotoID = selectedPhotoID
    }
}

// MARK: - 输入枚举

/// V3.6.30：点击 modifier 的可测试抽象。
///
/// macOS 不会同时产生 ⌘+⇧（互斥），所以 plain / command / shift 三选一。
/// 调用方从 NSEvent.modifierFlags 转：
///   if .command { .command }
///   else if .shift { .shift }
///   else { .plain }
enum ClickModifier: Equatable {
    case plain
    case command
    case shift
}

// MARK: - 输出枚举

/// V3.6.30：点击处理结果的分类。
///
/// 不同 case 走不同的状态更新路径：
/// - singleSelect: 设 selectedPhotoID + 清空 multi-select
/// - toggleMultiSelect: 只更新 selectedIDs，不动 selectedPhotoID
/// - rangeSelect: 更新 selectedIDs（从 lastSelectedID 到 targetID 的范围），selectedPhotoID = nil
enum TapOutcome: Equatable {
    case singleSelect(SelectionState)
    case toggleMultiSelect(SelectionState)
    case rangeSelect(SelectionState)
}

// MARK: - 纯函数

/// V3.6.30：多选交互数学——抽自 PhotoGridView.handleTap (line 317-338)
/// 和 PhotoGridView.rangeSelect (line 340-354)。
///
/// 行为与原 inline 实现完全等价：
/// - plain click: 单选，清空多选，设 selectedPhotoID
/// - ⌘+click: toggle 该 photo 是否在多选中
/// - ⇧+click: 从 lastSelectedID 到当前 photo 的范围选择，selectedPhotoID = nil
///
/// 关键不变量：
/// 1. ⌘+click 不改变 selectedPhotoID（原注释："⌘+点击不改变 selectedPhoto"）
/// 2. ⇧+click 设 selectedPhotoID = nil（原代码：rangeSelect 后 selectedPhoto = nil）
/// 3. ⇧+click 的 lastSelectedID = nil 退化路径：selectedIDs = [targetID]、lastSelectedID = targetID
enum MultiSelectMath {

    /// V3.6.30: 抽自 PhotoGridView.handleTap (line 317-338)
    ///
    /// 调用方需提供 photoIDs: [UUID]——⇧+click 时用 photoIDs.firstIndex(of:) 计算范围。
    /// plain / ⌘+click 时 photoIDs 会被忽略。
    ///
    /// 行为：与原 PhotoGridView.handleTap 完全等价。
    static func handleTap(
        state: SelectionState,
        photoID: UUID,
        modifier: ClickModifier,
        photoIDs: [UUID]
    ) -> TapOutcome {
        var s = state
        switch modifier {
        case .command:
            // ⌘+点击：toggle 多选
            if s.selectedIDs.contains(photoID) {
                s.selectedIDs.remove(photoID)
            } else {
                s.selectedIDs.insert(photoID)
            }
            s.lastSelectedID = photoID
            // ⌘+点击不改变 selectedPhotoID（保持原行为）
            return .toggleMultiSelect(s)

        case .shift:
            // ⇧+点击：范围选择
            s.selectedIDs = computeRangeSelection(
                photoIDs: photoIDs,
                lastID: s.lastSelectedID,
                targetID: photoID
            )
            s.lastSelectedID = photoID
            s.selectedPhotoID = nil  // ⇧+点击不激活详情面板
            return .rangeSelect(s)

        case .plain:
            // 普通单击：单选 + 清空多选
            s.selectedIDs = [photoID]
            s.lastSelectedID = photoID
            s.selectedPhotoID = photoID
            return .singleSelect(s)
        }
    }

    /// V3.6.30: 抽自 PhotoGridView.rangeSelect (line 340-354)
    /// 输入改为 photoIDs: [UUID]（不依赖 [Photo]），便于测试
    /// 行为完全等价：
    /// - lastID 和 targetID 都在 photoIDs：返回 [lower...upper] 的所有 ID
    /// - 退化路径（任一不在 photoIDs）：返回 [targetID]
    /// 注意：调用方应自行把 lastSelectedID = targetID（保持原行为）
    static func computeRangeSelection(
        photoIDs: [UUID],
        lastID: UUID?,
        targetID: UUID
    ) -> Set<UUID> {
        guard let lastID,
              let lastIdx = photoIDs.firstIndex(of: lastID),
              let currentIdx = photoIDs.firstIndex(of: targetID) else {
            return [targetID]
        }
        let lower = min(lastIdx, currentIdx)
        let upper = max(lastIdx, currentIdx)
        return Set(photoIDs[lower...upper])
    }
}
