//
//  ContentViewModel.swift
//  ImageGallery
//
//  V5.52 NEW: ContentView 的 @Observable 业务模型
//  把 ContentView 的 21 个 @State + 12 个 @AppStorage + 30+ computed + 41 methods + configureNSToolbar 全部抽到这里
//
//  关键约束 (从 V5.52 探索确定):
//    - @Observable + @MainActor + final class (macOS 14+ 已是项目标准, ImageGalleryUndoManager 沿用)
//    - modelContext init 注入 (不能 @Environment 因为非 View)
//    - @Query 不能进 class——由 view 通过 .onChange 推过来 (3 个 @ObservationIgnored 缓存)
//    - 12 @AppStorage 不能进 class——由 view 推到 Settings 字段
//    - ToolbarController.shared 12 个闭包原本 [self] capture struct value copy——现在 capture [model] (class stable ref)
//
//  阶段 (V5.52-1 骨架; 后续 V5.52-2..7 逐步填充):
//    - V5.52-1: skeleton (本文件) + Settings.swift + view 加 @State model + .task 注入
//    - V5.52-2: Settings 12 var
//    - V5.52-3: 21 个 @State (selection/filterState/...) 搬过来
//    - V5.52-4: 30+ computed 搬过来
//    - V5.52-5: 41 个 private func 搬过来
//    - V5.52-6: configureNSToolbar + 12 closures 搬过来
//    - V5.52-7: @Query 推送 .onChange + pane builders 走 model
//

import Foundation
import SwiftUI
import SwiftData

/// V5.52: ContentView 的业务模型——@MainActor @Observable 单一根
///
/// 持有所有非 view-only 状态 + 业务方法 + ToolbarController 接线。
/// 视图本身只保留 SwiftUI 强制的 @Query / @Environment / ephemeral @State。
@MainActor
@Observable
final class ContentViewModel {
    // V5.52-1 骨架: 后续步骤逐步填充
    //   - Settings 12 var
    //   - 21 business @State
    //   - @Query 缓存 (3 个 @ObservationIgnored var)
    //   - 30+ computed
    //   - 41 private func
    //   - configureToolbar()

    /// V5.52-1 起步: 12 keys UserDefaults 镜像 (改名 UserSettings 避免和 SwiftUI Settings scene 撞名)
    /// 后续 V5.52-2 填 12 个 var
    var settings = UserSettings()

    /// V5.52-1 起步: modelContext 注入
    /// @ObservationIgnored 防止被 Observation 追踪 (避免触发 view 重渲染)
    @ObservationIgnored let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
}
