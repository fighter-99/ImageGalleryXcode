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

import SwiftUI

struct ImmersivePhotoView: View {
    let photos: [Photo]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void

    @State private var isChromeVisible = true

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
            if let photo = currentPhoto {
                if let nsImage = ImageLoader.loadImage(at: photo.fileURL, maxPixelSize: 4000) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
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
            .animation(.easeInOut(duration: 0.2), value: isChromeVisible)

            // 4. 底部 chrome（翻页 + 索引）
            VStack {
                Spacer()
                bottomChrome
            }
            .opacity(isChromeVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isChromeVisible)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击图片区域切换 chrome
            withAnimation {
                isChromeVisible.toggle()
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
                    .background(Circle().fill(.black.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
            .allowsHitTesting(false)
        )
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
        .padding(.horizontal, 60)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
        )
    }

    // MARK: - 翻页

    private var canPrev: Bool { currentIndex > 0 }
    private var canNext: Bool { currentIndex < photos.count - 1 }

    private func goPrev() {
        guard canPrev else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            currentIndex -= 1
        }
    }

    private func goNext() {
        guard canNext else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            currentIndex += 1
        }
    }
}
