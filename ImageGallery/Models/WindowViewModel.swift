//
//  WindowViewModel.swift
//  ImageGallery
//
//  V6.28.2 NEW: 从 ContentViewModel 拆出的 Window 业务模型
//    持 Core back-ref (weak) 用于 settings 跨域访问
//    + shared settings (init 注入, 同 instance)
//
//  V6.74.2: 大幅简化 — 删 NSToolbar / TitlebarAccessoryController 整套 dead code
//    - 删 titlebarAccessory 字段 (V4.37.4 TitlebarAccessoryController 实例引用)
//    - 删 configureToolbar(window:) 方法 (140 行, 早在 L71-72 早返, 138 行 NSToolbar 代码永远不跑)
//    - 删 titlebarAccessoryTooltip(isActive:) 方法
//    ToolbarController / TitlebarAccessoryController 整文件删除
//    ⓘ 按钮 (Photos 范式) 改走 SwiftUI .toolbar .primaryAction (V6.74.1)
//    主 toolbar 9 个 SwiftUI ToolbarItem + searchable 接管所有 toolbar 业务
//    WindowAccessor callback 改 no-op, 保留 fallback minSize + setFrameAutosaveName
//
//  拆分依据 (memory V6.28 follow-up):
//    ContentViewModel V6.28.1 后 456 行 → 拆 WindowViewModel (~140 行 → V6.74.2 35 行)
//    Window chrome 单独追踪 — 不污染 Core / Grid / Import 的 observation graph
//
//  关键约束:
//    - @MainActor + @Observable + final class (同 ContentViewModel / GridViewModel / ImportViewModel)
//    - weak var core (避免 retain cycle — ContentViewModel 持 windowVM strong, windowVM 持 core weak)
//    - settings 由 init 注入 (同 instance, Core + Window 共享)
//
//  不在 WindowViewModel (仍 ContentViewModel):
//    - sidebarSelection / filterState / viewMode (Core)
//    - selection / visiblePhotos / batch ops (GridViewModel)
//    - startImport / handleDropImport / importPhotos (ImportViewModel)
//    - toastQueue / undoManager / enqueueToast (Core services)
//
//  阶段:
//    - V6.28.2-1: skeleton + Window 业务抽取 ✓
//    - V6.28.2-2: caller files file-by-file 迁移 model.X → model.windowVM.X ✓
//    - V6.28.2-3: tests 迁移 + 验证 0 regression ✓
//    - V6.74.2: 删 NSToolbar / TitlebarAccessoryController dead code ✓
//

import Foundation
import SwiftUI

/// V6.28.2: Window 业务模型
/// V6.74.2: 大幅简化 — 仅持 core weak + settings, toolbar/titlebar accessory 业务全删
@MainActor
@Observable
final class WindowViewModel {
    /// V6.28.2: Core back-ref (weak 避免 retain cycle)
    ///   用途: settings 跨域访问 (V6.74.2 后 core 主要给 future hook 留接口, 当前 0 caller)
    @ObservationIgnored weak var core: ContentViewModel?

    /// V6.28.2: shared settings (init 注入)
    let settings: UserSettings

    // MARK: - Init

    /// V6.28.2: WindowViewModel init — Core (ContentViewModel) 反向注入 weak ref + settings
    init(settings: UserSettings) {
        self.settings = settings
    }
}