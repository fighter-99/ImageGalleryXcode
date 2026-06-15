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
    /// V5.27: 6pt → 3pt——macOS Photos / Finder thumbnail 标准
    ///   - 6pt 偏大，让 cell "卡片" 感强 (iOS Photos 风格)
    ///   - 3pt 更 "原生"，不抢图
    ///   - 一处改全局一致：cell image clip / loading shimmer / failure placeholder / selection overlay
    /// V5.28: 3pt → 0pt——严格直角 (Photos.app Library 实际无圆角)
    ///   - macOS Photos.app Library cell 是 0 圆角 (严格直角)
    ///   - V5.26 1.5pt border + V5.27 3pt 圆角都是 Photos 痕迹
    /// V5.39.1: 0pt → 8pt——selection 框正方形 bug 修复 + 统一 square/masonry 圆角
    ///   - 0pt 让 cell/image clip/selection 全部退化为直角正方形
    ///   - 用户反馈"选中图片的框是正方形的, 不是选中整个缩略图"
    ///   - 4pt 圆角在 200pt cell 上太微妙 (2%), 6pt 仍读作"接近正方形"
    ///   - 8pt 圆角: square 模式 1:1 cell 也明显带圆角 (4%), masonry 模式 cell 形状变化时
    ///     圆角视觉一致, 不再有"square 无圆角 / masonry 有圆角"的割裂感
    ///   - 8pt 仍在 macOS Photos / Finder 缩略图圆角范围 (4-8pt) 内
    static let thumb: CGFloat = 8
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
// - V5.45: 按"场景"扩展 token（不按"权重"）——保证每个视觉场景都有专用 token
//   之前 7 个 token 太通用, 实际场景里 11+ 处写死 .system(size: ...) 散落
//   增 6 个场景化 token 后, 13 个 token 全覆盖 codebase 所有字号

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

    // V5.45: 按场景扩展 6 个新 token——之前散落写死 11 处 .system(size: ...) 统一收纳

    /// V5.45 NEW: 整页空态 icon——比 emptyStateIcon 大 1.33x
    ///   - MainSplitView 整 sidebar 空 / ImmersivePhotoView 沉浸式空
    ///   - 区别于 emptyStateIcon (60pt) 卡片内空态——80pt 视觉上"整页都没东西"
    static let emptyStateIconLarge = Font.system(size: 80, weight: .light)

    /// V5.45 NEW: 沉浸式大数字 (ImmersivePhotoView "1 / 5" 计数)
    ///   - 等宽数字——翻页时不抖
    ///   - 44pt 是 Photos.app QuickLook 风格的大数字
    static let immersiveCount = Font.system(size: 44).monospacedDigit()

    /// V5.45 NEW: 年份大标题 (ViewMode 时间线年份分隔)
    ///   - Photos.app "Years" 视图风格——年份是最大视觉锤
    ///   - .rounded + bold——既醒目又亲切
    static let yearTitle = Font.system(size: 34, weight: .bold, design: .rounded)

    /// V5.45 NEW: 详情面板小标签 (DetailView "标签"/"删除" 等字段标题)
    ///   - 比 caption (11pt) 大 1pt + bold——视觉层级清晰
    static let detailLabel = Font.system(size: 12, weight: .bold)

    /// V5.45 NEW: 日期 caption (cell 下方拍摄日期, masonry 模式)
    ///   - 同 body 13pt 但 weight: regular——cell 内信息"次要"层级
    static let dateCaption = Font.system(size: 13, weight: .regular)

    /// V5.45 NEW: 详情面板计数 (DetailView "1 / 5" 切换计数)
    ///   - 同 title2 (22pt) 但 weight: medium——大但比 title 略轻
    static let detailCount = Font.system(size: 22, weight: .medium)
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
    //   V4.8.1: 删 ToolbarSearchField 自绘——用 NSSearchField (AppKit 原生) 替代
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
    /// section header 字号——V4.48.0: caption2 (11pt) → 12pt
    ///   11pt 比行 label 13pt 小 2pt——段头"小一圈"不协调
    ///   12pt 缩差到 1pt + 与行 label 视觉更对齐
    ///   仍用 .semibold 保持"标题 vs 内容"层级
    static let headerFont: Font = .system(size: 12, weight: .semibold)
    /// section header 字号 (CGFloat 版) — token 一致性
    static let headerFontSize: CGFloat = 12
    /// section header 颜色——V4.48.0: secondary @ 0.7 → 0.85
    ///   0.7 太"淡"——与其他文本脱节
    ///   0.85 接近行 label 颜色 (Color.secondary 0.85) ——视觉协调
    static let headerColor: Color = Color.secondary.opacity(0.85)
    /// section header 上下 padding——视觉分组空间
    static let headerPaddingHorizontal: CGFloat = 12
    static let headerPaddingTop: CGFloat = 10
    static let headerPaddingBottom: CGFloat = 4
    /// section header icon↔title 间距
    static let headerIconSpacing: CGFloat = 5
    /// V4.48.0: section header icon 字号——10 → 12pt
    ///   与行 icon 13pt 差从 3pt 缩到 1pt——段头 icon 不"小一圈"
    static let headerIconSize: CGFloat = 12

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
    // V5.8: 砍 iconColorFavorite——V5.7 砍 .favorites 侧边栏后无 caller
    //   收藏 = 评分 ≥ 5，由筛选 popover 体现
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
    // V5.81: 180 → 150pt——placeholder 现在 "搜索照片、标签..." 短, 180pt 偏宽
    //   缩 30pt 给 toolbar 两侧按钮组 (4×28pt=112pt + 30pt 富余) 让出更多呼吸空间
    static let width: CGFloat = 150
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

