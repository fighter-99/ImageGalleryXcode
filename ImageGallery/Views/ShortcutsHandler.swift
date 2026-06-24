//
//  ShortcutsHandler.swift
//  ImageGallery
//
//  V6.97.2: Shortcuts Siri / Spotlight / 快捷指令 app URL scheme 桥接
//   Intent perform() 调 NSWorkspace.openURL("imagegallery://...")
//   主 app onOpenURL → ImageGalleryApp.handleShortcutsURL → NotificationCenter → 这里 .onReceive
//   4 个 action 走现有 GridViewModel operations (走 @MainActor, 自动 undo + toast)
//
//  抽到独立 ViewModifier 原因:
//   ContentView body 已经有 13 个 .onReceive 嵌套, 加 4 个触发 SwiftUI type-check timeout
//   跟 V3.6.37 抽 cell contextMenu modifier 教训一致 — 大 chain 拆 modifier
//

import SwiftUI

private struct ShortcutsHandler: ViewModifier {
    @Bindable var model: ContentViewModel

    func body(content: Content) -> some View {
        content
            // 打开最后一张 photo (immersive view) — 复用 GridViewModel.enterImmersive(_:)
            .onReceive(NotificationCenter.default.publisher(for: .shortcutsShowLastPhotoRequested)) { _ in
                // 按 importedAt desc 排序, 拿非 trash 第一张, 直接 enterImmersive
                //   跳过 selection (跟 enterImmersiveFromSelection 路径不同, 少 1 个 selection state 副作用)
                if let lastPhoto = model.grid.allPhotos
                    .filter({ !$0.isInTrash })
                    .sorted(by: { $0.importedAt > $1.importedAt })
                    .first {
                    model.grid.enterImmersive(lastPhoto)
                }
            }
            // 搜索 photos (userInfo["query"]) — 复用 grid.searchText (触发 visiblePhotos 重算)
            .onReceive(NotificationCenter.default.publisher(for: .shortcutsSearchRequested)) { note in
                let query = note.userInfo?["query"] as? String ?? ""
                model.grid.searchText = query
                // 清空当前 selection, 跳到第一张匹配
                model.grid.selection = .empty
            }
            // 裁剪当前单选 photo (userInfo["aspect"]) — 复用 cropSelected (V6.97.1.1 修后)
            .onReceive(NotificationCenter.default.publisher(for: .shortcutsCropRequested)) { note in
                // CropAspect rawValue 是 String, 直接 init CropAspect(rawValue: aspect)
                //   没有 selection → toast 提示先选 1 张 (跟 cropSelected 内部 guard 一致)
                guard let aspectRaw = note.userInfo?["aspect"] as? String,
                      let aspect = CropAspect(rawValue: aspectRaw),
                      model.grid.resolvedSingle != nil else {
                    model.showToast(Copy.toastSelectCropFirst, type: .info)
                    return
                }
                // 用 fullImage rect + 指定 aspect, 跟 cropSelected 走同样 undo + toast + coalesceId="crop" pattern
                model.grid.cropSelected(rect: CGRect(x: 0, y: 0, width: 1, height: 1), aspect: aspect)
            }
            // Toggle 收藏当前单选 photo (rating 5 ↔ 0, 跟 Photos 范式) — 复用 batchSetRating
            .onReceive(NotificationCenter.default.publisher(for: .shortcutsFavoriteRequested)) { _ in
                guard let photo = model.grid.resolvedSingle?.photo else {
                    model.showToast(Copy.toastSelectCropFirst, type: .info)
                    return
                }
                // toggle 逻辑: isFavoriteComputed ? 0 : 5 (跟 Photos Siri "Favorite" 行为对齐)
                let newRating = photo.isFavoriteComputed ? 0 : 5
                model.grid.batchSetRating(newRating)
            }
    }
}

// V6.97.2: View extension — 让 ContentView body 一行挂载 (跟 V6.94.1 markupSheet 同 pattern)
extension View {
    func shortcutsHandler(model: ContentViewModel) -> some View {
        modifier(ShortcutsHandler(model: model))
    }
}