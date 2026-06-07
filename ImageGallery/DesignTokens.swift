//
//  DesignTokens.swift
//  ImageGallery
//
//  设计 Token：集中管理颜色、间距、圆角、动画、阴影、字体。
//  整个 App 的视觉风格统一从这里引用。
//
//  V3.1 升级：Photos.app 极简风格（Direction A）。
//  - 新增 Surface（语义化表面色，自适应暗色）
//  - 新增 Elevation（微妙阴影系统）
//  - 新增 Typography（语义化字体层级）
//  - Palette 保留为兼容层，内部重定向到 Surface
//

import SwiftUI
import AppKit

// MARK: - 间距系统（4 的倍数）

enum Spacing {
    static let xs: CGFloat = 4      // 紧凑：chip 内边距
    static let sm: CGFloat = 8      // 小：元素间
    static let md: CGFloat = 12     // 中：组件内（默认）
    static let lg: CGFloat = 16     // 大：组件间
    static let xl: CGFloat = 20     // 特大：区域间
    static let xxl: CGFloat = 24    // 超大：主区域分隔
}

// MARK: - 圆角系统

enum Radius {
    static let sm: CGFloat = 6      // 小：输入框、按钮
    static let md: CGFloat = 8      // 中：缩略图、卡片
    static let lg: CGFloat = 12     // 大：大卡片、tag chip
}

// MARK: - 表面色（V3.1 NEW：Photos.app 风格语义化）
//
// 设计原则：
// - 用 NSColor 系统色，自动适配浅色/暗色
// - 用 primary.opacity 而非 gray.opacity，让文字/分隔线在两种模式下都自然
// - 透明度数字小（0.04-0.16），让 UI 安静地"退后"

enum Surface {
    // ─── 画布层级（从底到顶） ───
    static let canvas = Color(NSColor.windowBackgroundColor)
    static let panel = Color(NSColor.controlBackgroundColor)
    static let elevated = Color(NSColor.controlBackgroundColor)

    // ─── 交互态 ───
    /// hover 时的微妙高亮（两种模式下都自然）
    static let hover = Color.primary.opacity(0.04)
    /// 选中态的浅 accent 背景
    static let selected = Color.accentColor.opacity(0.10)
    /// 多选/强选中态
    static let selectedStrong = Color.accentColor.opacity(0.16)

    // ─── 分隔线 ───
    static let separator = Color.primary.opacity(0.08)
    static let separatorStrong = Color.primary.opacity(0.15)

    // ─── 文本层级 ───
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.7)

    // ─── 状态色 ───
    static let favorite = Color.yellow
    static let destructive = Color.red
    static let success = Color.green

    // ─── 卡片 ───
    static let cardBackground = Color(NSColor.controlBackgroundColor)
    static let cardBorder = Color.primary.opacity(0.06)

    // ─── 工具栏专用（V3.1 Phase 1.5） ───
    /// 工具栏内分组背景（segments、菜单、搜索）
    /// 比 .hover 略深（0.04 → 0.06），让分组在工具栏上更可见
    static let toolbarControl = Color.primary.opacity(0.06)
}

// MARK: - 阴影（V3.1 NEW：微妙阴影系统）
//
// 4 个标准层级。取代直接 .shadow() 调用。
// 所有阴影都是黑色低透明度，在两种模式下都自然。

struct ElevationStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum Elevation {
    /// 极轻：缩略图、按钮的 resting 状态
    static let subtle  = ElevationStyle(color: .black.opacity(0.04), radius: 2,  x: 0, y: 1)
    /// 强：hover 状态的缩略图
    static let strong  = ElevationStyle(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
}

// MARK: - 字体（V3.1 NEW：语义化字体层级）
//
// 设计原则：
// - 标题用 .rounded（SF Pro Rounded），更友好亲切
// - 数字用 .monospacedDigit()，宽度稳定不抖

enum Typography {
    /// 二级标题（多选计数等，比 title 略大）
    static let title2 = Font.system(size: 22, weight: .medium)
    /// 面板标题（详情面板、设置面板）
    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
    /// 章节小标题
    static let headline = Font.system(size: 15, weight: .semibold)
    /// 正文
    static let body = Font.system(size: 13)
    /// 辅助说明
    static let caption = Font.system(size: 11)
    /// 数字/计数（等宽）
    static let captionMono = Font.system(size: 11).monospacedDigit()
    /// 空状态大图标（详情面板 Empty/MultiSelect 的大号 SF Symbol）
    static let emptyStateIcon = Font.system(size: 60, weight: .light)
}

// MARK: - 旧 Palette 兼容层（V3.1 保留，Phase 2+ 逐步替换）
//
// 旧代码引用的 token 仍然可用，内部重定向到 Surface。

enum Palette {
    // 背景层级
    static let cellBackground = Surface.elevated
    static let cellEmpty = Color.gray.opacity(0.3)
    static let cellFilled = Color.gray.opacity(0.2)

    // 分隔线 / 边框
    static let chipBackground = Color.gray.opacity(0.15)

    // 强调色
    static let selectionOverlayMulti = Surface.selectedStrong
    static let selectionBorder = Color.accentColor

    // 状态色
    static let destructive = Surface.destructive
}

// MARK: - App Accent（V3.5.x 引入：可主题化的应用强调色）
//
// 设计意图：让占位/装饰性视图（如 MultiSelectDetailView 的图标）引用一个
// 语义化的"app 强调色"。
// V3.5.18：用户可在 SettingsView 里切换强调色，setter 重新启用。

private struct AppAccentEnvironmentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    /// App 级别的强调色，供装饰性视图使用
    var appAccent: Color {
        get { self[AppAccentEnvironmentKey.self] }
        set { self[AppAccentEnvironmentKey.self] = newValue }
    }
}

// MARK: - 动效（V3.6.11 NEW：统一动画 token）
//
// 设计原则：
// - 5 个标准时长（按"感知速度"命名，不用"slow/medium"等模糊词）
// - 1 个 spring 曲线（toast 弹出专用，比 easeInOut 更有"物理感"）
// - 集中调整一处即可全局影响（如未来调成更"快"或更"慢"风格）
//
// 用法：
// ```
// .animation(Animations.standard, value: isHovered)
// withAnimation(Animations.quick) { ... }
// ```

enum Animations {
    /// 最快：100ms，按压反馈（最高即时性）
    static let press: Animation = .easeInOut(duration: 0.1)
    /// 快：150ms，多选 toggle、焦点切换、沉浸式淡入
    static let quick: Animation = .easeInOut(duration: 0.15)
    /// 标准：200ms，hover、选中、Chrome 显示
    static let standard: Animation = .easeInOut(duration: 0.2)
    /// 中等：250ms，视图模式切换、sidebar 显隐
    static let medium: Animation = .easeInOut(duration: 0.25)
    /// 弹性 spring：toast 弹出（带"物理感"）
    static let springGentle: Animation = .spring(response: 0.35, dampingFraction: 0.85)
}
