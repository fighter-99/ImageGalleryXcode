//
//  PhotoRowView.swift
//  ImageGallery
//
//  V5.29: 单行 cell 渲染——从 PhotoGridView private struct MasonryRowView 提升
//    接收 GridRow (含 rowHeight + items) 替代原 itemIds + itemWidths + rowHeight
//    view 内用 PhotoGridItem.id 做 photos.first(where:) lookup——row 自包含
//
//  V5.16: masonry 单行渲染——HStack + 固定行高 + 变 cell 宽
//    - 行内 cell 高度统一 = rowHeight (行底部齐)
//    - cell 宽度 = item.width (GridLayout 算好的具体值, 含末行拉伸)
//    - 跨 cell 共享 selection/folders/tags 状态
//
//  V5.18: 加 showDateCaption——cell 下方显示拍摄日期 (Photos Days/Months 风格)
//    - 仅 date grouped 视图传入 true
//    - rowHeight < 100pt 时自动隐藏 (caption 20pt 会挤压 image)
//    - caption 用 inline DateFormatter——"5月12日" / "2024年5月12日"
//
//  V5.21: caption 预留高度 16 → 20pt (callout 14pt 字号调整必同步调预留高度)
//    镜像 V5.21 字号调整必同步调预留高度的契约
//

import SwiftUI

struct PhotoRowView: View {
    let row: GridRow
    let cellSpacing: CGFloat
    // V5.18: 日期 caption 开关——date grouped 传 true, 平铺传 false
    let showDateCaption: Bool
    let photos: [Photo]
    // V5.39.7: 排序模式 (透传到 PhotoThumbnailView, 决定是否启用 .dropDestination)
    //   必须放在 photos 之后, selection 之前——SwiftUI call site 顺序约束
    let sortOption: SortOption
    // V5.39.7: 重排回调 (PhotoThumbnailView reorder drop 后调, 触发 ContentView recomputePhotos)
    let onReorder: () -> Void
    let selection: SelectionState
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    let onDelete: (Photo) -> Void
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    /// V5.21: caption 预留高度从 16 → 20pt (callout 14pt 字号调整必同步调预留高度)
    private static let captionReservedHeight: CGFloat = 20

    /// V5.18: 最小 rowHeight 才显示 caption——rowHeight 太小时 caption 20pt 会挤压 image
    private static let minRowHeightForCaption: CGFloat = 100

    var body: some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(row.items) { item in
                if let photo = photos.first(where: { $0.id == item.id }) {
                    cellContent(photo: photo, width: item.width)
                }
            }
        }
        .frame(height: row.rowHeight, alignment: .top)
        // V5.39.1: HStack 加 .clipped()——即使 cell 内部 .clipped() 修了, HStack 这一层
        //   也兜底——cell 内容溢出 + HStack frame 不 clip 双重保险
        .clipped()
    }

    @ViewBuilder
    private func cellContent(photo: Photo, width: CGFloat) -> some View {
        // V5.18: caption 模式下 cell 是 VStack(image + caption), image 高度让出 caption
        let captionEnabled = showDateCaption && row.rowHeight >= Self.minRowHeightForCaption
        if captionEnabled {
            let imageHeight = row.rowHeight - Self.captionReservedHeight
            VStack(spacing: 2) {
                photoImage(photo: photo, width: width, height: imageHeight)
                Text(dateCaptionText(for: photo))
                    // V5.21: caption (12pt) → callout (14pt) — V5.19 反馈"12pt 仍看不到"
                    //   14pt callout 在 240pt 大 cell 上更明显, 但仍不抢主图
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            photoImage(photo: photo, width: width, height: row.rowHeight)
        }
    }

    /// V5.18: 单 cell 渲染——抽出来让 caption 模式/普通模式共用
    /// V5.39.7: 透传 sortOption + onReorder 到 PhotoThumbnailView (拖拽重排依赖)
    @ViewBuilder
    private func photoImage(photo: Photo, width: CGFloat, height: CGFloat) -> some View {
        PhotoThumbnailView(
            photo: photo,
            isInMultiSelect: selection.contains(photo.id),
            isActive: selection.singleSelectedID == photo.id,
            folders: folders,
            allTags: allTags,
            cellWidth: width,
            rowHeight: height,
            retentionDays: retentionDays,
            // V5.39.7: 透传排序模式 + 重排回调 (拖拽重排依赖)
            sortOption: sortOption,
            onReorder: onReorder,
            onDelete: { onDelete(photo) },
            onTap: { onTap(photo) },
            onDoubleTap: { onDoubleTap(photo) }
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.6).combined(with: .opacity)
        ))
    }

    /// V5.18: caption 文本——同年内 "M月d日" (5月12日), 跨年 "yyyy年M月d日"
    ///   Photos.app Days 视图 cell 下方格式——同月重复不冗余 (header 已说"5月")
    ///   跨年带年份——避免和 header "2024 年" 重复阅读歧义
    private func dateCaptionText(for photo: Photo) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let calendar = Calendar.current
        let photoYear = calendar.component(.year, from: photo.importedAt)
        let currentYear = calendar.component(.year, from: Date())
        if photoYear == currentYear {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: photo.importedAt)
    }
}
