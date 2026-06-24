//
//  SidebarStyleTests.swift
//  ImageGalleryTests
//
//  V4.6.0: SidebarStyle token 单元测试。
//  V6.61: 选中态改用 NSColor.selectedContentBackgroundColor 系统实色 (macOS 标准)
//         labelActive/iconActive 改 .white (跟系统选中白字一致)
//
//  设计原则：
//  - 行高 28pt 是 macOS Photos / Finder 侧栏标准——锁定数值防止回归
//  - 字号 13pt label + 11pt count 平衡"内容可读性"与"密度"
//  - 智能 folder icon 用 5 种语义色（橙/蓝/紫/金/橙），色相互不重叠
//  - 选中态用系统 NSColor.selectedContentBackgroundColor + 白字
//
//  锁定这些 token 数值后，sidebar 视觉打磨的所有边界条件就有了
//  "测试守护线"——避免未来某次改动偷偷调大字号或调小行高。
//
//  注: SwiftUI Font 没有公共 Equatable，所以 Font token 不直接对比——
//  它的字面常量在 DesignTokens.swift 编译时锁定，调用点引用 token 即可
//  防止回归（vs 在调用点硬编码 ".callout" / ".body"）。
//

import Testing
import SwiftUI
@testable import ImageGallery

struct SidebarStyleTests {

    // MARK: - 行（row）token

    @Test func rowHeightIs28() {
        // 锁定 macOS Photos / Finder 侧栏标准行高
        #expect(SidebarStyle.rowHeight == 28)
    }

    @Test func rowHorizontalPaddingIs8() {
        #expect(SidebarStyle.rowHorizontalPadding == 8)
    }

    @Test func rowBackgroundInsetIs4() {
        // 让背景不到边缘 4pt——macOS 标准"胶囊"风格
        #expect(SidebarStyle.rowBackgroundInset == 4)
    }

    @Test func rowIconTextSpacingIs8() {
        #expect(SidebarStyle.rowIconTextSpacing == 8)
    }

    @Test func rowTextCountSpacingIs4() {
        #expect(SidebarStyle.rowTextCountSpacing == 4)
    }

    @Test func rowCornerRadiusMatchesRadiusSm() {
        // 与 Radius.sm (6pt) 统一——避免 sidebar 出现"独立 6pt"
        #expect(SidebarStyle.rowCornerRadius == Radius.sm)
        #expect(SidebarStyle.rowCornerRadius == 6)
    }

    // MARK: - 图标（icon）token

    @Test func iconSizeIs13() {
        // 与 label 字号一致——视觉同步
        #expect(SidebarStyle.iconSize == 13)
    }

    @Test func iconFrameWidthIs18() {
        #expect(SidebarStyle.iconFrameWidth == 18)
    }

    // MARK: - 状态色

    @Test func activeBackgroundUsesAccentTint() {
        // V6.96: 选中态改 Color.accentColor.opacity(0.15) — 跟 macOS Sonoma+ Photos 真版一致
        //   之前 V6.61 NSColor.selectedContentBackgroundColor 系统灰色 (跟 accent 脱钩)
        //   现在 accent tint (0.15 opacity) — 选中态跟 accent color 主题联动
        //   Photos 真版选中态用 accent color tint (半透明), 跟 macOS 真版一致
        let expected = Color.accentColor.opacity(0.15)
        #expect(SidebarStyle.activeBackground == expected)
    }

    @Test func hoverBackgroundMatchesSurfaceHover() {
        // hover 比选中弱 3 倍（0.04 vs 0.12）
        #expect(SidebarStyle.hoverBackground == Surface.hover)
    }

    @Test func labelActiveIsAccentAndDifferFromDefault() {
        // V6.96: labelActive 改 .accentColor (跟 macOS Sonoma+ 真版一致)
        //   之前 V6.61 .white 适配旧灰色 activeBackground, 现在 activeBackground 改 accent tint
        //   labelDefault + labelHover 都是 .primary (hover 不变色, 只 active 变 accent)
        #expect(SidebarStyle.labelActive == Color.accentColor)
        #expect(SidebarStyle.labelDefault == Color.primary)
        #expect(SidebarStyle.labelActive != SidebarStyle.labelDefault)
    }

    @Test func iconDefaultIsSecondary() {
        // 默认 icon 用 secondary（弱化视觉权重）
        #expect(SidebarStyle.iconDefault == Color.secondary)
    }

    @Test func iconActiveIsAccent() {
        // V6.96: 选中态 icon 改 .accentColor — 跟 labelActive 同步
        //   之前 V6.61 .white 适配旧灰色 activeBackground
        #expect(SidebarStyle.iconActive == Color.accentColor)
    }

    // MARK: - section header

    @Test func headerPaddingValues() {
        #expect(SidebarStyle.headerPaddingHorizontal == 12)
        #expect(SidebarStyle.headerPaddingTop == 10)
        // V6.54 (design polish): 4 → 8 — section 之间视觉呼吸更足, 跟 Photos 真版对齐
        #expect(SidebarStyle.headerPaddingBottom == 8)
    }

    @Test func headerColorIsTertiaryLabelSystem() {
        // V6.61: headerColor 改用 NSColor.tertiaryLabelColor 系统实色 (light/dark 自动适配)
        //   替代 V6.23 的 Color.secondary.opacity(0.65) — 旧值在 dark 下偏暗
        //   注意: 由于 polish 后 SidebarView 用 DisclosureGroup 原生 header, headerColor
        //   主要供未来 section header 引用; 当前 caller = 0
        let expected = Color(nsColor: .tertiaryLabelColor)
        #expect(SidebarStyle.headerColor == expected)
    }

    // MARK: - 智能 folder icon 语义色
//
// V6.97 P3-6: 删 2 个 dead test — P1-10 删了 iconColorDuplicate/Recent/Large token
//   SidebarStyle 只剩 iconColorTrash, 不再需要 "4 个 slot 色相" 测试
//
// MARK: - Font token 引用一致性
    //
    // SwiftUI Font 没有公共 Equatable——这些测试是"引用一致性"守护：
    // SidebarRow 引用了这些 token 常量 (V6.62 P4.1: SidebarSectionHeader 已删, 仅 SidebarRow 引用)
    // （如果某天有人改成硬编码 ".callout"，会失去单一真相源）
    //
    // 测试意义：编译通过即代表 token 存在 + 被引用

    @Test func fontTokensAreReferenceable() {
        // 引用 token——如果 token 不存在/拼写错误，这里编译失败
        let _: Font = SidebarStyle.labelFont
        let _: Font = SidebarStyle.labelSelectedFont
        let _: Font = SidebarStyle.countFont
        let _: Font = SidebarStyle.headerFont
        let _: Font.Weight = SidebarStyle.iconWeight
    }
}
