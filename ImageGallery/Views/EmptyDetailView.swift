//
//  EmptyDetailView.swift
//  ImageGallery
//
//  未选中图片时的详情面板占位视图。
//  V3.5.x：从 ContentView.swift 末尾拆出（V3.5.D 补漏）。
//  V3.6.9：改用 EmptyStateView 统一空状态组件。
//

import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        EmptyStateView(
            icon: "photo",
            title: "选择一张图片",
            subtitle: "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选",
            iconColor: Surface.textTertiary
        )
    }
}

#Preview {
    EmptyDetailView()
        .frame(width: 320, height: 480)
}
