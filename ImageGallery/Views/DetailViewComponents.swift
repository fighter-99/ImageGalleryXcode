//
//  DetailViewComponents.swift
//  ImageGallery
//
//  V6.97 P3-4: DetailView 拆分 — 3 个独立子组件抽到本文件
//    - RatingStarsView (V5.11) — 5 颗 ⭐ hover 预览
//    - TagChip          — Eagle 风格彩色圆角 pill
//    - FlowLayout       — 自定义 Layout protocol 实现 (chips 流式换行)
//
//  之前 3 个组件全在 DetailView.swift 末尾, 跟主 view 混在一起 761 行
//  拆分后 DetailView.swift 只剩主 view + body, 各子 view 独立文件
//  PBXFileSystemSynchronizedRootGroup 自动同步——无需改 pbxproj
//

import SwiftUI

// MARK: - V5.11: RatingStarsView 5 颗 ⭐ hover 预览组件
//
// 5 颗 22pt medium weight ⭐ 横向排列
// hover 预览: @State 追踪鼠标位置——hover 到的星也显示填充（预览）— macOS Photos 同款
// 点击: 切换 rating——同星再点归 0（清除）
// 性能: @State 局部，hoverRating 变化只触发本 view 重绘
struct RatingStarsView: View {
    let rating: Int
    let onSet: (Int) -> Void

    @State private var hoverRating: Int = 0
    // V6.32.2: 暗色模式感知 — unfilled star opacity
    @Environment(\.colorScheme) private var colorScheme

    /// V6.32.2: 暗色下 unfilled star 用 0.65 (跟 filled yellow 形成对比)
    /// 浅色 0.5 (跟 Color.secondary 拉开)
    /// V6.54: 改走 Surface.ratingUnfilled(for: colorScheme) token — 收口, 跟 ratingFilled 对仗
    private var unfilledStarColor: Color {
        Surface.ratingUnfilled(for: colorScheme)
    }

    /// 显示的填充范围——max(rating, hoverRating)
    /// hover 时 hoverRating > rating，星星被"推"过去，预览效果
    /// V5.13：抽到 RatingStarsMath.displayedRating 便于纯函数测试
    private var displayedRating: Int {
        RatingStarsMath.displayedRating(current: rating, hover: hoverRating)
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    // 同星再点归 0（清除）——V5.8 行为不变
                    // V5.13：抽到 RatingStarsMath.nextRating 便于纯函数测试
                    onSet(RatingStarsMath.nextRating(after: n, current: rating))
                } label: {
                    Image(systemName: n <= displayedRating ? "star.fill" : "star")
                        .font(Typography.detailCount)
                        .foregroundStyle(n <= displayedRating ? Surface.ratingFilled : unfilledStarColor)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    // 鼠标进入该星 → hoverRating = n（覆盖至 N）
                    // 鼠标离开该星 → hoverRating = 0（恢复 actual rating）
                    hoverRating = isHovered ? n : 0
                }
                .help(n <= rating ? Copy.ratingCurrent(n) : Copy.ratingSetTo(n))
            }
        }
    }
}

// MARK: - TagChip (Eagle 风格彩色圆角 pill)

struct TagChip: View {
    let tag: Tag
    let onRemove: () -> Void
    @State private var isHovered = false

    private var tagColor: Color { Color(hex: tag.colorHex) }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tagColor)
                .frame(width: 10, height: 10)
            Text(tag.name)
                .font(Typography.caption)
                .foregroundStyle(tagColor.opacity(0.85))
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(isHovered ? tagColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tagColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(tagColor.opacity(0.20), lineWidth: 0.5))
        .onHover { hovering in
            withAnimation(Animations.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - FlowLayout (Layout protocol 实现)

/// 流式布局: chips 按顺序横排, 满宽自动换行
/// 比 LazyVGrid 轻量, 无 cell 间距
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth {
                totalHeight += currentRowHeight + spacing
                currentRowWidth = size.width + spacing
                currentRowHeight = size.height
            } else {
                currentRowWidth += size.width + spacing
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        totalHeight += currentRowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentRowHeight + spacing
                currentRowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}
