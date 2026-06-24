//
//  DetailView+ImageCard.swift
//  ImageGallery
//
//  V6.97 P3-4: DetailView 拆分 — 大图卡片 + 详情导航按钮
//    之前 1️⃣ 大图 + 导航覆盖层 都在 DetailView.swift (761 行), 拆出
//    包含: bigImageCard, detailNavButton
//    引用: @State bigImage, bigImageLoadFailed, photo, currentIndex, totalCount
//          Copy.photoPosition, Copy.detailPrevHelp, Copy.detailNextHelp
//
//  PBXFileSystemSynchronizedRootGroup 自动同步——无需改 pbxproj
//

import SwiftUI
import SwiftData
import AppKit
import os  // V6.97 P3-4: Logger.imageIO 错误日志

extension DetailView {
    /// 1️⃣ 大图卡
    var bigImageCard: some View {
        Group {
            if let nsImage = bigImage {
                // V4.35.0: 加 GeometryReader 读 bigImageCard section 实际尺寸
                //   V4.34.0 失误: image .frame(maxWidth: .infinity) 单方向 fit
                //   image 撑满父 width (detail panel 可见 width ~500pt)
                //   但 detail panel 实际 visible width < 500pt (被 toolbar / status bar 占)
                //   → image 渲染 width > visible width → 右溢出被切
                // V4.35.0 修复: image 用 GeometryReader 读 bigImageCard section 实际尺寸
                //   .frame(maxWidth: cardGeo.size.width, maxHeight: cardGeo.size.height)
                //   + aspectRatio(.fit) 按 min(width, height) 缩放
                //   bigImageCard section 实际 (detail panel 可见 width, 0.60 × visible height)
                //   1080×1503 竖向图: min(width, height) 按 bigImageCard 实际尺寸算
                //   image 不超 detail panel 右边界 + 不拉伸
                GeometryReader { cardGeo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: cardGeo.size.width, maxHeight: cardGeo.size.height)
                        .id("bigImage")
                }
            } else if bigImageLoadFailed {
                // V6.54 (design polish): 错误态加 caption + '在 Finder 中显示' button
                //   之前只显示 SF Symbol triangle — 用户看不出'加载失败 vs 文件被删 vs 权限不足'
                //   现在: icon + 1 行 caption ('无法读取文件') + 1 个 button (NSWorkspace.open photo.fileURL.dirname)
                //   Photos 真版 detail panel 错误态: icon + reason + recovery action
                VStack(spacing: Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Typography.emptyStateIcon)
                        .foregroundStyle(.tertiary)
                    Text(Copy.detailLoadFailed)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        // NSWorkspace.open fileURL.dirname — Finder 显示该目录, 用户可手动检查文件
                        NSWorkspace.shared.open(photo.fileURL.deletingLastPathComponent())
                    } label: {
                        Label(Copy.detailShowInFinder, systemImage: IconNames.folder)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Palette.cellFilled.opacity(0.3))
                )
            } else {
                // V4.9.5: 加载中——Shimmer 占位（V4.4.0 Shimmer 复用）
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Palette.cellFilled)
                    // V4.25.0: 删 maxHeight 360——Shimmer 占位也按 detail panel 宽度自适应
                    .frame(maxWidth: .infinity)
                    .modifier(Shimmer(duration: 1.2))
            }
        }
        // V4.25.0: 删 maxHeight 360——大图按 aspectRatio 完整显示
        //   V4.4.0 当时限制 360pt 是 "占 50% 高度"——但 360pt 固定值不随窗口高度变
        //   大图竖向 1080×1621 在 detail panel 280pt 宽度下, height = 420pt——超过 360pt 被裁剪
        //   macOS Photos 实际: 大图按 aspectRatio 完整显示 + 整个 detail panel 滚动
        //   删 maxHeight 限制——大图按 fit 缩放到 detail panel 宽度 + 高度由 aspectRatio 决定
        .frame(maxWidth: .infinity)
        // V4.9.5: async 加载——photo.id 变化时自动取消旧任务
        .task(id: photo.id) {
            bigImage = nil
            bigImageLoadFailed = false
            bigImage = await ImageLoader.loadImageAsync(
                at: photo.fileURL,
                maxPixelSize: 2000
            )
            if bigImage == nil {
                bigImageLoadFailed = true
                Logger.imageIO.error("DetailView loadImageAsync failed: \(photo.fileURL.path, privacy: .public)")
            }
        }
        // V4.17.0: photo 切换时 opacity + scale spring 过渡
        //   .id(photo.id) 强制 child 替换触发 transition
        //   视觉：旧图淡出 + 缩小 + 新图淡入 + 放大
        //   旧实现：photo 切换瞬间图替换（无 transition 感觉"跳"）
        .id(photo.id)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(Animations.bouncy, value: photo.id)
        // macOS Quick Look 风格：大图无边框、无卡片背景
        // 导航覆盖层：← / 索引 / →
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                detailNavButton(systemName: "chevron.left", help: Copy.detailPrevHelp) {
                    onPrev()
                }
                .disabled(!canPrev)
                .opacity(canPrev ? 0.9 : 0.3)

                Spacer(minLength: 0)

                if totalCount > 0 {
                    Text(Copy.photoPosition(current: currentIndex, total: totalCount))
                        .font(Typography.captionMono)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        // V4.21.0: 撤回 .glassEffect——macOS 26 单 view 视觉副作用
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer(minLength: 0)

                detailNavButton(systemName: "chevron.right", help: Copy.detailNextHelp) {
                    onNext()
                }
                .disabled(!canNext)
                .opacity(canNext ? 0.9 : 0.3)
            }
            .frame(maxWidth: .infinity)  // 关键: 让 Spacer 撑开,索引居中,左/右按钮贴边
            .padding(Spacing.sm)
        }
    }

    /// 详情导航按钮（← / →）
    func detailNavButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typography.detailLabel)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                // V4.21.0: 撤回 .glassEffect——macOS 26 单 view 视觉副作用
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
