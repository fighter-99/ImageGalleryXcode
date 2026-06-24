//
//  SidebarSection.swift
//  ImageGallery
//
//  V6.103: SidebarView 696 LOC 拆 SidebarSection — 5 section 通用化
//    之前 SidebarView.sidebarContent 内 5 段 DisclosureGroup 重复 header style:
//      Text(title).font(Typography.sidebarSectionHeader)
//        .textCase(.uppercase).tracking(0.8)
//        .padding(.top, SidebarStyle.sectionHeaderTopPadding)
//        .padding(.bottom, SidebarStyle.sectionHeaderBottomPadding)
//    5 段重复 ~9 行 × 5 = 45 行重复 code
//
//    现在 1 个 SidebarSection 通用 view — 接受 title + isExpanded binding + content closure
//    V6.95 A 真版 header (uppercase + tracking 0.8) + V6.96 P4 上下间距 集中
//
//  设计目标:
//   - SidebarView.sidebarContent 5 段全部用 SidebarSection(title:isExpanded:) { content }
//   - DisclosureGroup 行为不变 (Photos 真版 sidebar 折叠)
//   - section header 视觉 0 变化 (snapshot byte match)
//

import SwiftUI

/// V6.103: SidebarView 5 section 通用化 — DisclosureGroup + 真版 section header
///   V6.95 A: uppercase + tracking 0.8 (Photos Sonoma+ 真版 sidebar 风格)
///   V6.96 P4: section header 上下间距 (section 视觉分组)
struct SidebarSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            Text(title)
                .font(Typography.sidebarSectionHeader)
                // V6.95 A: uppercase + tracking 0.8 — Photos 真版 sidebar section header 风格
                .textCase(.uppercase)
                .tracking(0.8)
                // V6.96 P4: section header 上下间距 — section 视觉分组更明显
                //   顶部 6pt 让 section header 跟上一个 section 的最后 row 分层
                //   底部 2pt 让 section header 跟本 section 第一个 row 紧凑
                .padding(.top, SidebarStyle.sectionHeaderTopPadding)
                .padding(.bottom, SidebarStyle.sectionHeaderBottomPadding)
        }
    }
}

/// V6.103: SidebarView 5 section 简化 wrapper — 跟 sidebarRow 配套, 简化 caller
///   SidebarSection 默认用 Section wrapper (跟 V6.97 P2-3 smart folder 路径一致)
struct SidebarPlainSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                content()
            } label: {
                Text(title)
                    .font(Typography.sidebarSectionHeader)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.top, SidebarStyle.sectionHeaderTopPadding)
                    .padding(.bottom, SidebarStyle.sectionHeaderBottomPadding)
            }
        }
    }
}