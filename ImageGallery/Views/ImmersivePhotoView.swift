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
                        // V6.10: 用 WindowModeMetrics.viewerImagePadding 替 hardcode 40
                        //   DesignTokens.swift:423 已定义同名 token, 本处旁路
                        .padding(WindowModeMetrics.viewerImagePadding)
                } else {
                    // V6.31.2: 加载中 → shimmer 骨架 (跟 PhotoThumbnailView 一致)
                    //   加载失败 → 静态 fallback (exclamationmark.triangle + 文件名)
                    if loadFailed {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(Typography.emptyStateIconLarge)
                                .foregroundStyle(.secondary)
                            Text(photo.filename)
                                .foregroundStyle(.white)
                        }
                    } else {
                        // shimmer 骨架 — 黑色背景上白点流动, 暗示"正在加载"
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .fill(.white.opacity(0.05))
                                .shimmer()
                            Text(photo.filename)
                                .foregroundStyle(.white.opacity(0.5))
                                .font(.caption)
                        }
                        .padding(WindowModeMetrics.viewerImagePadding)
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
            // V6.58 (audit P1.9): photos.isEmpty 时整个 chrome 隐藏
            //   之前 ProgressView guard `count > 0` 防 crash, 但 Index "1 / 0" UX 错乱
            //   现在 chrome 整体隐藏 (用户从侧栏进入空 photo, 直接看到 blank + Esc 退出)
            VStack {
                Spacer()
                if !photos.isEmpty {
                    bottomChrome
                }
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
            // V5.7: 砍收藏 ⭐——沉浸查看只显示文件名
            if let photo = currentPhoto {
                HStack(spacing: 8) {
                    Text(photo.filename)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // V6.12: .callout → Typography.body (13pt) (Q11)
                //   16→13pt 1 调整——chrome 内文字跟 body 层级一致, 不与 detail panel 标题争视觉重量
                .font(Typography.body)
            }
            Spacer()
            // 关闭按钮
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    // V6.12: .title2 → Typography.detailCount (22pt medium) (Q11)
                    //   22pt 跟 close 按钮点击区视觉匹配——比 detail panel 标题略大, 突出"可关闭"
                    .font(Typography.detailCount)
                    .foregroundStyle(.white.opacity(0.9))
                    // V4.57.0: 删 .background(Circle().fill(.black.opacity(0.3)))
                    //   transl material pill 已经有底色——内嵌黑色圆形底是冗余
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        // V6.12: chrome padding 旁路全 token 化 (Q11)
        //   16/10 → Spacing.lg / WindowModeMetrics.immersiveTopVerticalPadding
        .padding(.horizontal, WindowModeMetrics.immersiveTopHorizontalPadding)
        .padding(.vertical, WindowModeMetrics.immersiveTopVerticalPadding)
        // V4.57.0: transl material pill——macOS Photos 风格
        //   仿 V4.45.0 + V4.47.0 popover transl material 范式
        //   之前是 LinearGradient 黑色 60% → 透明 80pt 高渐变带
        //   现在是 NSVisualEffectView .popover 胶囊——chrome 浮动在大图上
        //   注：VisualEffectMaterial 是 NSViewRepresentable（不是 ShapeStyle），
        //   不能用 .background(_, in: Capsule()) 模式——改用 .background() + .clipShape() 标准模式
        .background(VisualEffectMaterial())
        .clipShape(Capsule())
        .padding(.horizontal, WindowModeMetrics.immersiveTopOuterHorizontal)
        .padding(.top, WindowModeMetrics.immersiveTopOuterTop)
    }

    private var bottomChrome: some View {
        HStack(spacing: 40) {
            // 上一张
            Button {
                goPrev()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(Typography.immersiveCount)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(!canPrev)
            .opacity(canPrev ? 1 : 0.3)

            Spacer()

            // 索引
            VStack(spacing: 2) {
                Text(Copy.photoPosition1Indexed(current: currentIndex + 1, total: photos.count))
                    // V6.12: .title3.monospacedDigit() → Typography.immersiveIndexMono (Q11)
                    //   20pt monospaced——"1/5"翻页时数字宽度不抖
                    //   区别于 immersiveCount (44pt) 给翻页箭头图标, 这里给小一号索引数字
                    .font(Typography.immersiveIndexMono)
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
                    .font(Typography.immersiveCount)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(!canNext)
            .opacity(canNext ? 1 : 0.3)
        }
        // V6.12: chrome padding 旁路全 token 化 (Q11) — 32/12 → WindowModeMetrics / Spacing.md
        .padding(.horizontal, WindowModeMetrics.immersiveBottomHorizontalPadding)
        .padding(.vertical, WindowModeMetrics.immersiveBottomVerticalPadding)
        // V4.57.0: transl material pill——macOS Photos 风格
        //   仿 V4.45.0 + V4.47.0 popover transl material 范式
        //   之前是 LinearGradient 透明 → 黑色 60% 120pt 高渐变带
        //   现在是 NSVisualEffectView .popover 胶囊——chrome 浮动在大图上
        //   注：VisualEffectMaterial 是 NSViewRepresentable（不是 ShapeStyle），
        //   不能用 .background(_, in: Capsule()) 模式——改用 .background() + .clipShape() 标准模式
        .background(VisualEffectMaterial())
        .clipShape(Capsule())
        .padding(.horizontal, WindowModeMetrics.immersiveBottomOuterHorizontal)
        .padding(.bottom, WindowModeMetrics.immersiveBottomOuterBottom)
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
