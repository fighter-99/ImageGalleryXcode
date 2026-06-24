//
//  KeyboardModifiers.swift
//  ImageGallery
//
//  V6.100: 从 ContentView+Lifecycle.contentBodyModifiers 抽 (line 126-152)
//    gridInputHandling (PhotosView keyboard shortcuts for selection) +
//    contentKeyboardShortcuts (全局 ⌘O/⌘N/⌘C 等)
//
//  拆出理由: 同 LifecycleModifiers — V5.59-2 拆 body modifier 解决 type-check 超时
//  拆出后 ContentView body chain -2 modifier (lifecycleModifiers 已经包一部分)
//

import SwiftUI

extension View {
    /// V6.100: Keyboard modifiers — 14 个 keyboard shortcut handler 集中
    ///   从 ContentView+Lifecycle.contentBodyModifiers 抽 (line 126-152, ~26 行)
    @MainActor
    func keyboardModifiers(
        canPrev: Bool,
        canNext: Bool,
        hasSelection: Bool,
        hasSelectedPhoto: Bool,
        onDelete: @escaping () -> Void,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onEscape: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        onSpace: @escaping () -> Void,
        onResetZoom: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onReturn: @escaping () -> Void,
        onImport: @escaping () -> Void,
        onNewFolder: @escaping () -> Void,
        onResetFilters: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onToggleSortDirection: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void,
        onSetRating: @escaping (Int) -> Void
    ) -> some View {
        self
            .gridInputHandling(
                canPrev: canPrev,
                canNext: canNext,
                hasSelection: hasSelection,
                onDelete: onDelete,
                onPrev: onPrev,
                onNext: onNext,
                onEscape: onEscape,
                onSelectAll: onSelectAll,
                onZoomIn: onZoomIn,
                onZoomOut: onZoomOut,
                hasSelectedPhoto: hasSelectedPhoto,
                onSpace: onSpace,
                onResetZoom: onResetZoom,
                onExport: onExport,
                onReturn: onReturn
            )
            .contentKeyboardShortcuts(
                onImport: onImport,
                onNewFolder: onNewFolder,
                onResetFilters: onResetFilters,
                onCopy: onCopy,
                onToggleSortDirection: onToggleSortDirection,
                onToggleSidebar: onToggleSidebar,
                onSetRating: onSetRating
            )
    }
}