//
//  ContentView+Lifecycle.swift
//  ImageGallery
//
//  V5.51-3: 从 ContentView.swift 抽出 appLifecycleHooks modifier
//  原位置 ContentView.swift:1744-1775
//  V4.10.0 引入——把 .onAppear + 6 个 .onChange 打包成 1 个 modifier 避免 type-check 超时
//

import SwiftUI

// MARK: - V4.10.0: app lifecycle hooks extension
//
// 把 .onAppear + 6 个 .onChange 打包成 1 个语义化 modifier，让 body 链显著缩短。
// 同样的"抽到 extension 避免 type-check 超时"模式参考 applySettingsChrome / syncNSToolbar*。
extension View {
    func appLifecycleHooks(
        thumbnailSize: CGFloat,
        sidebarSelection: SidebarSelection?,
        sortOption: SortOption,
        viewModeRaw: String,
        storedThumbnailSize: Double,
        storedSortOption: String,
        onAppear: @escaping () -> Void,
        onStoredThumbnailChange: @escaping (Double) -> Void,
        onStoredSortChange: @escaping (String) -> Void,
        onThumbnailChange: @escaping (CGFloat) -> Void,
        onSidebarSelectionChange: @escaping (SidebarSelection?) -> Void,
        onSortOptionChange: @escaping (SortOption) -> Void
    ) -> some View {
        self
            .onAppear { onAppear() }
            // V3.6.13: 监听 SettingsView 修改 storedThumbnailSize，实时同步当前 session
            //   避免"重启后生效"的尴尬
            .onChange(of: storedThumbnailSize) { _, new in onStoredThumbnailChange(new) }
            .onChange(of: storedSortOption) { _, new in onStoredSortChange(new) }
            // V3.6.13: viewModeRaw 通过 computed property 自动响应 AppStorage 变化
            .onChange(of: viewModeRaw) { _, _ in }
            .onChange(of: thumbnailSize) { _, new in onThumbnailChange(new) }
            .onChange(of: sidebarSelection) { _, new in onSidebarSelectionChange(new) }
            .onChange(of: sortOption) { _, new in onSortOptionChange(new) }
    }
}
