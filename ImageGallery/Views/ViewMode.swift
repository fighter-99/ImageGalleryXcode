//
//  ViewMode.swift
//  ImageGallery
//
//  三种视图模式：网格 / 列表 / 时间线。
//

import SwiftUI

// MARK: - 枚举

enum ViewMode: String, CaseIterable, Identifiable {
    case grid
    case list
    case timeline

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .timeline: return "calendar"
        }
    }

    var label: String {
        switch self {
        case .grid: return "网格"
        case .list: return "列表"
        case .timeline: return "时间线"
        }
    }
}

// MARK: - 列表视图（V3.5.20 Photos.app 风格）

struct PhotoListView: View {
    let photos: [Photo]
    let selectedIDs: Set<UUID>
    let singleSelectedID: UUID?
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        // 不用 List，用 ScrollView + VStack 自定义（List 默认样式不符合 Photos.app 紧凑感）
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(photos) { photo in
                    PhotoListRow(
                        photo: photo,
                        isInMultiSelect: selectedIDs.contains(photo.id),
                        isActive: singleSelectedID == photo.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(photo) }
                    .onTapGesture(count: 2) { onDoubleTap(photo) }
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .background(Surface.canvas)
    }
}

// MARK: - 列表行（V3.5.20 Photos.app 紧凑风格）