// MARK: - V4.41.0 NEW: Popover 视觉 token
//
// 两个 popover（ViewOptions + Filter）共用同一套视觉 token。
// 之前 V4.36.x Filter 弃用 SwiftUI 改纯 AppKit（因为 SwiftUI intrinsic size 与 NSPopover
// 协商不一致导致 popover 裁切）——但视觉 token 没跟上 DesignTokens 系统。
// V4.41.0 抽 token 让两边引用，消除 11 项不一致点。
//
// 设计原则：
// - 段头：caption2 + uppercase + secondary（macOS Photos 标准）
// - item：28pt 居中高度（Photos 风格 44pt 太舒展，toolbar 风格 22pt 太紧凑）
// - 状态：active = accent + 白字；inactive = 6% primary 底 + primary 字
// - 暗色：全用系统色 token，自动适配
//
// SwiftUI / AppKit 双实现：ViewOptions 用 SwiftUI（popoverSegmentItem 风格），
// Filter 用 AppKit（NSButton + bezel）——token 字段两套并存，避免来回转换。

enum PopoverStyle {
    // ─── 布局 ───
    /// popover 宽度
    static let width: CGFloat = 240
    /// popover 内边距
    static let padding: CGFloat = Spacing.md
    /// 段间距——V4.42.0: 8 → 10 (更多垂直呼吸)
    /// V4.52.0: 10 → 12 (与 Photos 一致"宽间距"——段间更呼吸)
    /// V4.64.0: 12 → 10 (向 macOS Photos 实际紧凑感靠拢)
    ///   Photos 排序 popover 段间距 ~10pt
    ///   段头删除后段间靠留白过渡——过宽反而"散"
    static let sectionSpacing: CGFloat = 10
    /// 2 列布局列间距（folder/tag 段用）
    static let columnGap: CGFloat = 8

    // ─── 段头（section header） ───
    /// 段头字号——caption2 (11pt)
    /// V4.61.0 删 FilterPopoverViewController 段头后此 token 实际未用——保留兼容
    static let headerFontSize: CGFloat = 11
    /// 段头字重（SwiftUI 版本）——Font.Weight
    static let headerWeight: Font.Weight = .semibold
    /// 段头字重（AppKit 版本）——NSFont.Weight
    /// 注: Font.Weight 和 NSFont.Weight 标度相反（semibold 在 Font 是 0.3，在 NSFont 是 0.6）
    /// 不能直接转换——必须各设各的
    static let headerWeightAppKit: NSFont.Weight = .semibold
    /// 段头 icon↔title 间距——V4.42.0: 4 → 6 (icon 与 title 更舒展)
    static let headerIconSpacing: CGFloat = 6

