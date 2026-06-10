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
    static let md: CGFloat = 8      // 中：卡片
    static let lg: CGFloat = 12     // 大：大卡片、tag chip

    /// V4.4.0 NEW: 缩略图 cell 专用——统一所有缩略图相关圆角
    /// 之前 cell 外层 cornerRadius 6 vs selectionOverlay/加载占位/多选蒙层
    /// 用 Radius.md (8pt) 不一致 → 选中边框 8pt 罩在 6pt cell 上漏 1pt 白边
    /// 现在所有缩略图相关 RoundedRectangle 统一引用 Radius.thumb
    static let thumb: CGFloat = 6
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
    /// V4.6.0: 0.10 → 0.12——sidebar active row 视觉锤（"胶囊"效果更明确）
    static let selected = Color.accentColor.opacity(0.12)
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
    // V3.6.14: 暗色下用 NSColor.separatorColor 系统色（自动适配亮/暗）
    static let cardBorder = Color(nsColor: .separatorColor)

    // ─── 工具栏专用（V3.1 Phase 1.5） ───
    /// 工具栏内分组背景（segments、菜单、搜索）
    /// 比 .hover 略深（0.04 → 0.06），让分组在工具栏上更可见
    static let toolbarControl = Color.primary.opacity(0.06)
}

// MARK: - 阴影（V3.1 NEW：微妙阴影系统）
//
// 4 个标准层级。取代直接 .shadow() 调用。
// V3.6.14 暗色适配：shadow 改用 NSColor.shadowColor 系统色 + 不同 alpha
// （之前 .black.opacity 暗色下几乎不可见）

struct ElevationStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum Elevation {
    /// 极轻：缩略图、按钮的 resting 状态
    /// V3.6.14: 暗色下用更高 alpha（0.10）让阴影可见
    static let subtle  = ElevationStyle(color: Color(nsColor: .shadowColor).opacity(0.08), radius: 2,  x: 0, y: 1)
    /// 强：hover 状态的缩略图
    static let strong  = ElevationStyle(color: Color(nsColor: .shadowColor).opacity(0.20), radius: 12, x: 0, y: 4)
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
    // V3.6.14: 暗色下用 NSColor.quaternaryLabelColor 系统色（自动适配）
    static let cellEmpty = Color(nsColor: .quaternaryLabelColor)
    static let cellFilled = Color(nsColor: .quaternaryLabelColor).opacity(0.7)

    // 分隔线 / 边框
    // V3.6.14: 暗色下用 NSColor.controlBackgroundColor 系统色
    static let chipBackground = Color(nsColor: .controlBackgroundColor)

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

// MARK: - 动效（V3.6.11 NEW：统一动画 token；V4.0.0 升级）
//
// 设计原则：
// - 5 个标准时长（按"感知速度"命名，不用"slow/medium"等模糊词）
// - 1 个 spring 曲线（toast 弹出专用，比 easeInOut 更有"物理感"）
// - 集中调整一处即可全局影响（如未来调成更"快"或更"慢"风格）
// - V4.0.0: standard / medium 改从 easeInOut → spring（统一 spring 风格）
// - V4.0.0: springGentle 重命名为 interactive（语义更清晰）
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
    /// 标准：200ms spring，hover、选中、Chrome 显示
    /// V4.0.0: 改从 easeInOut → spring
    static let standard: Animation = .spring(response: 0.3, dampingFraction: 0.85)
    /// 中等：250ms spring，视图模式切换、sidebar 显隐
    /// V4.0.0: 改从 easeInOut → spring
    static let medium: Animation = .spring(response: 0.3, dampingFraction: 0.85)
    /// 弹性 spring：toast 弹出 / 选中 / sidebar 进出
    /// V4.0.0: 重命名 springGentle → interactive（语义更清晰）
    static let interactive: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    /// V4.0.0 兼容别名——旧代码用 springGentle 的地方仍能编译（过渡期）
    static var springGentle: Animation { interactive }
    /// V4.0.0 NEW: 弹性更"Q"的 spring（带轻微反弹，用于 toast / 重要操作确认）
    static let bouncy: Animation = .spring(response: 0.4, dampingFraction: 0.7)
}