struct PhotoListRow: View {
    let photo: Photo
    let isInMultiSelect: Bool
    let isActive: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // 缩略图（紧凑：44x44，比之前的 56 更小）
            ZStack(alignment: .topTrailing) {
                if let nsImage = ImageLoader.loadImage(at: photo.fileURL, maxPixelSize: 100) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Palette.cellEmpty)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Surface.cardBorder, lineWidth: 0.5)  // 微妙边框（V3.5.20）
            )
            .overlay {
                if isInMultiSelect {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(
                            Circle().fill(.background).padding(2)
                        )
                        .padding(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }

            // 文件名 + 收藏星标
            HStack(spacing: 4) {
                Text(photo.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(textColor)
                if photo.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Surface.favorite)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 尺寸（仅在有值时显示）
            if photo.width > 0 && photo.height > 0 {
                Text("\(photo.width) × \(photo.height)")
                    .font(Typography.captionMono)
                    .foregroundStyle(textColor.opacity(0.7))
                    .frame(width: 100, alignment: .trailing)
            }

            // 文件大小
            Text(formatFileSize(photo.fileSize))
                .font(Typography.captionMono)
                .foregroundStyle(textColor.opacity(0.7))
                .frame(width: 70, alignment: .trailing)

            // 导入时间
            Text(formatDate(photo.importedAt))
                .font(Typography.captionMono)
                .foregroundStyle(textColor.opacity(0.7))
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        // V3.6.31 撤销 V3.6.29: List 视图先不挂 .onDrag
        // 原因：DragPayload refactor 在用户环境导致 drag 失败（详见 PhotoGridView .onDrag 注释）
        // PhotoListRow 暂时只响应点击（单选/多选），拖出功能等 DragPayload 修复后重做
    }

    /// 行背景：选中 > 多选 > hover > 默认
    private var rowBackground: some View {
        Group {
            if isActive {
                Color.accentColor
            } else if isInMultiSelect {
                Surface.selected
            } else if isHovered {
                Surface.hover
            } else {
                Color.clear
            }
        }
    }

    /// 行文字颜色（选中时变白，否则 primary）
    private var textColor: Color {
        isActive ? .white : .primary
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - 时间线视图（V3.5.20 Photos.app 风格：年 → 月 二级分组）

struct PhotoTimelineView: View {
    let photos: [Photo]
    let selectedIDs: Set<UUID>
    let singleSelectedID: UUID?
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    /// 按"年 → 月"二级分组
    /// 结构：[(year: String, months: [(monthKey: String, monthDate: Date, photos: [Photo])])]
    private var groupedByYear: [(year: String, months: [(key: String, keyDate: Date, photos: [Photo])])] {
        // 第一步：按"年-月"分组
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"

        let byMonth = Dictionary(grouping: photos) { photo in
            monthFormatter.string(from: photo.importedAt)
        }
        let monthGroups: [(key: String, keyDate: Date, photos: [Photo])] = byMonth.compactMap { (key, photos) -> (String, Date, [Photo])? in
            guard let firstDate = photos.first?.importedAt else { return nil }
            return (key, firstDate, photos.sorted { $0.importedAt > $1.importedAt })
        }
        .sorted { $0.keyDate > $1.keyDate }

        // 第二步：按年聚合月组
        let byYear = Dictionary(grouping: monthGroups) { item in
            String(item.key.prefix(4))  // "2024-05" → "2024"
        }
        return byYear
            .map { (year, months) in
                (year: year, months: months.sorted { $0.keyDate > $1.keyDate })
            }
            .sorted { $0.year > $1.year }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xxl) {
                ForEach(groupedByYear, id: \.year) { yearGroup in
                    TimelineYearSection(
                        year: yearGroup.year,
                        months: yearGroup.months,
                        selectedIDs: selectedIDs,
                        singleSelectedID: singleSelectedID,
                        onTap: onTap,
                        onDoubleTap: onDoubleTap
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xl)
        }
        .background(Surface.canvas)
    }
}

// MARK: - 年 Section（V3.5.20 新增：Photos.app 风格的年分组）

struct TimelineYearSection: View {
    let year: String
    let months: [(key: String, keyDate: Date, photos: [Photo])]
    let selectedIDs: Set<UUID>
    let singleSelectedID: UUID?
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    private var totalCount: Int { months.reduce(0) { $0 + $1.photos.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // 年 header（大号 rounded 字体，Photos.app 风格）
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("\(year)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(totalCount) 张")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // 月份子 section
            ForEach(months, id: \.key) { month in
                TimelineMonthSection(
                    title: formatMonth(month.key),
                    photos: month.photos,
                    selectedIDs: selectedIDs,
                    singleSelectedID: singleSelectedID,
                    onTap: onTap,
                    onDoubleTap: onDoubleTap
                )
            }
        }
    }

    private func formatMonth(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return key }
        return "\(month) 月"
    }
}

// MARK: - 月 Section（V3.5.20 改：精简，去掉重复的年份）

struct TimelineMonthSection: View {
    let title: String
    let photos: [Photo]
    let selectedIDs: Set<UUID>
    let singleSelectedID: UUID?
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 月份 header（小一号字体 + secondary 色）
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(photos.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 缩略图 grid
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 60), spacing: Spacing.sm), count: 5),
                spacing: Spacing.sm
            ) {
                ForEach(photos) { photo in
                    TimelineThumbnail(
                        photo: photo,
                        isInMultiSelect: selectedIDs.contains(photo.id),
                        isActive: singleSelectedID == photo.id
                    )
                    .onTapGesture { onTap(photo) }
                    .onTapGesture(count: 2) { onDoubleTap(photo) }
                }
            }
        }
    }
}

// MARK: - TimelineThumbnail

struct TimelineThumbnail: View {
    let photo: Photo
    let isInMultiSelect: Bool
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = ImageLoader.loadImage(at: photo.fileURL, maxPixelSize: 400) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Palette.cellEmpty)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Surface.cardBorder, lineWidth: 0.5)  // V3.5.20：微妙边框
        )
        .overlay {
            if isInMultiSelect {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Surface.selectedStrong)
                Image(systemName: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(
                        Circle().fill(.background).padding(2)
                    )
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(
                    isActive ? Color.accentColor : Color.clear,
                    lineWidth: isActive ? 3 : 0
                )
        }
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(Animations.standard, value: isActive)
        // V3.6.31 撤销 V3.6.29: Timeline 视图先不挂 .onDrag（详见 PhotoGridView .onDrag 注释）
    }
}
