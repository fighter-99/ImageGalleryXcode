//
//  DateSectionHeader.swift
//  ImageGallery
//
//  V4.37.0: 日期分组表头（Photos.app 风格）
//    主 grid 按 importedAt 分段：今天 / 昨天 / 本周 / 本月 / X 月 / X 年
//    段头不吸顶（让照片流连续），只做视觉分组标记
//
//  V5.18: 视觉对齐 Photos.app 真版
//    - 标题字号 .title3 semibold → system 24pt bold（Photos "Today" 头视觉权重）
//    - 删 .background(.red) DEBUG 残留
//    - 顶 padding Spacing.sm → Spacing.lg（段间更舒展，与 Photos 一致）
//    - 计数右侧继续保留（ImageGallery 增强；Photos 无 count）
//
//  设计要点：
//  - 标题 24pt bold + primary 色，Photos.app 段落视觉权重
//  - 计数 callout secondary 右侧——PhotoGallery 增强（用户一眼能看段内数量）
//  - 顶 16pt 底 4pt padding，让段头与上一段照片明显分隔
//  - 整行可点击（toggle 该日期段的"详情/隐藏"——V4.37.0 暂不实现，仅占位）
//

import SwiftUI

struct DateSectionHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                // V5.18: title3 semibold → system 24pt bold（对齐 Photos.app "Today" 视觉权重）
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            // V5.18: count 移到右侧 + secondary 色（避免和 label 抢权重）
            Text("\(count) 张")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // V5.18: 顶 padding Spacing.sm → Spacing.lg (16pt)，段间舒展
        .padding(.top, Spacing.lg)
        // V5.18: 加 4pt 底 padding，让段头与下方照片之间留 4pt 微隙
        //   （之前无底 padding，段头紧贴 grid——Photos 实际有微隙）
        .padding(.bottom, Spacing.xs)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        DateSectionHeader(label: "今天", count: 12)
        DateSectionHeader(label: "昨天", count: 8)
        DateSectionHeader(label: "本周", count: 47)
        DateSectionHeader(label: "本月", count: 128)
        DateSectionHeader(label: "5 月", count: 64)
        DateSectionHeader(label: "2024 年", count: 250)
    }
    .padding(.horizontal)
    .frame(width: 600)
}
