//
//  NotificationModifiers.swift
//  ImageGallery
//
//  V6.100: 从 ContentView+Lifecycle.contentBodyModifiers 抽 12 个 .onReceive + shortcutsHandler
//    - 12 个 NotificationCenter event:
//      .emptyTrashRequested / .quickLookRequested / .navigatePrevRequested / .navigateNextRequested
//      .copyRequested / .actualSizeRequested / .zoomInRequested / .zoomOutRequested
//      .markupRequested / .cropRequested / (V6.97.2 4 个 Shortcuts via shortcutsHandler)
//    - .shortcutsHandler: V6.97.2 抽的 Siri / Spotlight URL scheme 桥接 modifier
//
//  拆出理由: 12 个 .onReceive 难维护, 新加通知要在 250 行内 grep, 极易 miss
//    集中 1 文件后, 加新通知只动 1 处
//  V6.97.2 ShortcutsHandler 已经是同样的 sub-modifier pattern
//

import SwiftUI

extension View {
    /// V6.100: Notification modifiers — 12 个 .onReceive + shortcutsHandler 集中
    ///   从 ContentView+Lifecycle.contentBodyModifiers 抽 (line 191-244, ~54 行)
    ///   加新通知: 改本文件 1 处, 不再 250 行内 grep
    @MainActor
    func notificationModifiers(model: ContentViewModel) -> some View {
        self
            // V6.39.0: Settings "清空回收站" button → NotificationCenter → ContentView
            .onReceive(NotificationCenter.default.publisher(for: .emptyTrashRequested)) { _ in
                model.grid.emptyTrash()
            }
            // V6.74.0: View menu ⌘Y 桥接 — 取代 ToolbarController.shared.onQuickLook nil 死路径
            .onReceive(NotificationCenter.default.publisher(for: .quickLookRequested)) { _ in
                model.grid.showQuickLook()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigatePrevRequested)) { _ in
                model.grid.goPrev()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateNextRequested)) { _ in
                model.grid.goNext()
            }
            // V6.96 P0 #7: Edit > Copy (⌘C)
            .onReceive(NotificationCenter.default.publisher(for: .copyRequested)) { _ in
                model.grid.copyToPasteboard()
            }
            // V6.96 P0 #7: View > Actual Size (⌘0) / Zoom In/Out (⌘+ / ⌘-)
            .onReceive(NotificationCenter.default.publisher(for: .actualSizeRequested)) { _ in
                model.grid.resetThumbnailSize()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomInRequested)) { _ in
                model.grid.zoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOutRequested)) { _ in
                model.grid.zoomOut()
            }
            // V6.94.1: Markup (PencilKit 标注) — Edit menu ⌘M
            .onReceive(NotificationCenter.default.publisher(for: .markupRequested)) { _ in
                model.grid.showingMarkupSheet = true
            }
            // V6.97.1: Crop — Edit menu ⌘⇧K / context menu "裁剪..."
            .onReceive(NotificationCenter.default.publisher(for: .cropRequested)) { _ in
                model.grid.showingCropSheet = true
            }
            // V6.97.2: Shortcuts Siri / Spotlight / 快捷指令 app URL scheme 桥接
            //   4 个 Intent perform() 调 NSWorkspace.openURL → handleShortcutsURL → NotificationCenter
            //   抽到 shortcutsHandler modifier 避免 .onReceive 嵌套太多触发 type-check timeout
            .shortcutsHandler(model: model)
    }
}