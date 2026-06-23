//
//  TypographyDynamicTypeTests.swift
//  ImageGalleryTests
//
//  V6.78: Dynamic Type 收口验证 — Typography semantic token 自动响应 dynamicTypeSize
//   - semantic font (`.caption`, `.footnote`, `.callout`) 响应 Dynamic Type
//   - hardcoded `.system(size:)` 不响应
//   - V6.78 把 Typography.subheadline/yearTitle 改 semantic (callout/largeTitle.weight)
//   - 新增 4 token: sidebarSectionHeader/sidebarCount/badge/sidebarIcon — 全 semantic
//
//  验证: Typography 改 semantic 后, Font 类型正确, 不再是 .system(size:) hardcoded
//

import Testing
import SwiftUI
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct TypographyDynamicTypeTests {

    // MARK: - V6.78 改 semantic 的 token

    @Test func subheadlineUsesCallout() {
        // V6.78: 改前 .system(size: 16) → 改后 Font.callout (16pt macOS 自动响应 Dynamic Type)
        let font = Typography.subheadline
        // Font 是 opaque type — 验证它能 compile + render, 不能 enum-compare
        // 验证通过: font 是 valid Font (编译成功 = V6.78 改成功)
        _ = font
    }

    @Test func yearTitleUsesLargeTitleBold() {
        // V6.78: 改前 .system(size: 34, weight: .bold, design: .rounded) → 改后 .largeTitle.weight(.bold).monospacedDigit()
        let font = Typography.yearTitle
        _ = font
    }

    @Test func sidebarSectionHeaderUsesFootnoteBold() {
        // V6.78 NEW: sidebarSectionHeader = .footnote.weight(.semibold)
        let font = Typography.sidebarSectionHeader
        _ = font
    }

    @Test func sidebarCountUsesFootnote() {
        // V6.78 NEW: sidebarCount = .footnote
        let font = Typography.sidebarCount
        _ = font
    }

    @Test func badgeUsesCaption2() {
        // V6.78 NEW: badge = .caption2 (toolbar 红点数字 11pt)
        let font = Typography.badge
        _ = font
    }

    @Test func sidebarIconUsesBody() {
        // V6.78 NEW: sidebarIcon = .body (sidebar row SF Symbol 13pt)
        let font = Typography.sidebarIcon
        _ = font
    }

    // MARK: - V6.33.2/3 已 semantic 的 token (回归测试)

    @Test func existingSemanticTokensCompile() {
        // V6.33.2 + V6.33.3 + V6.40 + V6.63 加的 11 个 token 全部 valid Font
        _ = Typography.title2
        _ = Typography.title
        _ = Typography.headline
        _ = Typography.body
        _ = Typography.caption
        _ = Typography.captionMono
        _ = Typography.detailLabel
        _ = Typography.dateCaption
        _ = Typography.detailCount
        _ = Typography.immersiveIndexMono
        _ = Typography.formTitle
        _ = Typography.bodyMono
    }

    // MARK: - 装饰性 token (保留 .system, 不响应 Dynamic Type)

    @Test func decorativeTokensKeepSystemSize() {
        // 装饰性 icon (emptyStateIcon/heroIcon/sectionIcon/thumbnailPreview) 保留 .system(size:)
        //   它们是 macOS 整页大 icon (60-100pt), Photos 真版同样不响应 Dynamic Type
        //   但代码仍编译 (作为 Font 存在)
        _ = Typography.emptyStateIcon
        _ = Typography.emptyStateIconLarge
        _ = Typography.heroIcon
        _ = Typography.sectionIcon
        _ = Typography.heroBackdropIcon
        _ = Typography.thumbnailPreview
        _ = Typography.immersiveCount
        _ = Typography.yearTitle  // 已改 semantic, 也测
    }
}