//
//  SheetModifiers.swift
//  ImageGallery
//
//  V6.100: 从 ContentView+Lifecycle 抽 sheet 一族 (5 个 sub-modifier)
//    - batchRenameSheet: P4.2 batch rename (template + preview)
//    - shareSheet: V6.19.0 NSSharingServicePicker
//    - markupSheet: V6.94.1 NSBezierPath 自绘 markup
//    - cropSheet: V6.97.1 NSView 9 handles crop
//    - smartFolderAndShareSheets: V6.97 P2-3 打包 5 modifier 解决 type-check 超时
//
//  拆出理由: 5 个 sheet 都是 model @Bindable owner, 集中放 sheet 文件
//  之前混在 ContentView+Lifecycle 跟其他 modifier 同文件, 难以定位
//

import SwiftUI

extension View {
    /// V6.100: Sheet modifiers — 5 sheet 集中 (batchRename / share / markup / crop / smartFolder)
    ///   从 ContentView+Lifecycle.contentBodyModifiers + 独立 extension 抽 (line 176-188 + 305-579)
    @MainActor
    func sheetModifiers(
        model: ContentViewModel,
        bindableGrid: Bindable<GridViewModel>,
        selection: SelectionState,
        visiblePhotos: [Photo],
        showingBatchRename: Binding<Bool>
    ) -> some View {
        self
            .batchRenameSheet(
                model: model,
                selection: selection,
                visiblePhotos: visiblePhotos,
                showingBatchRename: showingBatchRename
            )
            .smartFolderAndShareSheets(
                model: model,
                bindableGrid: bindableGrid
            )
            // V6.94.1: Markup sheet — P0 #3 Markup feature
            .markupSheet(model: model, showingSheet: model.grid.showingMarkupSheet)
            // V6.97.1: Crop sheet — P0 #5 Crop / Aspect feature
            .cropSheet(model: model, showingSheet: model.grid.showingCropSheet)
    }
}