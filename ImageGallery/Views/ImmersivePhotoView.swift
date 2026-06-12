//
//  ImmersivePhotoView.swift
//  ImageGallery
//
//  沉浸式全屏看图。
//  - 黑色背景，大图居中
//  - 翻页（左/右方向键、按钮）
//  - 顶部关闭按钮（Esc 退出）
//  - 缩放：双击放大（V2.6+）
//
//  V4.57.0: 顶/底 chrome 升级 transl material pill
//    之前：LinearGradient 黑色 60% → 透明 渐变带
//    现在：Capsule + VisualEffectMaterial(.popover)——macOS Photos 实际风格
//    仿 V4.45.0 + V4.47.0 popover transl material 范式
//    （material = .popover, state = .followsWindowActiveState, blendingMode = .withinWindow）
//

import SwiftUI

struct ImmersivePhotoView: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void

    @State private var isChromeVisible = true
    // V4.38.0: 异步大图加载——避免 4000px 大图在主线程解码卡 UI
    //   仿 PhotoGridView cell (V3.6.26) + DetailView bigImage (V4.9.5) 模式
    //   photo.id 变化时自动取消旧 task
    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    /// 当前显示的图片
    private var currentPhoto: Photo? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            // 1. 黑色背景
            Color.black
                .ignoresSafeArea()

            // 2. 大图（居中）
            // V4.38.0: async 加载——loadedImage 优先；加载中/失败时显示 fallback
            if let photo = currentPhoto {
                if let nsImage = loadedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
                    // 加载中 + 加载失败都用同一 fallback（避免加 Shimmer 复杂度）
                    VStack(spacing: 16) {
                        Image(systemName: "photo")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                        Text(photo.filename)
                            .foregroundStyle(.white)
                    }
                }
            }

            // 3. 顶部 chrome（关闭按钮）
            VStack {
                topChrome
                Spacer()
            }
            .opacity(isChromeVisible ? 1 : 0)
            .animation(Animations.standard, value: isChromeVisible)

            // 4. 底部 chrome（翻页 + 索引）
            VStack {
                Spacer()
                bottomChrome
            }
            .opacity(isChromeVisible ? 1 : 0)
            .animation(Animations.standard, value: isChromeVisible)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击图片区域切换 chrome
            withAnimation {
                isChromeVisible.toggle()
            }
        }
        // V4.38.0: 异步大图加载——currentPhoto 变化时自动取消旧 task
        //   maxPixelSize 4000（全屏大图）——后台线程解码不阻塞 UI
        .task(id: currentPhoto?.id) {
            guard let photo = currentPhoto else {
                loadedImage = nil
                return
            }
            loadFailed = false
            let img = await ImageLoader.loadImageAsync(
                at: photo.fileURL,
                maxPixelSize: 4000
            )
            if img == nil {
                loadFailed = true
            } else {
                loadedImage = img
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            goPrev()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            goNext()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.space) {
            goNext()
            return .handled
        }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack {
            // 文件名 + 索引
            if let photo = currentPhoto {
                HStack(spacing: 8) {
                    Text(photo.filename)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if photo.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.callout)
            }
            Spacer()
            // 关闭按钮
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                    // V4.57.0: 删 .background(Circle().fill(.black.opacity(0.3)))
                    //   transl material pill 已经有底色——内嵌黑色圆形底是冗余
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // V4.57.0: transl material pill——macOS Photos 风格
        //   仿 V4.45.0 + V4.47.0 popover transl material 范式
        //   之前是 LinearGradient 黑色 60% → 透明 80pt 高渐变带
        //   现在是 NSVisualEffectView .popover 胶囊——chrome 浮动在大图上
        //   注：VisualEffectMaterial 是 NSViewRepresentable（不是 ShapeStyle），
        //   不能用 .background(_, in: Capsule()) 模式——改用 .background() + .clipShape() 标准模式
        .background(VisualEffectMaterial())
        .clipShape(Capsule())
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var bottomChrome: some View {
        HStack(spacing: 40) {
            // 上一张
            Button {
                goPrev()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(!canPrev)
            .opacity(canPrev ? 1 : 0.3)

            Spacer()

            // 索引
            VStack(spacing: 2) {
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.white)
                if photos.count > 0 && photos.count <= 100 {
                    ProgressView(value: Double(currentIndex + 1), total: Double(photos.count))
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 120)
                }
            }

            Spacer()

            // 下一张
            Button {
                goNext()
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(!canNext)
            .opacity(canNext ? 1 : 0.3)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        // V4.57.0: transl material pill——macOS Photos 风格
        //   仿 V4.45.0 + V4.47.0 popover transl material 范式
        //   之前是 LinearGradient 透明 → 黑色 60% 120pt 高渐变带
        //   现在是 NSVisualEffectView .popover 胶囊——chrome 浮动在大图上
        //   注：VisualEffectMaterial 是 NSViewRepresentable（不是 ShapeStyle），
        //   不能用 .background(_, in: Capsule()) 模式——改用 .background() + .clipShape() 标准模式
        .background(VisualEffectMaterial())
        .clipShape(Capsule())
        .padding(.horizontal, 60)
        .padding(.bottom, 24)
    }

    // MARK: - 翻页

    private var canPrev: Bool { currentIndex > 0 }
    private var canNext: Bool { currentIndex < photos.count - 1 }

    private func goPrev() {
        guard canPrev else { return }
        withAnimation(Animations.quick) {
            currentIndex -= 1
        }
    }

    private func goNext() {
        guard canNext else { return }
        withAnimation(Animations.quick) {
            currentIndex += 1
        }
    }
}
