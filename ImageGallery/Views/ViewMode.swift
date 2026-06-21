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
        case .grid: return Copy.layoutModeSquareFit
        case .list: return Copy.layoutModeList
        case .timeline: return Copy.viewModeTimeline
        }
    }
}

// MARK: - 列表视图（V3.5.20 Photos.app 风格）

struct PhotoListView: View {
    let photos: [Photo]
    // V3.6.52: 2 let (selectedIDs/singleSelectedID) 合并为 1 SelectionState
    let selection: SelectionState
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        // 不用 List，用 ScrollView + VStack 自定义（List 默认样式不符合 Photos.app 紧凑感）
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(photos) { photo in
                    PhotoListRow(
                        photo: photo,
                        isInMultiSelect: selection.contains(photo.id),
                        isActive: selection.singleSelectedID == photo.id
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
    // V4.38.0: 异步缩略图加载——避免列表快速滚动时 100px 缩略图主线程解码
    //   仿 PhotoGridView cell 模式（V3.6.26 沉淀，V4.4.0 加 loadFailed 区分）
    //   44x44 小尺寸——不引入 Shimmer 复杂度，加载中/失败同 fallback
    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    var body: some View {
        // V3.6.34: 同样 capture @Model 属性到 local（详见 PhotoGridView 同名注释）
        let capturedFileURL = photo.fileURL
        return HStack(spacing: Spacing.md) {
            // 缩略图（紧凑：44x44，比之前的 56 更小）
            ZStack(alignment: .topTrailing) {
                if let nsImage = loadedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Palette.cellEmpty)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .font(Typography.body)
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
                        .font(Typography.body)
                        .foregroundStyle(.white, Color.accentColor)
                        .background(
                            Circle().fill(.background).padding(Spacing.xxs)
                        )
                        .padding(Spacing.xxs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }

            // 文件名
            // V5.7: 砍收藏星标——收藏 = 评分 ≥ 5，列表行只显示文件名
            HStack(spacing: 4) {
                Text(photo.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 尺寸（仅在有值时显示）
            if photo.width > 0 && photo.height > 0 {
                Text(Copy.imageDimensions(width: photo.width, height: photo.height))
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
        // V3.6.33: List 视图也支持拖出到 Finder / 侧栏
        // V3.6.34: 同样 capture @Model 属性到 local（详见 PhotoGridView 同名注释）
        .draggable(capturedFileURL)
        // V4.38.0: 异步缩略图加载——photo.id 变化时自动取消旧 task
        //   maxPixelSize 100（44x44 cell 足够）
        .task(id: photo.id) {
            loadFailed = false
            let img = await ImageLoader.loadImageAsync(
                at: photo.fileURL,
                maxPixelSize: 100
            )
            if img == nil {
                loadFailed = true
            } else {
                loadedImage = img
            }
        }
    }

    /// 行背景：选中 > 多选 > hover > 默认
    /// V6.32.1: 多选态用 Surface.selectedStrong — 暗色下 opacity 从 0.16 → 0.22 增强对比
    @Environment(\.colorScheme) private var scheme

    private var rowBackground: some View {
        Group {
            if isActive {
                Color.accentColor
            } else if isInMultiSelect {
                Surface.selectedStrong(for: scheme)
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
    // V3.6.52: 2 let (selectedIDs/singleSelectedID) 合并为 1 SelectionState
    let selection: SelectionState
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
                        selection: selection,
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
    // V3.6.52: 2 let → 1 SelectionState
    let selection: SelectionState
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    private var totalCount: Int { months.reduce(0) { $0 + $1.photos.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // 年 header（大号 rounded 字体，Photos.app 风格）
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(Copy.yearLabel(year))
                    .font(Typography.yearTitle)
                Text(Copy.totalCount(totalCount))
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }

            // 月份子 section
            ForEach(months, id: \.key) { month in
                TimelineMonthSection(
                    title: formatMonth(month.key),
                    photos: month.photos,
                    selection: selection,
                    onTap: onTap,
                    onDoubleTap: onDoubleTap
                )
            }
        }
    }

    private func formatMonth(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return key }
        return Copy.dateSectionMonthLabel(month)
    }
}

// MARK: - 月 Section（V3.5.20 改：精简，去掉重复的年份）

struct TimelineMonthSection: View {
    let title: String
    let photos: [Photo]
    // V3.6.52: 2 let → 1 SelectionState
    let selection: SelectionState
    let onTap: (Photo) -> Void
    let onDoubleTap: (Photo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 月份 header（小一号字体 + secondary 色）
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Typography.headline.weight(.semibold))
                Spacer()
                Text(Copy.totalCount(photos.count))
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
                        isInMultiSelect: selection.contains(photo.id),
                        isActive: selection.singleSelectedID == photo.id
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
    @Environment(\.colorScheme) private var scheme

    let photo: Photo
    let isInMultiSelect: Bool
    let isActive: Bool

    // V4.38.0: 异步缩略图加载——timeline 滚动时 400px 缩略图主线程解码会卡
    //   仿 PhotoGridView cell 模式（V3.6.26 + V4.4.0 loadFailed 区分）
    //   timeline cell 约 60-120pt——不引入 Shimmer 复杂度，加载中/失败同 fallback
    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    var body: some View {
        // V3.6.34: 同样 capture @Model 属性到 local（详见 PhotoGridView 同名注释）
        let capturedFileURL = photo.fileURL
        return ZStack(alignment: .topTrailing) {
            if let nsImage = loadedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Palette.cellEmpty)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .font(Typography.body)
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
                let strong = Surface.selectedStrong(for: scheme)
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(strong)
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.body)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(
                        Circle().fill(.background).padding(Spacing.xxs)
                    )
                    .padding(Spacing.xxs)
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
        // V3.6.33: Timeline 视图也支持拖出到 Finder / 侧栏
        // V3.6.34: 同样 capture @Model 属性到 local（详见 PhotoGridView 同名注释）
        .draggable(capturedFileURL)
        // V4.38.0: 异步缩略图加载——photo.id 变化时自动取消旧 task
        //   maxPixelSize 400（timeline cell 足够，最大约 120pt 显示）
        .task(id: photo.id) {
            loadFailed = false
            let img = await ImageLoader.loadImageAsync(
                at: photo.fileURL,
                maxPixelSize: 400
            )
            if img == nil {
                loadFailed = true
            } else {
                loadedImage = img
            }
        }
    }
}
