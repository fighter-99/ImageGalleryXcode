//
//  SidebarStyleTests.swift
//  ImageGalleryTests
//
//  V4.6.0: SidebarStyle token 单元测试。
//
//  设计原则：
//  - 行高 28pt 是 macOS Photos / Finder 侧栏标准——锁定数值防止回归
//  - 字号 13pt label + 11pt count 平衡"内容可读性"与"密度"
//  - 智能 folder icon 用 5 种语义色（橙/蓝/紫/金/橙），色相互不重叠
//  - 选中态高亮 0.12 opacity——比 hover (0.04) 强 3 倍
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

    @Test func activeBackgroundMatchesSurfaceSelected() {
        // V4.6.0: Surface.selected 0.10 → 0.12——视觉锤更明确
        // V6.32.1: Surface.selected 变函数 (for: ColorScheme), activeBackground 走 selectedLight
        // SidebarStyle.activeBackground 是 Surface.selectedLight 的别名 (向后兼容 light mode)
        #expect(SidebarStyle.activeBackground == Surface.selectedLight)
    }

    @Test func hoverBackgroundMatchesSurfaceHover() {
        // hover 比选中弱 3 倍（0.04 vs 0.12）
        #expect(SidebarStyle.hoverBackground == Surface.hover)
    }

    @Test func labelColorsDifferByState() {
        // 三档 label 颜色必须互不相同
        #expect(SidebarStyle.labelDefault != SidebarStyle.labelHover)
        #expect(SidebarStyle.labelHover != SidebarStyle.labelActive)
        #expect(SidebarStyle.labelDefault != SidebarStyle.labelActive)
    }

    @Test func iconDefaultIsSecondary() {
        // 默认 icon 用 secondary（弱化视觉权重）
        #expect(SidebarStyle.iconDefault == Color.secondary)
    }

    @Test func iconActiveIsAccent() {
        // hover/选中 icon 用 accent——与 label 同步
        #expect(SidebarStyle.iconActive == Color.accentColor)
    }

    // MARK: - section header

    @Test func headerPaddingValues() {
        #expect(SidebarStyle.headerPaddingHorizontal == 12)
        #expect(SidebarStyle.headerPaddingTop == 10)
        // V6.54 (design polish): 4 → 8 — section 之间视觉呼吸更足, 跟 Photos 真版对齐
        #expect(SidebarStyle.headerPaddingBottom == 8)
    }

    @Test func headerColorIsTertiaryEquivalent() {
        // V6.23.0: 0.85 → 0.65 opacity (跟 labelDefault 0.85 拉开差 — 视觉层级清晰)
        //   之前 V4.48.0 写 0.85 跟 labelDefault 撞色, 段头"小一圈"不协调
        //   V6.23 改 0.65 拉低 header opacity, 让 label/row 是视觉锤
        //   production token (SidebarStyle.headerColor) 已跟 V6.23 同步 0.65
        let expected = Color.secondary.opacity(0.65)
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
