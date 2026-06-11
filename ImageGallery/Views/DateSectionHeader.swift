//
//  DateSectionHeader.swift
//  ImageGallery
//
//  V4.37.0: 日期分组表头（Photos.app 风格）
//    主 grid 按 importedAt 分段：今天 / 昨天 / 本周 / 本月 / X 月 / X 年
//    段头不吸顶（让照片流连续），只做视觉分组标记
//
//  设计要点：
//  - 标题字号 .title3.weight(.semibold)，与 sidebar section header 区分
//    (sidebar header 是 .caption.small caps，这里是 .title3 normal case)
//  - 右侧显示照片数（caption + secondary 色）——Photos.app 风格
//  - 顶/底 padding 适中，避免段头与照片粘连
//  - 整行可点击（toggle 该日期段的"详情/隐藏"——V4.37.0 暂不实现，仅占位）
//

import SwiftUI

struct DateSectionHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(count) 张")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)  // 段头与上方照片分隔
        .background(.red)  // DEBUG: 看是否渲染
        // 注意: 不设 .padding(.bottom)——段头与下方 grid 自然接续
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        DateSectionHeader(label: "今天", count: 12)
        DateSectionHeader(label: "昨天", count: 8)
        DateSectionHeader(label: "本周", count: 47)
        DateSectionHeader(label: "本月", count: 128)
        DateSectionHeader(label: "5 月", count: 64)
        DateSectionHeader(label: "2024 年", count: 250)
    }
    .padding()
    .frame(width: 600)
}
