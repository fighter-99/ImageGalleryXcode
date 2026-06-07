//
//  MainLayoutView.swift
//  ImageGallery
//
//  最外层主布局：VStack 纵向堆叠 Toolbar / PathBar / MainSplit / StatusBar，
//  + 原生 title bar 侧栏按钮
//  + undoManager 环境注入
//  + Toast 浮层
//  + 沉浸式全屏看图
//
//  V3.5.17：从 ContentView.swift 拆出。
//
//  修饰顺序严格保持原 mainLayout（不能调换）：
//  .toolbar → .environment → .overlay(toast) → .animation(toast)
//  → .overlay(immersive) → .animation(immersive)
//

import SwiftUI

struct MainLayoutView<Toolbar: View, PathBar: View, Split: View, StatusBarView: View>: View {
    // 4 个子视图（generic 存储）
    let toolbar: Toolbar
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
        @ViewBuilder toolbar: () -> Toolbar,
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
        self.toolbar = toolbar()
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
            toolbar
            pathBar
            split
            statusBar
        }
        // V3.5.13：恢复 Mac 原生侧栏按钮（title bar 区域）
        // V3.5.16：Photos.app 风格视觉状态 — 侧栏显示时图标变实心 + accent 色
        // V3.5.17：包 withAnimation 让侧栏出现/消失平滑过渡
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .symbolVariant(showSidebar ? .fill : .none)
                        .foregroundStyle(showSidebar ? Color.accentColor : .primary)
                }
                .help(showSidebar ? "隐藏侧栏 (⌘⌃+S)" : "显示侧栏 (⌘⌃+S)")
            }
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
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
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
        .animation(.easeInOut(duration: 0.25), value: immersivePhoto)
    }
}
