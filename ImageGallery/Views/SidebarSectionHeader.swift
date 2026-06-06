//
//  SidebarSectionHeader.swift
//  ImageGallery
//
//  V3.5.8 侧栏精修：自定义 section header。
//  Photos.app 风格：粗体 + secondary 色 + 小字号 + 上下 padding。
//

import SwiftUI

/// 侧栏 section header
/// V3.5.14 Photos.app 风格：small caps + tertiary 色 + 较小字号
/// - macOS 风格小写大字母（uppercase + caption2）
/// - tertiary 色（比 secondary 更淡）
/// - 上下 padding 留出视觉分组空间
struct SidebarSectionHeader: View {
    let title: String

    /// 支持 `SidebarSectionHeader("标题")` 写法
    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)  // ⭐ Photos.app 风格：small caps
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}
