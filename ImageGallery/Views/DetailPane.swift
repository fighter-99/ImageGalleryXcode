//
//  DetailPane.swift
//  ImageGallery
//
//  三列布局的右侧列：详情面板。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  三种状态：
//  1. 选中单张图 → DetailView（带元数据、标签、EXIF、上一张/下一张）
//  2. 多选模式 → MultiSelectDetailView（提示批量操作快捷键）
//  3. 无选中 → EmptyDetailView（提示选择图片）
//

import SwiftUI

struct DetailPane: View {
    let singleSelectedPhoto: Photo?
    let isMultiSelect: Bool
    let count: Int
    let totalSize: Int64
    let folders: [Folder]
    let allTags: [Tag]
    // 单图操作
    let onDelete: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let canPrev: Bool
    let canNext: Bool
    let currentIndex: Int
    let totalCount: Int
    // 多选操作（V3.5.19：从 mainLayout 接过来）
    let onBatchMove: (Folder?) -> Void
    let onBatchAddTag: (Tag) -> Void
    let onBatchToggleFavorite: () -> Void
    let onBatchExport: () -> Void
    let onBatchDelete: () -> Void
    let onClearSelection: () -> Void

    var body: some View {
        if let photo = singleSelectedPhoto {
            DetailView(
                photo: photo,
                onDelete: onDelete,
                onPrev: onPrev,
                onNext: onNext,
                canPrev: canPrev,
                canNext: canNext,
                currentIndex: currentIndex,
                totalCount: totalCount
            )
        } else if isMultiSelect {
            MultiSelectDetailView(
                count: count,
                totalSize: totalSize,
                folders: folders,
                allTags: allTags,
                onMove: onBatchMove,
                onAddTag: onBatchAddTag,
                onToggleFavorite: onBatchToggleFavorite,
                onExport: onBatchExport,
                onDelete: onBatchDelete,
                onClearSelection: onClearSelection
            )
        } else {
            EmptyDetailView()
        }
    }
}
