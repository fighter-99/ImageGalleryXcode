//
//  ColumnLayoutState.swift
//  ImageGallery
//
//  三列布局（侧栏 / 内容 / 详情）的宽度管理抽象。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  设计：把"宽度状态 + 约束 + 持久化钩子"打包成一个 struct。
//  - 不持有真实状态（ContentView 拥有 @State / @AppStorage）
//  - 不引入 @Observable / class（保持现有模式）
//  - 通过 binding 注入 + 闭包回调，与 ContentView 协作
//

import SwiftUI

struct ColumnLayoutState {
    // ─── 运行时宽度（binding 注入，MainSplitView 通过 .wrappedValue 读写）───
    let sidebarColumnWidth: Binding<CGFloat>
    let detailColumnWidth: Binding<CGFloat>
    let sidebarDragStartWidth: Binding<CGFloat>
    let detailDragStartWidth: Binding<CGFloat>

    // ─── 约束（let 不可变）───
    let sidebarMinWidth: CGFloat
    let sidebarMaxWidth: CGFloat
    let detailMinWidth: CGFloat
    let detailMaxWidth: CGFloat

    // ─── 生命周期回调 ───
    /// drag end 时调用，把当前宽度持久化到 AppStorage
    let onSidebarDragEnd: () -> Void
    let onDetailDragEnd: () -> Void
    /// onAppear 时调用，从 AppStorage 恢复宽度
    let restoreFromStorage: () -> Void
}
