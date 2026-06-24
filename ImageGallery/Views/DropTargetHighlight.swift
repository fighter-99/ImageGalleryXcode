//
//  DropTargetHighlight.swift
//  ImageGallery
//
//  V6.96 P1 #3: 拖放目标高亮 ViewModifier
//   - 收口三处实现: folder (2pt accent 描边 + 阴影) / trash (warningOrange 0.28 填充) / window (accent 虚线框)
//   - 之前 3 套独立写法散落 SidebarView / ContentView, 改 padding 或颜色要 grep 三处
//   - 现在一处定义, 颜色/圆角/动画曲线全走 token, 新增 drop target 只能选 style 不能造风格
//
//  V6.96 (Toast/ToastView): 改 Animations.standard (跟 P1 #1 token 收敛一致, 之前 folder 是 medium / trash 是 interactive)
//
import SwiftUI

/// 拖放目标高亮 modifier
/// - folder: 2pt accent 描边 + Elevation.standard 阴影 (适合 sidebar folder, 强调"这格会接住")
/// - trash:  warningOrange 0.28 alpha 填充 (适合 sidebar trash, 警示性而非强调性)
/// - window: 3pt accent 虚线描边 8pt inset (适合主窗格整窗高亮, 跟 MainSplitView dropOverlay 互斥)
struct DropTargetHighlight: ViewModifier {
    enum Style {
        case folder
        case trash
        case window
    }

    let isActive: Bool
    let style: Style

    func body(content: Content) -> some View {
        content
            .background(backgroundShape)
            .overlay(borderShape)
            .animation(Animations.standard, value: isActive)
    }

    // MARK: - 背景填充 (trash)

    @ViewBuilder
    private var backgroundShape: some View {
        if isActive, style == .trash {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Surface.warningOrange.opacity(0.28))
                .padding(-4)
        }
    }

    // MARK: - 描边 + 阴影 (folder / window)

    @ViewBuilder
    private var borderShape: some View {
        switch (isActive, style) {
        case (true, .folder):
            // V6.96 P1 #3: folder style 是 fill + stroke + shadow 三层
            //   fill 0.28 让 row 内部"亮起" (照片 app 拖到 folder 的视觉锤)
            //   stroke 2pt 给清晰边界
            //   shadow 0.4 让"抬起" (跟 hover 视觉一致)
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.accentColor.opacity(0.28))
                    .padding(-4)
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(-4)
                    .shadow(
                        color: Color.accentColor.opacity(0.4),
                        radius: Elevation.standard.radius,
                        y: Elevation.standard.y
                    )
            }

        case (true, .window):
            // 3pt 虚线 + 8pt inset — 跟 MainSplitView 全窗 drop overlay 视觉不同
            //   MainSplitView 是 transl material + icon (massive overlay), 这里给"主窗格内"小范围高亮
            //   但实际主窗格现在用 MainSplitView 的 dropOverlay, window style 暂保留备用
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, dash: [10, 6])
                )
                .padding(8)

        default:
            EmptyView()
        }
    }
}

extension View {
    /// 拖放目标高亮快捷修饰
    /// - Parameter style: 三种风格 (folder/trash/window)
    /// - Parameter isActive: 鼠标是否悬停在目标上, 来自 .dropDestination isTargeted 闭包
    func dropTargetHighlight(_ style: DropTargetHighlight.Style, isActive: Bool) -> some View {
        modifier(DropTargetHighlight(isActive: isActive, style: style))
    }
}