// MARK: - V4.0.0 NEW: 工具栏样式 token

enum ToolbarStyle {
    /// macOS 原生 toolbar 高度（unified 模式系统决定，留常量给测试）
    static let height: CGFloat = 52       // unified 默认
    static let heightCompact: CGFloat = 28 // V4.0.2 用户选"紧凑"
    static let spacing: CGFloat = 8        // ToolbarItem 之间

    // V4.3.0 删除：自绘按钮相关 token（已不再用）
    //   - highlightRadius (RoundedRect 圆角)
    //   - buttonRestingTint / HoverTint / ActiveTint (Color.primary.opacity 等级)
    //
    //   V4.2.x 5 轮在自绘 buttonStyle 上反复调，最终回归原生 Button + Label，
    //   所有按钮 hover / focus / pressed 由 macOS 系统接管，无需 token
    //
    //   ToolbarSearchField 仍自绘（项目无 NavigationStack），但只用 .quaternary
    //   material + 6pt 圆角直接硬编码，无须 token 维护
}

// MARK: - V4.0.0 NEW: 窗口 chrome token

enum WindowChrome {
    /// hiddenTitleBar 后，内容区起始 Y 偏移
    static let topInset: CGFloat = 0
    /// 侧栏"折叠/展开"按钮的额外 padding
    static let navButtonPadding: CGFloat = 12
}

// MARK: - V4.6.0 NEW: 侧栏视觉 token
//
// 设计原则：
// - 行高 28pt 是 macOS Photos / Finder 侧栏标准
// - 字号 13pt label + 11pt count 平衡"内容可读性"与"密度"
// - 智能 folder icon 用语义色——一眼区分内容类型（重复/最近/大图/收藏/最近删除）
// - 选中态高亮 0.12 opacity——比 hover (0.04) 强 3 倍，视觉锤足够
//
// 与 V4.4.5 cell 浅框教训呼应：sidebar 不放 resting shadow、不放 hover shadow，
// 仅靠 background 颜色变化区分状态——避免 5 个浅框真凶链

enum SidebarStyle {
    // ─── 行 (row) ───
    /// 行高——macOS Photos / Finder 侧栏标准
    static let rowHeight: CGFloat = 28
    /// 行内左右 padding（视觉上不到侧栏边缘，配合背景 padding 形成 inset 效果）
    static let rowHorizontalPadding: CGFloat = 8
    /// 行背景外侧 padding（让背景不到侧栏边缘 4pt，macOS 标准风格）
    static let rowBackgroundInset: CGFloat = 4
    /// 行圆角——用 Radius.sm (6pt) 与其他 UI 组件统一
    static let rowCornerRadius: CGFloat = Radius.sm
    /// 行内 icon↔text 间距
    static let rowIconTextSpacing: CGFloat = 8
    /// 行内 text↔count 最小间距
    static let rowTextCountSpacing: CGFloat = 4

    // ─── 图标 (icon) ───
    /// icon 字号——与 label 字号 13pt 一致
    static let iconSize: CGFloat = 13
    /// icon 字重
    static let iconWeight: Font.Weight = .medium
    /// icon 框架宽度（让所有 icon 对齐）
    static let iconFrameWidth: CGFloat = 18

    // ─── 文字 (label + count) ───
    /// label 字号 13pt——macOS Photos / Finder 侧栏标准
    /// V4.6.0: 之前用 .callout (16pt) 太大，sidebar 显得拥挤
    static let labelFont: Font = .system(size: 13, weight: .regular)
    /// label 选中态字重——加粗视觉锤（V4.1.0B 引入，V4.6.0 token 化）
    static let labelSelectedFont: Font = .system(size: 13, weight: .semibold)
    /// count 字号 11pt + 等宽数字（防止数字宽度抖动）
    static let countFont: Font = .system(size: 11).monospacedDigit()

