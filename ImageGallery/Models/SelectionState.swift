//
//  SelectionState.swift
//  ImageGallery
//
//  V3.6.52：图片选中状态的值类型——图片网格中"哪些图片被选中"的唯一真相源。
//
//  抽离动机（V3.6.52）：
//  - 之前 ContentView 用 3 个分散 @State（selectedPhoto / selectedIDs / lastSelectedID）
//    协同表示选中；任意两个字段的清空/设置必须手工同步，5+ 处易遗漏
//  - SelectionState 之前作为镜像结构藏在 MultiSelectMath.swift 里
//    （V3.6.30 抽 seam 时留下的），但 ContentView 从未真正落地用它
//  - 派生状态（singleSelectedID、isMultiSelect、selectedPhotos(in:)）散在
//    多个 view 里重复算
//
//  设计要点：
//  - 零 SwiftData 依赖——只接 [Photo] 不在结构字段（与 V3.6.28 教训对齐：
//    避免在纯值类型 seam 里存 @Model 引用，触发 Swift Testing 并行 @MainActor
//    测试时 SwiftData in-memory 共享状态冲突）
//  - 所有方法返回新值（值语义），原值不变——纯函数，可单测
//  - 与 MultiSelectMath.handleTap 协同：seam 负责"点击事件 → 状态转换"，
//    本结构负责"派生查询 + 批量操作"，调用方 thin glue
//

import Foundation

// MARK: - 值类型

/// V3.6.52：图片选中状态。ContentView 唯一持有 `@State private var selection`。
///
/// 三个字段语义：
/// - `selectedIDs`：多选集合（⌘+点击累积；⇧+点击范围选择；⌘A / 框选全量替换）
/// - `lastSelectedID`：范围选择的起点（⇧+点击锚点）
/// - `selectedPhotoID`：当前详情面板对应的图片 ID（nil = 不显示详情面板）
///
/// 关键不变量：
/// - `selectedIDs.count == 1` 时 singleSelectedID 优先用 `selectedIDs.first`
/// - `selectedIDs.count > 1` 时 singleSelectedID 强制为 nil（详情面板对多选隐藏）
/// - `selectedPhotoID` 独立于 selectedIDs：可以"已选 3 张 + 单选过 photo A 后又
///   ⌘+点了 B 触发 selectedPhotoID = nil"的中间态
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

// MARK: - 派生查询

extension SelectionState {
    /// 完全无选中（多选空 + 详情面板无）
    var isEmpty: Bool {
        selectedIDs.isEmpty && selectedPhotoID == nil
    }

    /// 任意选中（供 PhotoGridView 判断是否抑制空状态）
    /// 与 isMultiSelect（count > 1）区别：hasSelection 也包含"只选了 1 张"的态
    var hasSelection: Bool {
        !selectedIDs.isEmpty || selectedPhotoID != nil
    }

    /// 多选模式（>1 张）——DetailPane 用此判断显示 multi vs single 详情面板
    var isMultiSelect: Bool {
        selectedIDs.count > 1
    }

    /// 当前单选 ID（最多 1 张时；多选时为 nil）。
    /// 优先级：selectedIDs.first > selectedPhotoID（保持 V3.6.30 原行为）
    var singleSelectedID: UUID? {
        selectedIDs.count <= 1 ? (selectedIDs.first ?? selectedPhotoID) : nil
    }

    /// 给定 ID 是否在选中集合中
    func contains(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }
}

// MARK: - 批量过滤

extension SelectionState {
    /// 在 photos 中查找当前选中的 Photo，保持输入顺序
    /// - Parameter photos: 可见图片列表（已按 sort 排好序）
    /// - Returns: photos ∩ selectedIDs（顺序与 photos 一致）
    /// - Note: 不存在时返回空数组（不抛错）
    func selectedPhotos(in photos: [Photo]) -> [Photo] {
        photos.filter { selectedIDs.contains($0.id) }
    }

    /// V3.6.52 优化：在 photos 中解析单选 photo（不返回 selectedIDs 里的多选）
    /// - Returns: 单选 photo（与 singleSelectedID 对应）；若 selectedIDs > 1 或
    ///   photo 不在 photos 里，返回 nil
    /// - Note: 替代 ContentView 里 `selectedPhoto: Photo?` 的手写 lookup
    ///   O(n) 一次扫描（之前 selectedPhoto + singleSelectedPhoto + currentIndex
    ///   共 2-3 次扫描）
    func singlePhoto(in photos: [Photo]) -> Photo? {
        guard let id = singleSelectedID else { return nil }
        return photos.first(where: { $0.id == id })
    }
}

// MARK: - 状态变更（值语义，返回新 struct）

extension SelectionState {
    /// 空状态常量（用于 `selection = .empty`）
    static let empty = SelectionState()

    /// 清空（返回新值，调用方：`selection = selection.cleared`）
    var cleared: SelectionState { .empty }

    /// 单选：清空多选 + 设 selectedPhotoID + 更新 lastSelectedID
    /// - 用途：plain click、方向键切换、DetailView 上一张/下一张
    func selectingSingle(_ id: UUID) -> SelectionState {
        SelectionState(
            selectedIDs: [id],
            lastSelectedID: id,
            selectedPhotoID: id
        )
    }

    /// toggle 多选（不变 selectedPhotoID——调用方负责）
    /// - 用途：⌘+点击（MultiSelectMath.handleTap seam 已封装；本方法供其他场景）
    /// - 关键：lastSelectedID 始终更新为本次操作的 ID
    func toggling(_ id: UUID) -> SelectionState {
        var s = self
        if s.selectedIDs.contains(id) {
            s.selectedIDs.remove(id)
        } else {
            s.selectedIDs.insert(id)
        }
        s.lastSelectedID = id
        return s
    }

    /// 移除一个 ID（用于 deletePhoto 后从选中集合中剔除）
    /// - 若 id 是 lastSelectedID / selectedPhotoID，对应字段也清空
    func removing(_ id: UUID) -> SelectionState {
        var s = self
        s.selectedIDs.remove(id)
        if s.lastSelectedID == id  { s.lastSelectedID = nil }
        if s.selectedPhotoID == id { s.selectedPhotoID = nil }
        return s
    }

    /// 全选当前可见（⌘A / ⌥+框选）
    /// - 行为：selectedIDs = photos.allIDs, lastSelectedID = nil, selectedPhotoID = nil
    /// - 与 MultiSelectMath 协同：seam 只处理点击，本方法覆盖"批量替换"路径
    func settingAll(in photos: [Photo]) -> SelectionState {
        SelectionState(
            selectedIDs: Set(photos.map(\.id)),
            lastSelectedID: nil,
            selectedPhotoID: nil
        )
    }
}
