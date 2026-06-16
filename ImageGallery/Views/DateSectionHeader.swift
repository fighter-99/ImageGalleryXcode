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
//  V5.21: count 颜色 secondary → primary + 字重 medium (深背景上对比度)
//    - 之前 count "637 张图片" 在深背景下偏淡，截图 29 几乎看不清
//    - 仍比 label 字号小 (callout vs system 24pt)——不抢 label 视觉权重
//
//  V5.56: Key Photo——段头左侧加代表图缩略图 (80x80, 加载 latest non-trashed photo from group)
//    - 镜像 Photos.app 真版: 段头左侧 1 张小图, 标识该日期组
//    - 代表图 selection: ContentViewModel.representativePhoto(for: DateGroup) (按 importedAt 最新非 trashed)
//
//  设计要点：
//  - 标题 24pt bold + primary 色，Photos.app 段落视觉权重
//  - 计数 callout primary medium 右侧（V5.21 加深——深背景可见性）
//  - 顶 16pt 底 4pt padding，让段头与上一段照片明显分隔
//  - 整行可点击（toggle 该日期段的"详情/隐藏"——V4.37.0 暂不实现，仅占位）
//

import SwiftUI

struct DateSectionHeader: View {
    let label: String
    let count: Int
    // V5.56: Key Photo 代表图 (optional——空时 fallback text-only header)
    let representative: Photo?

    /// V5.56 简版 init——保持向后兼容 (没 representative 时不显示缩略图)
    init(label: String, count: Int) {
        self.label = label
        self.count = count
        self.representative = nil
    }

    /// V5.56 主 init——传 representative photo
    init(label: String, count: Int, representative: Photo?) {
        self.label = label
        self.count = count
        self.representative = representative
    }

    @State private var loadedImage: NSImage?
    @State private var loadFailed: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            // V5.56: 代表图缩略图 (左侧 32x32 + 6pt corner radius)
            if let photo = representative {
                Group {
                    if let img = loadedImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if loadFailed {
                        // 加载失败: 灰底占位
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(width: 32, height: 32)
                    } else {
                        // 加载中: 简单灰底占位 (V5.56)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(width: 32, height: 32)
                    }
                }
                .task(id: photo.id) {
                    loadFailed = false
                    loadedImage = nil
                    let img = await ImageLoader.loadImageAsync(
                        at: photo.fileURL,
                        maxPixelSize: 80  // V5.56: 32pt × 2.5x retina = 80px
                    )
                    if img == nil {
                        loadFailed = true
                    } else {
                        loadedImage = img
                    }
                }
            }
            Text(label)
                // V5.18: title3 semibold → system 24pt bold（对齐 Photos.app "Today" 视觉权重）
                // V5.27: 24pt bold → 15pt medium——macOS Photos Library 节奏
                // V5.31: 15pt medium → 13pt regular——更 sutil (Photos Days 视图段头实际 ~13pt)
                //   24pt 切碎 grid, 15pt 仍偏'重', 13pt regular 是 Photos 真版
                .font(Typography.dateCaption)
                .foregroundStyle(.primary)
            Spacer()
            // V5.21: count "637 张图片" 颜色 secondary → primary + 字重 medium
            //   之前 secondary 在深背景上偏淡，截图 29 几乎看不清
            //   仍 callout 字号（比 label 15pt 小）——不抢 label 视觉权重
            Text(Copy.dateSectionCount(count))
                .font(Typography.body.weight(.medium))
                .foregroundStyle(.primary)
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
    let photo = Photo(
        filename: "key.jpg",
        fileURL: URL(fileURLWithPath: "/tmp/V556_key.jpg"),
        fileSize: 1000,
        width: 100,
        height: 100
    )
    return VStack(alignment: .leading, spacing: 0) {
        DateSectionHeader(label: "今天", count: 12, representative: photo)
        DateSectionHeader(label: "昨天", count: 8)
        DateSectionHeader(label: "本周", count: 47, representative: photo)
        DateSectionHeader(label: "本月", count: 128)
        DateSectionHeader(label: "5 月", count: 64, representative: photo)
        DateSectionHeader(label: "2024 年", count: 250)
    }
    .padding(.horizontal)
    .frame(width: 600)
}
