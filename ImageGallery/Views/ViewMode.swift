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
    let searchText: String
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
                        isActive: selection.singleSelectedID == photo.id,
                        searchText: searchText
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
    let searchText: String

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
                HighlightedText(text: photo.filename, query: searchText)
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
    // V6.114: 透传 grid layout 参 — timeline 复用 masonryRowsView 同样的 layout engine
    //   之前 timeline 走自己的 LazyVGrid 硬编码 5 列 + 1:1 square, 跟 grid 完全不一致
    //   现在跟 grid 共用 SquareLayout.cellSize + GridLayout.computeRows + PhotoGridLayoutView
    let thumbnailSize: CGFloat
    let layoutMode: ThumbnailLayoutMode
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    // V6.114: 跟 PhotoGridLayoutView 一致 — onRotate (Photo, clockwise) -> Void
    //   之前我设计的 onRotateLeft/Right 是错的, PhotoGridLayoutView 只收单个 onRotate
    let onRotate: (Photo, Bool) -> Void
    let onMarkup: () -> Void
    let onCrop: (Photo) -> Void

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
                        onDoubleTap: onDoubleTap,
                        // V6.114: 透传 grid layout 参 — timeline 复用 grid masonry engine
                        thumbnailSize: thumbnailSize,
                        layoutMode: layoutMode,
                        folders: folders,
                        allTags: allTags,
                        retentionDays: retentionDays,
                        onRotate: onRotate,
                        onMarkup: onMarkup,
                        onCrop: onCrop
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
    // V6.114: 透传 grid layout 参给 month section
    let thumbnailSize: CGFloat
    let layoutMode: ThumbnailLayoutMode
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    let onRotate: (Photo, Bool) -> Void
    let onMarkup: () -> Void
    let onCrop: (Photo) -> Void

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
                    onDoubleTap: onDoubleTap,
                    thumbnailSize: thumbnailSize,
                    layoutMode: layoutMode,
                    folders: folders,
                    allTags: allTags,
                    retentionDays: retentionDays,
                    onRotate: onRotate,
                    onMarkup: onMarkup,
                    onCrop: onCrop
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
    // V6.114: grid layout 参 — 跟 PhotoGridView.masonryRowsView 完全一致
    let thumbnailSize: CGFloat
    let layoutMode: ThumbnailLayoutMode
    let folders: [Folder]
    let allTags: [Tag]
    let retentionDays: Int
    let onRotate: (Photo, Bool) -> Void
    let onMarkup: () -> Void
    let onCrop: (Photo) -> Void

    // V6.114: 跟 PhotoGridView.swift:309-326 同样的常量
    //   gridHorizontalPadding = 16 (外边距, 由 ScrollView .padding 提供)
    //   rowSpacing = 6, cellSpacing = 6
    private static let rowSpacing: CGFloat = 6
    private static let cellSpacing: CGFloat = 6

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

            // V6.114: 用 GridLayout + PhotoGridLayoutView 替 LazyVGrid 硬编码 5 列
            //   跟 grid 模式完全一致: 缩略图大小由 thumbnailSize slider 驱动
            //   cellSize = SquareLayout.cellSize (填满可用宽度)
            //   rows = GridLayout.computeRows (justified masonry packing)
            //   GeometryReader 必须 (rows 需要 availableWidth 算 cellSize)
            GeometryReader { geo in
                let availableWidth = geo.size.width
                let actualRowHeight = SquareLayout.cellSize(
                    availableWidth: availableWidth,
                    rowHeight: thumbnailSize,
                    cellSpacing: Self.cellSpacing
                )
                let layout = GridLayout(
                    availableWidth: availableWidth,
                    rowHeight: actualRowHeight,
                    cellSpacing: Self.cellSpacing,
                    layoutMode: layoutMode
                )
                let rows = layout.computeRows(from: photos)
                PhotoGridLayoutView(
                    rows: rows,
                    rowSpacing: Self.rowSpacing,
                    cellSpacing: Self.cellSpacing,
                    showDateCaption: false,  // timeline 不需要 date caption (date 在 header 里)
                    photos: photos,
                    sortOption: .importedAtDesc,  // timeline 永远按 importedAt 排, 不需要 reorder
                    onReorder: {},  // timeline 不支持 drag-reorder (跟原 LazyVGrid 行为一致)
                    layoutMode: layoutMode,
                    selection: selection,
                    folders: folders,
                    allTags: allTags,
                    retentionDays: retentionDays,
                    onTap: onTap,
                    onDoubleTap: onDoubleTap,
                    onRotate: onRotate,  // 旋转按钮 timeline 不展示, 但 PhotoCellContent 需要回调
                    onMarkup: onMarkup,
                    onCrop: onCrop,
                    isSingle: selection.singleSelectedID != nil && !selection.isMultiSelect
                )
            }
            .frame(height: timelineHeight(thumbnailSize: thumbnailSize))
        }
    }

    // V6.114: 估算 frame height — rows 数 × cellSize + row spacings
    //   SwiftUI ScrollView 嵌套 GeometryReader 不传 height 会让 cell 缩到 0
    //   best-effort 估算: 用 thumbnailSize 当 cellSize, columns = availableWidth / cellSize
    //   timeline scroll container 默认 ≈ 800pt - 220pt sidebar - 32pt toolbar ≈ 548pt
    //   按 200pt thumbnailSize 算 ≈ 2.74 cols, 用 3 cols 保守估
    //   更精确: 让 cell 用 maxWidth: .infinity 让 row 自己撑
    private func timelineHeight(thumbnailSize: CGFloat) -> CGFloat {
        let cellSize = thumbnailSize
        let estimatedAvailableWidth = max(400, cellSize * 3)  // 至少 3 列, fallback 400pt
        let columns = max(1, Int(estimatedAvailableWidth / cellSize))
        let rowCount = max(1, Int(ceil(Double(photos.count) / Double(columns))))
        return CGFloat(rowCount) * cellSize + CGFloat(max(0, rowCount - 1)) * Self.rowSpacing
    }
}

// V6.114: TimelineThumbnail 删除 — timeline 复用 PhotoGridLayoutView + PhotoCellContent
//   之前 80 行 stripped-down cell (image + border + active stroke + checkmark)
//   现在直接走 PhotoGridLayoutView → PhotoRowView → PhotoThumbnailView → PhotoCellContent (335 行 rich)
//   0 重复代码, 0 行为差异 (badge/rating/hover/drag-drop 全部跟 grid 一致)