    // ─── item 文字（list row） ───
    /// V4.72.0 NEW: item 文字字号——12pt
    ///   之前 L585 用 headerFontSize (11pt) 是错的——item 不是段头
    ///   12pt = macOS 系统 popover item 文字标准（Photos 实际 ~13pt）
    ///   item 24pt 配 12pt 字号 + 15pt icon = Photos 实际比例
    static let itemFontSize: CGFloat = 12
    /// 段头 icon 字号
    static let headerIconSize: CGFloat = 10
    /// 段头文字 uppercase（macOS Photos 风格）
    static let headerUppercased: Bool = true
    /// V4.43.1 NEW: 段头底边分隔线颜色——SwiftUI
    ///   段间视觉分组更明确（macOS Photos 风格）
    /// V4.53.0: 6% → 10% opacity——transl material 上保持可见
    ///   V4.47.0 transl 亮色后 6% 几乎不可见——段间"看起来糊"
    static let headerSeparatorColor: Color = Color.primary.opacity(0.10)
    /// V4.43.1 NEW: 段头底边分隔线颜色——AppKit 版
    /// V4.53.0: 0.06 → 0.10 opacity
    static let headerSeparatorColorAppKit: NSColor = NSColor(white: 0, alpha: 0.10)
    /// V4.43.1 NEW: 段头底边分隔线高度
    /// V4.53.0: 0.5 → 1pt——V4.47.0 transl 亮色后 0.5pt 太细
    static let headerSeparatorHeight: CGFloat = 1

    // ─── item（segment / list row） ───
    /// item 高度
    ///   V4.42.0: 28 → 32 (略增, 让 16pt icon + caption2 label 不挤)
    ///   V4.47.0: 32 → 28 (回收)——V4.45.0 transl material + 4 段全展开
    ///     让 popover 720pt 超窗口可视区。28pt 减 ~88pt 高度
    ///     仍能装下 16pt icon (item 减 4pt 不挡 icon) = Photos 平衡点
    ///   V4.64.0: 28 → 26 (向 macOS Photos 实际紧凑感靠拢)
    ///   V4.71.0: 26 → 24 (更接近 Photos 实际 22-24pt 范围)
    ///     装 15pt icon (item 减 9pt) + 1 列 row 间距 2pt = 更紧凑
    static let itemHeight: CGFloat = 24
    /// item 圆角——V4.42.0: 6 → 8 (略增, 更现代圆润)
    ///   V4.64.0: 8 → 4 (向 macOS Photos 实际风格靠拢)
    ///     Photos 排序 popover item 圆角很小（接近 0）
    ///     4pt = 微弱圆角，保留现代感 + Photos 紧凑感
    static let itemCornerRadius: CGFloat = 4
    /// segment 之间的间距——V4.42.0: 4 → 6 (相邻 segment 不再贴紧)
    static let segmentGap: CGFloat = 6
    /// 2 列布局的 VStack 行间距——V4.42.0: 2 → 4 (checkbox 行间更舒展)
    static let columnRowGap: CGFloat = 4
    /// item 内垂直 padding——V4.42.0 新增: 4pt (让 icon 不贴边)
    /// V4.52.0: 4 → 6pt (item 内 padding 增加——视觉"不挤")
    static let itemVerticalPadding: CGFloat = 6
    /// item 内水平 padding——V4.52.0 新增: 8pt (与垂直对称)
    ///   之前只有 .padding(.horizontal, 8) 散在代码——token 化 + 略增
    static let itemHorizontalPadding: CGFloat = 8
    /// icon 字号——V4.42.0 新增: 16pt (从 14pt 增, 与 itemHeight 32 比例协调)
    /// V4.47.0: 仍 16pt (item 28pt 装 16pt icon 上下 6pt 留白——更紧凑但图标清楚)
    /// V4.64.0: 16 → 15pt (向 macOS Photos 实际紧凑感靠拢)
    ///   26pt item 装 15pt icon 上下 5pt 留白 = 紧凑 Photos 风
    static let iconFontSize: CGFloat = 15

