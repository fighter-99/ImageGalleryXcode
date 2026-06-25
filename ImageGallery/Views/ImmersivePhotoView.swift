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

struct ImmersivePhotoView<DetailContent: View>: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void
    // V6.111.1: 沉浸式详情抽屉 — Photos.app Sonoma+ 模式, 大图右侧滑入的 detail panel
    //   closure 模式 (DetailPane 需要 25 props), ContentView 是 DetailPane 唯一构造点
    //   nil = 旧行为 (无 drawer), 兼容 V6.110 ship 后的现有 call site
    //   closure 内部读 model.grid.immersivePhoto, ←/→ 翻页时 drawer 自动跟新
    let detailContent: (() -> DetailContent)?

    @State private var isChromeVisible = true
    // V4.38.0: 异步大图加载——避免 4000px 大图在主线程解码卡 UI
    //   仿 PhotoGridView cell (V3.6.26) + DetailView bigImage (V4.9.5) 模式
    //   photo.id 变化时自动取消旧 task
    @State private var loadedImage: NSImage?
    @State private var loadFailed = false
    // V6.110.2 (focus + focus ring bug fix): immersive 显式拿焦点
    //   V6.110 第一版加过 @FocusState 但忘了 .focusEffectDisabled → 用户反馈: 拿焦点后 macOS 系统
    //     focus ring (淡蓝色边框) 包围整个 immersive view, 只有缩略图正常显示
    //   V6.110.1 revert @FocusState → gridInputHandling 阻断 → 但 .overlay 内 view 没 first responder
    //     AppKit 不送 key event 给它 → 用户必须先点鼠标, 才能触发 ←/→/Space/Esc
    //   V6.110.2 正确: 阻断 gridInputHandling (V6.110.1) + @FocusState + .focusEffectDisabled
    //     两者缺一不可: 阻断 = 让事件 bubble 出来, @FocusState = AppKit 把 first responder 转过来
    @FocusState private var isImmersiveFocused: Bool
    // V6.111.1: detail drawer 状态 — 默认隐藏保持沉浸感, ⓘ 按钮 toggle
    @State private var isDrawerOpen = false

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
            // V6.67 (Q4): SwiftUI ViewBuilder 不支持 guard let early return — 嵌套 if let 是 idiomatic.
            //   跳过本处, Photos 真版 ImmersivePhotoView 同模式.
            if let photo = currentPhoto {
                if let nsImage = loadedImage {
                    // V6.94.1: 用 MarkupService.compose 把原图 + markupData 合成为 displayImage
                    //   之前 loadedImage 是 raw 原图, markup 标注在 immersive view 不可见 — UX bug
                    //   现在 compose 后 markup 可见, 跟 Photos 真版 immersive view 标注一致
                    //   markupData 为 nil 时 compose 直接返回原图 (no-op)
                    // V6.97.1: 链上 PhotoCropService.compose (P0 #5 Crop / Aspect)
                    //   markup 先 (composited overlay), crop 后 (extract region)
                    //   两个 transformation 正交 — 任意组合 / 单用都安全
                    //   跟 V6.94.1 markup compose chain 完全对称 wiring
                    let displayImage = PhotoCropService.compose(
                        baseImage: MarkupService.compose(baseImage: nsImage, markupData: photo.markupData),
                        cropData: photo.cropRect
                    )
                    Image(nsImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // V6.10: 用 WindowModeMetrics.viewerImagePadding 替 hardcode 40
                        //   DesignTokens.swift:423 已定义同名 token, 本处旁路
                        .padding(WindowModeMetrics.viewerImagePadding)
                        // V6.111.2: 抽屉开时图片 .padding(.trailing) 缩小腾位置
                        //   抽屉宽 320pt + drawer 外距 = 380pt 总共让出
                        //   .animation 跟 value: isDrawerOpen 配套, 平滑过渡
                        .padding(.trailing, isDrawerOpen ? WindowModeMetrics.immersiveDetailDrawerWidth + WindowModeMetrics.immersiveBottomOuterHorizontal : 0)
                        .animation(Animations.standard, value: isDrawerOpen)
                } else if loadFailed {
                    // V6.96 P2 #2: ErrorStateView 范式统一——自绘 fallback 改 EmptyStateView(.destructive)
                    //   之前自绘: icon + 文件名 (视觉跟空状态/加载态区分弱)
                    //   现在 EmptyStateView: 120pt 红色圆形 backdrop + 56pt icon + caption + retry 按钮
                    //   跟全 app 错误态视觉锤一致, Photos 真版 immersive view fallback 范式
                    // V6.97 P2-3: 补 icon 参数 + onTap 标签 + loadCurrentImage → loadCurrentPhoto (跟实际方法名一致)
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: Copy.loadFailedTitle,
                        subtitle: photo.filename,
                        style: .destructive,
                        primaryAction: EmptyStateView.Action(
                            label: Copy.retry,
                            systemImage: IconNames.arrowClockwise,
                            onTap: {
                                // V6.97 P2-3: 真正 reload — loadedImage 置 nil + loadFailed 置 false
                                //   加载逻辑在外层 .task(id: currentPhoto?.id) 里, SwiftUI 会自动重跑
                                loadedImage = nil
                                loadFailed = false
                            }
                        )
                    )
                } else {
                    // V6.31.2: 加载中 → shimmer 骨架 (跟 PhotoThumbnailView 一致)
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

            // V6.111.2: 沉浸式详情抽屉 — Photos.app Sonoma+ 真版
            //   大图右侧滑入 320pt 详情面板, 同时让图片 .padding(.trailing) 缩小腾位置
            //   5th ZStack layer 必须在 chrome 之后 — 不然 chrome pill 会盖在 drawer 上
            //   .zIndex(5) 兜底确保 drawer 永远在最上层
            if isDrawerOpen, let content = detailContent {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content()
                        .frame(width: WindowModeMetrics.immersiveDetailDrawerWidth)
                        .frame(maxHeight: .infinity)
                        .background(VisualEffectMaterial())
                        .clipShape(RoundedRectangle(cornerRadius: Radius.inspector, style: .continuous))
                        // V6.111.2: 0.5pt 白色 8% opacity border — 跟 chrome transl material 一致
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.inspector, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .padding(.trailing, WindowModeMetrics.immersiveBottomOuterHorizontal)
                        .padding(.top, WindowModeMetrics.immersiveTopOuterTop + 60)  // 避开顶部 chrome
                        .padding(.bottom, WindowModeMetrics.immersiveBottomOuterBottom + 60)  // 避开底部 chrome
                        // V6.111.2: drawer 吞 tap — 防止 tap 冒泡到 body 关掉 drawer
                        //   跟 V6.110 focus pattern 同思路: 局部吞事件, 不让 sibling 处理
                        //   drawer 内部 interactive controls (button/tag/text field) 仍响应 — 它们优先于 outer .onTapGesture
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .zIndex(5)
            }
        }
        .contentShape(Rectangle())
        // V6.111.2: body tap 改条件 — 抽屉开时关抽屉, 否则 toggle chrome
        //   之前 V6.110 ship: 无脑 toggle chrome, 抽屉加后行为错乱
        .onTapGesture {
            if isDrawerOpen {
                withAnimation(Animations.standard) {
                    isDrawerOpen = false
                }
            } else {
                withAnimation {
                    isChromeVisible.toggle()
                }
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
        // V6.110.2: 显式绑 @FocusState — 让 AppKit 把 first responder 转到 immersive view
        //   V6.49 SettingsView 已验证 pattern: .focused + .onAppear DispatchQueue.main.async 设 true
        //   延迟 0.05s 关键: window 刚 show 焦点未稳, 同步设焦点失败
        .focused($isImmersiveFocused)
        .onAppear {
            // V6.49 pattern: asyncAfter 0.05s 等 window focus 稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isImmersiveFocused = true
            }
        }
        .onDisappear {
            isImmersiveFocused = false
        }
        // V6.110.2: 禁用 macOS 系统 focus ring (淡蓝色边框) — 跟 PhotoCellContent.swift:489 同 pattern
        //   沉浸式全屏查看是 black background, focus ring 视觉破坏
        //   类似 PhotoCellContent 因为有自定义选中边框所以也禁用 focus ring
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) {
            goPrev()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            goNext()
            return .handled
        }
        // V6.111.3: Esc 分级处理 — 抽屉开 → 关抽屉; 抽屉关 → 退 immersive
        //   跟 Photos.app Sonoma+ 真版一致: 第一次 Esc 关闭浮层, 第二次退全屏
        //   之前 V6.111.2: 无脑退 immersive, 抽屉开时按 Esc 直接退, 用户没法分步退出
        //   现在: 抽屉开 → isDrawerOpen = false (图片仍沉浸); 抽屉关 → onDismiss()
        .onKeyPress(.escape) {
            if isDrawerOpen {
                withAnimation(Animations.standard) {
                    isDrawerOpen = false
                }
                return .handled
            }
            onDismiss()
            return .handled
        }
        // V6.111.3: 抽屉开时强制 chrome 可见 — 不然 drawer 出现但 chrome 隐藏, ⓘ 按钮不可见, 用户没法关
        //   抽屉关时不动 chrome state, 保持用户之前的 chrome 显示/隐藏偏好
        .onChange(of: isDrawerOpen) { _, newValue in
            if newValue {
                isChromeVisible = true
            }
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
            // V6.111.1: ⓘ 按钮 — toggle 详情抽屉 (仅当 detailContent closure 存在时显示)
            //   仿 Photos.app Sonoma+ 真版, 顶部 chrome ⓘ 切换右侧 detail drawer
            //   不破坏 V6.74.5 决定 (toolbar ⓘ 删), 这是沉浸式 chrome 独立 surface
            //   V6.111.2 接 drawer view + 图片 padding 缩小腾位置
            if detailContent != nil {
                Button {
                    withAnimation(Animations.standard) {
                        isDrawerOpen.toggle()
                    }
                } label: {
                    Image(systemName: isDrawerOpen ? "info.circle.fill" : "info.circle")
                        .font(Typography.detailCount)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Show photo details")
                .accessibilityLabel("Show photo details")
            }
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
