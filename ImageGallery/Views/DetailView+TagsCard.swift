//
//  DetailView+TagsCard.swift
//  ImageGallery
//
//  V6.97 P3-4: DetailView 拆分 — 标签卡片
//    之前 4️⃣ 标签卡 + removeTag + createAndAddTag 都在 DetailView.swift
//    拆出: tagsCard
//    (ratingPickerRow + removeTag + createAndAddTag 暂留 DetailView, 后续再拆)
//

import SwiftUI
import SwiftData

extension DetailView {
    /// 4️⃣ 标签卡
    var tagsCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(Copy.tagLabel)
                        .font(Typography.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        newTagName = ""
                        showingAddTagAlert = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(Typography.body)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    .help(Copy.addTag)
                }

                if photo.tags.isEmpty {
                    HStack {
                        Image(systemName: "tag")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                        Text(Copy.addTagHint)
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Spacing.xs)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(photo.tags) { tag in
                            TagChip(tag: tag) {
                                removeTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }
}