    // ─── 状态色（SwiftUI 版本） ───
    /// active 背景
    static let activeBackground: Color = .accentColor
    /// active 文字
    static let activeText: Color = .white
    /// inactive 背景
    ///   V4.42.0: primary.opacity(0.06) → 0.10 (更多可见度)
    ///   V4.46.0: 0.10 → 0.14 — transl material 上 10% 实际视觉仅 ~5%
    ///   14% 抵消 transl 透明度损失，保持 active vs inactive 区分度
    static let inactiveBackground: Color = Color.primary.opacity(0.14)
    /// inactive 文字
    static let inactiveText: Color = .primary
    /// V4.43.0 NEW: hover 背景——inactive items 在鼠标悬停时显示
    ///   14% → 18% (略加深，给"可点击"反馈)
    ///   active items 不变 (accent 实色，hover 加深没意义)
    static let hoverBackground: Color = Color.primary.opacity(0.18)

    /// V4.43.0 NEW: sort item 文字字号——12pt (原 13pt .callout)
    ///   缩小让 sort item 视觉密度与 segment item (icon 16pt + label 11pt) 更协调
    ///   V4.64.0: 12 → 13pt (向 macOS Photos 实际紧凑感靠拢)
    ///     13pt 是 macOS 系统 popover 文字标准——itemHeight 26pt 配 13pt
    static let sortItemFontSize: CGFloat = 13

    // ─── 状态色（AppKit 版本） ───
    /// active 背景：NSColor.controlAccentColor（与 SwiftUI .accentColor 同源）
    static let activeBackgroundAppKit: NSColor = .controlAccentColor
    /// active 文字
    static let activeTextAppKit: NSColor = .white
    /// inactive 背景
    ///   V4.42.0: 6% black → 10% black (更多可见度)
    ///   V4.46.0: 0.10 → 0.14 — transl material 上 10% 实际视觉仅 ~5%
    ///   14% 抵消 transl 透明度损失，保持 active vs inactive 区分度
    static let inactiveBackgroundAppKit: NSColor = NSColor(white: 0, alpha: 0.14)
    /// inactive 文字
    static let inactiveTextAppKit: NSColor = .labelColor
    /// V4.43.1 NEW: 状态变化过渡动画时长
    ///   0.15s easeInOut——macOS 标准 "瞬时但不突兀" 过渡
    ///   V4.17.0 DetailView spring 动画 (response 0.4, damping 0.8) 偏 Q 弹
    ///   popover state 切换用更短更平——避免 "Q 弹" 在快速点击时累赘
    static let stateTransitionDuration: Double = 0.15

    // ─── V4.79.0 NEW: 顶层 popover host 视觉 token ───
    /// popover host 圆角——12pt
    ///   item cornerRadius (4pt) 之外另设——host 比 item 大
    ///   V4.45.0 FilterPopoverViewController 写死 12——抽 token
    ///   V4.77.0 ViewOptionsPopoverHostController 写死 12——同上
    static let hostCornerRadius: CGFloat = 12
    /// popover host 边框宽度——0.5pt
    ///   V4.67.0 引入——dark mode + transl material 边界强化
    static let hostBorderWidth: CGFloat = 0.5

    // ─── V4.79.0 NEW: 顶层 popover 4 类别行专用 token ───
    /// V5.63-3: 类别行高度 32→40pt——更易点击 target + 视觉 breathing, 仿 macOS Photos
    static let categoryRowHeight: CGFloat = 40
    /// 类别行 icon 字号——15pt（与 item icon 一致）
    static let categoryRowIconSize: CGFloat = 15
    /// 类别行 chevron 字号——9pt（chevron 比 icon 小——次要视觉元素）
    static let categoryRowChevronSize: CGFloat = 9
    /// V5.63-3: count badge 数字字号 11→10pt——更轻量, 仿 macOS Photos
    static let categoryRowCountBadgeSize: CGFloat = 10
    /// 类别行 count badge 高度——16pt（圆形/胶囊形高度）
    static let categoryRowCountBadgeHeight: CGFloat = 16
    /// V5.63-3: count badge 背景透明度 12→10% accent——更轻, 不与整行 tint 争抢对比
    static let categoryRowCountBadgeOpacity: CGFloat = 0.10
}
