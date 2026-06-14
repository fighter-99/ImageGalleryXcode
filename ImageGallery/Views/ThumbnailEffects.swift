//
//  ThumbnailEffects.swift
//  ImageGallery
//
//  V4.4.0 NEW: 缩略图视觉效果组件集
//    - CheckerboardBackground: 透明 PNG 的棋盘背景（Mac Preview / Pixelmator 同款）
//    - Shimmer: 加载中骨架动效（Reduced Motion 自动禁用）
//
//  抽到独立文件原因：
//    - PhotoGridView 已 1300+ 行，加新功能继续膨胀不利于阅读
//    - 这两个效果未来可能被 DetailView/ImmersivePhotoView 复用
//

import SwiftUI

// MARK: - 透明 PNG checker 棋盘背景
//
// 用 SwiftUI Canvas 画 8×8pt 的浅灰/深灰交替棋盘——
// 浅色模式下用 #F0F0F0/#FAFAFA，深色模式下用 #1E1E1E/#262626
// 自动适配 colorScheme。
//
// 用法：
//   ZStack {
//       CheckerboardBackground()   // ← 最底层
//       Image(nsImage: pngImage)   // ← 透明 PNG 显示在棋盘上
//   }
struct CheckerboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// 棋盘格大小（pt）；8pt 是 macOS Preview/Pixelmator 标准
    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let colorA = lightSquareColor
            let colorB = darkSquareColor
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col).isMultiple(of: 2)
                    let color = isLight ? colorA : colorB
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }

    private var lightSquareColor: Color {
        colorScheme == .dark
            ? Color(white: 0.15)   // 深色模式：偏暗灰
            : Color(white: 0.98)   // 浅色模式：近白
    }

    private var darkSquareColor: Color {
        colorScheme == .dark
            ? Color(white: 0.10)   // 深色模式：更暗灰
            : Color(white: 0.92)   // 浅色模式：浅灰
    }
}

// MARK: - Shimmer 骨架动效
//
// 加载中的缩略图占位——给空白 RoundedRectangle 加一道斜向流动的高光，
// 暗示"正在加载"。比静态 photo icon 信息量大、不刺眼。
//
// 自动适配：
//   - 深浅模式：浅色用半透明白，深色用半透明白（叠加在深灰底上）
//   - Reduced Motion：自动禁用（仅显示底色，不动）
//
// 用法：
//   RoundedRectangle(cornerRadius: 6)
//       .fill(.quaternary)
//       .modifier(Shimmer())
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    /// 单次扫光周期（秒）；1.5s 是常见值
    var duration: Double = 1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    if !reduceMotion {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0),    location: 0.30),
                                .init(color: .white.opacity(0.25), location: 0.50),
                                .init(color: .white.opacity(0),    location: 0.70),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: geo.size.width * 1.5)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                    }
                }
            )
            .mask(content)  // 让 shimmer 只在 content 形状内可见（适配圆角）
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 0.6
                }
            }
    }
}

extension View {
    /// 给 view 加 shimmer 骨架动效（加载占位用）
    func shimmer(duration: Double = 1.5) -> some View {
        modifier(Shimmer(duration: duration))
    }
}

// MARK: - Preview

#Preview("Checker + Shimmer") {
    HStack(spacing: 20) {
        // Checker (with sample transparent PNG)
        VStack {
            Text("Checker").font(.caption)
            ZStack {
                CheckerboardBackground()
                Image(systemName: "photo.fill")
                    .font(Typography.emptyStateIcon)
                    .foregroundStyle(.tint.opacity(0.5))
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }

        // Shimmer
        VStack {
            Text("Shimmer").font(.caption)
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 150, height: 150)
                .shimmer()
        }
    }
    .padding()
}
