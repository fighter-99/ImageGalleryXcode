//
//  DetailView+InfoCard.swift
//  ImageGallery
//
//  V6.97 P3-4: DetailView 拆分 — 信息卡片
//    之前 2️⃣ 信息卡 (文件名 + 元数据 grid) + formatDate/formatFileSize 都在 DetailView.swift
//    拆出: infoCard, infoRow, formatDate, formatFileSize
//

import SwiftUI
import SwiftData
import Foundation

extension DetailView {
    /// 2️⃣ 信息卡（文件名 + 元数据）
    var infoCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // 文件名（标题级 + 重命名按钮）
                // V4.5.0: 字号 .title3.semibold → .headline（13pt semibold，窄 panel 不换行）
                //         重命名按钮 .plain → .borderless（hover 出系统圆角灰底，可识别为按钮）
                HStack(spacing: Spacing.sm) {
                    HighlightedText(text: photo.filename, query: searchText)
                        .font(Typography.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        // V6.58 (audit P1.3): capture renameTarget = photo at alert-open
                        //   之前 `newFileName = photo.filename` 在 photo 切换时失同步:
                        //   按 ← → photo 变 B 但 newFileName 仍是 A 的名字 → 改错照片
                        renameTarget = photo
                        newFileName = photo.filename
                        showingRenameAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(Typography.body)
                    }
                    .buttonStyle(.borderless)
                    .help(Copy.renamePhotoTitle)
                    .fixedSize()  // 不被 Spacer 挤压
                }

                // macOS 原生 info 面板不用 Divider，用 spacing 自然分隔

                // 元数据 grid（2 列：图标 + 内容）
                // V6.52 (design polish): row spacing xs(4) → sm(8) — 之前 4pt 太挤, 字段读起来"挤在一起"
                //   + icon font caption(11pt) → caption2(9pt) — icon 二级化, 不抢字段值
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let folder = photo.folder {
                        infoRow(icon: "folder", text: folder.name)
                    }
                    if photo.width > 0 && photo.height > 0 {
                        let dim = "\(photo.width) × \(photo.height)"
                        infoRow(icon: "ruler", text: dim, mono: true)
                    }
                    infoRow(icon: "doc", text: formatFileSize(photo.fileSize), mono: true)
                    infoRow(icon: "calendar", text: formatDate(photo.importedAt), mono: true)
                }
            }
        }
    }

    /// 信息行（图标 + 文字）
    /// V6.52 (design polish): icon font caption(11pt) → caption2 — icon 二级化不抢字段值
    ///   字段值用 .primary (之前已对), 视觉层级 icon < value 更清晰
    func infoRow(icon: String, text: String, mono: Bool = false) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            if mono {
                Text(text)
                    .font(Typography.captionMono)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(Typography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
