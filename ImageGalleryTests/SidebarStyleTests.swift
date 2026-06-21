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

    @Test func activeBackgroundUsesSystemSelectedContent() {
        // V6.61: 选中态改用 NSColor.selectedContentBackgroundColor 系统实色
        //   替代 V6.32.1 的 Surface.selectedLight (0.12 opacity accent)
        //   理由: macOS Photos / Finder 选中态都用系统实色, light/dark 自动适配
        let systemColor = Color(nsColor: .selectedContentBackgroundColor)
        #expect(SidebarStyle.activeBackground == systemColor)
    }

    @Test func hoverBackgroundMatchesSurfaceHover() {
        // hover 比选中弱 3 倍（0.04 vs 0.12）
        #expect(SidebarStyle.hoverBackground == Surface.hover)
    }

    @Test func labelActiveIsWhiteAndDifferFromDefault() {
        // V6.61: labelActive 改 .white (跟 macOS 系统选中行白字一致)
        //   labelDefault + labelHover 都是 .primary (hover 不变色, 只 active 变白)
        //   只 active 一档跟 default/hover 不同, 通过背景 activeBackground 反衬
        #expect(SidebarStyle.labelActive == Color.white)
        #expect(SidebarStyle.labelDefault == Color.primary)
        #expect(SidebarStyle.labelActive != SidebarStyle.labelDefault)
    }

    @Test func iconDefaultIsSecondary() {
        // 默认 icon 用 secondary（弱化视觉权重）
        #expect(SidebarStyle.iconDefault == Color.secondary)
    }

    @Test func iconActiveIsWhite() {
        // V6.61: 选中态 icon 改 .white (跟 macOS 系统选中白字一致)
        //   替代 V4.6.0 的 Color.accentColor
        //   hover 态仍走 iconActive (跟 labelActive 同步)
        #expect(SidebarStyle.iconActive == Color.white)
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

    @Test func smartFolderIconColorsAreFiveDistinctColors() {
        // 5 个语义色 slots 中有 4 个独立色相（duplicate + trash 同 orange 共用警示色族）
        // 这是设计选择——重复图和最近删除都属于"需要用户注意"的语义类别
        // 用同一色族保持视觉一致：橘色 = "警示/需要处理"
        let colors: [Color] = [
            SidebarStyle.iconColorDuplicate,   // .orange
            SidebarStyle.iconColorRecent,      // .blue
            SidebarStyle.iconColorLarge,       // .purple
            // V5.8: 砍 iconColorFavorite——收藏 = 评分 ≥ 5 走筛选 popover
            SidebarStyle.iconColorTrash        // .orange (与 duplicate 同色)
        ]
        let uniqueColors = Set(colors.map { String(describing: $0) })
        #expect(uniqueColors.count == 3, "4 个 slots 共享 3 个独立色相：橙/蓝/紫")
    }

    @Test func smartFolderIconColorsMatchSystemColors() {
        // 锁定具体色值——避免未来某次"统一化"改动破坏视觉锚点
        // 重复图 + 最近删除 都用 orange（同色族警示）
        // V5.8: 砍 iconColorFavorite 测试——V5.7 砍 .favorites 侧边栏时遗漏
        #expect(SidebarStyle.iconColorDuplicate == .orange)
        #expect(SidebarStyle.iconColorTrash == .orange)
        #expect(SidebarStyle.iconColorRecent == .blue)
        #expect(SidebarStyle.iconColorLarge == .purple)
    }

    // MARK: - Font token 引用一致性
    //
    // SwiftUI Font 没有公共 Equatable——这些测试是"引用一致性"守护：
    // SidebarRow/SidebarSectionHeader 引用了这些 token 常量
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
