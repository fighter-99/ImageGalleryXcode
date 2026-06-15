//
//  ContentView+WindowChrome.swift
//  ImageGallery
//
//  V5.51-7: 从 ContentView.swift 抽出 windowChromeAndToolbar modifier
//  原位置 ContentView.swift:1676-1729
//  V4.10.0 引入——打包 6 个 chrome modifier（title/subtitle/colorScheme/WindowAccessor + 3 syncNSToolbar）
//

import SwiftUI

// MARK: - V4.10.0: window chrome + NSToolbar 桥接 extension
//
// 把 .navigationTitle + .navigationSubtitle + .preferredColorScheme +
// .background(WindowAccessor) + .syncNSToolbarSelectionState + .syncNSToolbarSearchField
// 6 个 chrome modifier 打包成 1 个语义化 modifier。
extension View {
    func windowChromeAndToolbar(
        title: String,
        subtitle: String,
        colorScheme: ColorScheme?,
        selection: SelectionState,
        searchText: String,
        // V5.24: 加 layoutMode + thumbnailSize 参数——windowChromeAndToolbar 自身不持有
        //   状态，需 caller 传入以同步到 NSToolbar segment/slider
        // V5.39.3: 加 sortOption 参数——推 NSToolbar sortMenu 按钮 (image 跟 sortOption 走)
        layoutMode: ThumbnailLayoutMode,
        thumbnailSize: CGFloat,
        sortOption: SortOption,
        configureWindow: @escaping (NSWindow) -> Void
    ) -> some View {
        self
            // V4.8.0: 删 .toolbar { toolbarContent }——SwiftUI .toolbar 在 macOS 是降级实现
            //   改用 NSToolbar (AppKit) 在 WindowAccessor 处设置
            //   Photos.app / Finder / Mail 都用 NSToolbar——本路线一致
            //
            // V4.2.0 P0❸: 窗口元数据（hidden title bar 模式下不显示在窗口顶部，
            //   但进入 Dock 右键 / ⌘⇥ 切换器 / Mission Control / VoiceOver 等位置）
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            // V3.6.22: 应用外观（浅色/深色/跟随系统）
            .preferredColorScheme(colorScheme)
            // V4.8.0: NSToolbar 桥接——WindowAccessor 拿到 NSWindow 后设置 NSToolbar
            //   .background(WindowAccessor) 嵌入零尺寸 NSView
            .background(WindowAccessor { window in
                configureWindow(window)
            })
            // V4.8.0: 选中状态变化 → 更新 NSToolbar buttons enabled
            .syncNSToolbarSelectionState(
                selection: selection,
                layoutMode: layoutMode,
                density: thumbnailSize
            )
            // V4.8.1: SwiftUI @State searchText 变化 → 同步到 NSSearchField
            .syncNSToolbarSearchField(text: searchText)
            // V5.39.3: 3 个 NSMenu 按钮状态同步——layoutMode + density + sortOption
            //   替代 V5.24 syncNSToolbarDensity + V5.33 砍掉的 syncNSToolbarLayoutMode
            //   1 个 modifier 推 3 个 onChange, 简化 body 链
            .syncNSToolbarAllStates(
                layoutMode: layoutMode,
                density: thumbnailSize,
                sortOption: sortOption
            )
    }
}
