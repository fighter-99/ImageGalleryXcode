//
//  MainLayoutView.swift
//  ImageGallery
//
//  最外层主布局：VStack 纵向堆叠 Split / StatusBar，
//  + undoManager 环境注入
//  + Toast 浮层
//  + 沉浸式全屏看图
//
//  V3.5.17：从 ContentView.swift 拆出。
//  V4.0.0: 去掉 toolbar generic 槽位（toolbar 现在用 ContentView.toolbarContent
//  暴露给外层 .toolbar { ... } modifier）；保留 pathBar 槽位供未来启用
//
//  修饰顺序严格保持原 mainLayout（不能调换）：
//  .environment → .overlay(toast) → .animation(toast)
//  → .overlay(immersive) → .animation(immersive)
//

import SwiftUI

struct MainLayoutView<PathBar: View, Split: View, StatusBarView: View>: View {
    // 3 个子视图（generic 存储）—— toolbar 在 V4.0.0 已迁出到 native .toolbar API
    let pathBar: PathBar
    let split: Split
    let statusBar: StatusBarView

    // 修饰需要的 binding
    @Binding var showSidebar: Bool
    @Binding var immersivePhoto: Photo?
    @Binding var immersiveIndex: Int

    // 修饰需要的值
    let undoManager: ImageGalleryUndoManager
    let toast: ToastInfo?
    let visiblePhotos: [Photo]

    // 修饰需要的 action
    let onImmersiveDismiss: () -> Void

    init(
        @ViewBuilder pathBar: () -> PathBar,
        @ViewBuilder split: () -> Split,
        @ViewBuilder statusBar: () -> StatusBarView,
        showSidebar: Binding<Bool>,
        undoManager: ImageGalleryUndoManager,
        toast: ToastInfo?,
        immersivePhoto: Binding<Photo?>,
        immersiveIndex: Binding<Int>,
        visiblePhotos: [Photo],
        onImmersiveDismiss: @escaping () -> Void
    ) {
        self.pathBar = pathBar()
        self.split = split()
        self.statusBar = statusBar()
        self._showSidebar = showSidebar
        self.undoManager = undoManager
        self.toast = toast
        self._immersivePhoto = immersivePhoto
        self._immersiveIndex = immersiveIndex
        self.visiblePhotos = visiblePhotos
        self.onImmersiveDismiss = onImmersiveDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            split
            statusBar
        }
        // V3.5 Phase 2：把 undoManager 注入环境，让 DetailView 的撤销逻辑（添加/移除标签、重命名）能用
        .environment(\.undoManager, undoManager)
        // Toast 浮层（中央上方）
        .overlay(alignment: .top) {
            if let toast = toast {
                ToastView(message: toast.message, type: toast.type)
                    .padding(.top, 80)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Animations.springGentle, value: toast)
        // 沉浸式全屏看图
        .overlay {
            if immersivePhoto != nil {
                ImmersivePhotoView(
                    photos: visiblePhotos,
                    currentIndex: $immersiveIndex,
                    onDismiss: onImmersiveDismiss
                )
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .animation(Animations.medium, value: immersivePhoto)
    }
}
