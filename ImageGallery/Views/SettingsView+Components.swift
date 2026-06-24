import SwiftUI
import AppKit

//
// 截图1.png 视觉规范:
//   - 顶层 group label: 16pt semibold (Photos iCloud page "iCloud 照片")
//   - 描述: 11pt secondary, indent 跟 group label 起点对齐
//   - radio 选项: 圆圈 + label, **indented +32pt** from group
//   - radio 描述: 11pt secondary, indent 跟 radio 对齐
//
// PhotosSettingRow — 单个 setting row (title + desc + trailing control)
//   替代之前 "label 80pt 固定列宽 + Picker" 模式
// PhotosRadioGroup — radio 选项容器 (用于 hierarchical settings)

/// V6.42: Photos 风格 setting row — 单行设置 (title + description + trailing control)
///   Title 16pt semibold + 11pt secondary description (跟截图 iCloud 行的 visual hierarchy 一致)
///   trailing control 在 right (Picker / Toggle / Slider)
struct PhotosSettingRow<Trailing: View>: View {
    let title: String
    let description: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.description = description
        self.trailing = trailing
    }

    var body: some View {
        // V6.42: Photos 风格 — leading 是 title/desc stack, trailing 是 control
        //   Spacer 让 control 推到右侧; baseline alignment 让 control 跟 title 对齐
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.md)
            trailing()
        }
    }
}

/// V6.42: Photos 风格 radio option — 单个 radio 选项
///   圆圈 + label (14pt regular) + description (11pt)
///   Photos 选中态: 实心圆点 (蓝) — 用 SF Symbol circle.inset.filled
///   未选中: 空圆圈 — SF Symbol circle
struct PhotosRadioOption<Trailing: View>: View {
    let title: String
    let description: String?
    let isSelected: Bool
    let onTap: () -> Void
    @ViewBuilder let trailing: (() -> Trailing)?
    // V6.58 (audit P1.6 follow-up): @State 提到 struct 字段
    @State private var isHovered = false

    init(
        title: String,
        description: String? = nil,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.onTap = onTap
        self.trailing = trailing
    }

    var body: some View {
        // V6.45: hover state — radio option 在鼠标悬停时背景微微变深
        //   Photos 真版 feedback: hover 给用户"可点"暗示, 不像 click 按钮那么重
        return Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(Typography.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                            .font(Typography.caption)
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Spacing.md)
                if let trailing {
                    trailing()
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                isHovered && !isSelected ? Surface.hover : .clear,
                in: RoundedRectangle(cornerRadius: Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// V6.43: Photos 风格 checkbox — SF Symbol 模拟 macOS Sonoma+ 蓝填充框
///   选中: `checkmark.square.fill` (蓝底白勾)
///   未选: `square` (灰框)
///   替代 .toggle 的 switch 样式 — macOS Photos 用 checkbox 而非 switch
struct PhotosCheckbox: View {
    let title: String
    let description: String?
    // V6.58 (audit P1.6): 改 @Binding 取代 Bool + onToggle 分离
    //   之前 caller 写 `$settings.X.wrappedValue` (Bool) + `onToggle: { settings.X.toggle() }`,
    //   外部 mutation (例如 reset()) 不会更新 checkbox 视觉 (因为没监听变化)
    //   现在 @Binding 直接绑, SwiftUI 自动追踪 source of truth
    @Binding var isOn: Bool
    // V6.58: @State 提到 struct 字段 (之前在 body 内是非 idiomatic)
    @State private var isHovered = false

    var body: some View {
        // V6.48: hover 反馈 — 跟 PhotosRadioOption + CategoryTabButton 一致
        //   未选 checkbox 悬停时 Surface.hover 浅背景 — 用户感觉"可点"
        //   选中时不显示 hover (避免视觉冲突)
        return Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(Typography.subheadline)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                            .font(Typography.caption)
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Spacing.md)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                isHovered && !isOn ? Surface.hover : .clear,
                in: RoundedRectangle(cornerRadius: Radius.sm)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// V6.43: Photos 风格 setting with radios — vertical stack of PhotosRadioOption
///   用于 settings 有多个选项 (替代 .menu Picker + SettingsSection 嵌套)
///   跟截图 iCloud page "iCloud 照片" group label 一样: title + description + 子 radios stacked
struct PhotosSettingRadios<T: Hashable>: View {
    let title: String
    let description: String?
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let optionDescription: (T) -> String?

    init(
        title: String,
        description: String? = nil,
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String,
        optionDescription: @escaping (T) -> String? = { _ in nil }
    ) {
        self.title = title
        self.description = description
        self.options = options
        self._selection = selection
        self.label = label
        self.optionDescription = optionDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(Typography.caption)
                        .foregroundStyle(Surface.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    PhotosRadioOption(
                        title: label(option),
                        description: optionDescription(option),
                        isSelected: selection == option,
                        onTap: { selection = option }
                    )
                }
            }
        }
    }
}

// MARK: - V6.89: 顶部 tab 改 Picker(.segmented) — 紧凑 + 真版对齐
//  V6.87 + V6.88 实施自定义 button tab (80×60pt + 22pt icon + subheadline label), 用户实测反馈过大
//  V6.89: 改 macOS 真版 Picker(.segmented) — 紧凑系统 widget, 选中态系统 tint 背景
//  删 CategoryTabButton (整个 struct, ~70 LOC) — segmented 不需要自定义 button
//  7 个 category 用 segmented 自动 fit, NSSegmentedControl 系统级 widget 视觉锤
//  保留 ScrollViewReader 暂不需要 (segmented 不溢出, 自动 fit), 后续若窗口过窄再加滚动
struct CategoryTabBar: View {
    @Binding var selection: SettingsCategory

    var body: some View {
        // V6.89: Picker(.segmented) — macOS 系统级 NSSegmentedControl
        //   7 个 category 自动 fit, 选中态系统 tint 背景, 无 icon, 纯 text label
        //   紧凑 (高度 ~24pt vs 原 V6.88 60pt), 跟 macOS 真版 System Preferences 顶部 widget 一致
        //   .labelsHidden() 隐藏默认 label (Picker API 要求提供但视觉隐藏)
        Picker("", selection: $selection) {
            ForEach(SettingsCategory.allCases) { category in
                Text(category.title).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // V6.89: padding — segmented control 跟窗口边缘视觉缓冲
        //   横向 Spacing.xl (20pt) 跟 detail 内容对齐 (V6.86 大标题 padding 一致)
        //   纵向 Spacing.sm (8pt) — segmented 紧凑, 不需要 Spacing.md 12pt
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        // V6.89: 保留 .background(.bar) — segmented 跟 macOS 真版 toolbar frosted glass 一致
        .background(.bar)
        // V6.90.5: chrome 整合 — Divider tint alpha 0.3 让 chrome 跟 detail 视觉融合
        //   原 Divider() 默认 alpha 1.0 视觉上过抢, 跟 detail 强分隔
        //   改 alpha 0.3 减弱视觉, 让 chrome 跟 detail 是一体 (跟 macOS Sonoma+ System Preferences 真版一致)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.3)
        }
    }
}

// MARK: - 通用 settings section 容器 (沿用 V5.89 fluid rows 设计)