    // ─── 状态色 ───
    /// hover 背景色——Surface.hover 0.04
    static let hoverBackground: Color = Surface.hover
    /// 选中背景色——Surface.selected 0.12（V4.6.0 从 0.10 提至 0.12）
    static let activeBackground: Color = Surface.selected
    /// 默认 label 颜色
    static let labelDefault: Color = Color.primary.opacity(0.85)
    /// hover label 颜色
    static let labelHover: Color = Color.primary
    /// 选中 label 颜色
    static let labelActive: Color = Color.accentColor
    /// 默认 icon 颜色
    static let iconDefault: Color = Color.secondary
    /// hover/选中 icon 颜色（保持与 label 一致——视觉关联）
    static let iconActive: Color = Color.accentColor

    // ─── section header ───
    /// section header 字号——caption2 (11pt) semibold
    static let headerFont: Font = .caption2.weight(.semibold)
    /// section header 颜色——.tertiary 等价值
    /// 注: Color 没有 .tertiary（tertiary 是 ShapeStyle 概念），用 secondary 70% opacity 模拟
    static let headerColor: Color = Color.secondary.opacity(0.7)
    /// section header 上下 padding——视觉分组空间
    static let headerPaddingHorizontal: CGFloat = 12
    static let headerPaddingTop: CGFloat = 10
    static let headerPaddingBottom: CGFloat = 4
    /// section header icon↔title 间距
    static let headerIconSpacing: CGFloat = 5

    // ─── 智能 folder icon 语义色 ───
    //
    // 一眼区分内容类型——不依赖文案理解
    // 色板：色相分散（HLS space 60°+ 间隔），避免混淆
    //
    /// 重复图——橙色（警示/注意）
    static let iconColorDuplicate: Color = .orange
    /// 最近 7 天——蓝色（新鲜/时间）
    static let iconColorRecent: Color = .blue
    /// 大图——紫色（文件体积/重量）
    static let iconColorLarge: Color = .purple
    /// 收藏——金色（重要/标记）
    static let iconColorFavorite: Color = .yellow
    /// 最近删除——橙色（警示，与重复图共用色族但更饱和）
    /// 条件：trashed > 0 时显示，空时不显示（保持简洁）
    static let iconColorTrash: Color = .orange
}

// MARK: - V4.0.0 NEW: 材质 token（集中管理 .regularMaterial / .quaternary 等）

enum Material {
    /// drop overlay 背景（半透明 + blur）
    static let dropOverlay: AnyShapeStyle = AnyShapeStyle(.regularMaterial)
    /// status bar 背景（半透明 + blur，自动适配暗色）
    static let statusBar: AnyShapeStyle = AnyShapeStyle(.regularMaterial)
    /// toolbar segmented 容器（替代旧 Surface.toolbarControl 的实心色）
    static let toolbarControl: AnyShapeStyle = AnyShapeStyle(.quaternary)
    /// confirmation dialog 卡片
    static let dialog: AnyShapeStyle = AnyShapeStyle(.regularMaterial)
}

// MARK: - V4.0.1 NEW: 状态栏升级指标

enum StatusBarMetrics {
    static let height: CGFloat = 24
    static let progressBarHeight: CGFloat = 3
    static let popoverWidth: CGFloat = 360
}

// MARK: - V4.0.1 NEW: 搜索框指标

enum SearchFieldMetrics {
    // V4.0.0.4: 240 → 200pt——视觉上不再抢戏（toolbar 整体更平衡）
    // V4.2.3: 200 → 170pt——给两侧按钮组让出呼吸空间
    // V4.2.4: 170 → 180pt——170 装不下原 placeholder "搜索文件名、标签、备注"
    //   配合 placeholder 缩短为 "搜索照片、标签..." 两手抓
    static let width: CGFloat = 180
    static let widthExpanded: CGFloat = 360  // 展开历史时（V4.0.1 智能搜索）
    static let height: CGFloat = 30          // V4.0.0.4 与其他 item 对齐
}

// MARK: - V4.0.2 NEW: 窗口模式指标

enum WindowModeMetrics {
    /// viewerOnly 模式下的工具栏高度（紧凑）
    static let viewerToolbarHeight: CGFloat = 32
    /// viewerOnly 模式下的图片 padding
    static let viewerImagePadding: CGFloat = 40
}
