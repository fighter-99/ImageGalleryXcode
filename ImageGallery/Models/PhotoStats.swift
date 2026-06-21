//
//  PhotoStats.swift
//  ImageGallery
//
//  V3.6.1：Photo 集合的统计纯函数。
//  设计为 enum + static func 而非 class/init：
//  - 无状态、无依赖 → 单元测试零成本
//  - 调用方 `PhotoStats.trashed(allPhotos)` 比 `PhotoStats().trashed(allPhotos)` 更轻
//  - 避免 `extension Collection where Element == Photo` 的链式 filter 多次中间数组分配
//

import Foundation

/// V3.6.1：Photo 集合的统计纯函数集合。
/// 所有方法都是 nonisolated static func，可在任何 actor 上调（包括测试）。
enum PhotoStats {

    // MARK: - 过滤

    /// 回收站中的照片（trashedAt != nil）
    static func trashed(_ photos: [Photo]) -> [Photo] {
        photos.filter(\.isInTrash)
    }

    /// 图库中的照片（trashedAt == nil）
    static func inLibrary(_ photos: [Photo]) -> [Photo] {
        photos.filter { !$0.isInTrash }
    }

    // V5.8: 砍 favorites()——V5.7 砍 .favorites 侧边栏后无 caller
    //   "收藏" 现在 = 评分 ≥ 5，由 FilterState.minRating 处理（不走 PhotoStats.favorites）

    /// 待整理照片（在图库 + folder == nil）
    static func unfiled(_ photos: [Photo]) -> [Photo] {
        photos.filter { $0.folder == nil && !$0.isInTrash }
    }

    // MARK: - V6.13.4: 智能文件夹计数 (SidebarView 用)
    ///   之前 SidebarView "最近 7 天" / "大图（>5MB）" 2 个 item 没 count (其它 5 个有)
    ///   补 2 个纯函数 helper, 跟 inLibraryCount(folder:) 一致
    ///   filter 范围: 排除 trash, 大图阈值 5_000_000 跟 PhotoStats.filtered filterLargeFiles 一致
    static func recent7DaysCount(_ photos: [Photo]) -> Int {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return photos.filter { !$0.isInTrash && $0.importedAt > cutoff }.count
    }
    static func largeFilesCount(_ photos: [Photo]) -> Int {
        photos.filter { !$0.isInTrash && $0.fileSize > 5_000_000 }.count
    }

    // MARK: - 聚合

    /// 所有照片总占用字节数
    static func totalSize(_ photos: [Photo]) -> Int64 {
        photos.reduce(0) { $0 + $1.fileSize }
    }

    /// 回收站照片总占用字节数
    static func trashedSize(_ photos: [Photo]) -> Int64 {
        trashed(photos).reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - 重复图分组（V3.6.15 清理工具用）

    /// 按 fileHash 分组，每组 ≥ 2 张为重复组
    /// - 返回：[[Photo]]，每组内按 importedAt 降序（最新优先）
    /// - fileHash == nil 的照片跳过（无法判断重复）
    static func duplicateGroups(in photos: [Photo]) -> [[Photo]] {
        let groups = Dictionary(grouping: photos) { $0.fileHash }
        return groups
            .compactMap { (hash, photos) -> [Photo]? in
                guard hash != nil, photos.count >= 2 else { return nil }
                return photos.sorted { $0.importedAt > $1.importedAt }
            }
            .sorted { $0.count > $1.count }  // 重复多的组排前面
    }

    /// 每组保留 importedAt 最新的，其他返回（待清理候选）
    static func duplicatesToPurge(in photos: [Photo]) -> [Photo] {
        duplicateGroups(in: photos)
            .flatMap { $0.dropFirst() }  // 每组跳过最新的（[0]）
    }

    // MARK: - 关系对象上的 count

    /// 文件夹下"图库"照片数（排除 trashed 的）
    /// V3.6.4 修复：之前 folder.photos.count 包括 trashed 的，跟 grid 实际显示数不一致
    static func inLibraryCount(_ folder: Folder) -> Int {
        folder.photos.lazy.filter { !$0.isInTrash }.count
    }

    /// 标签下"图库"照片数（排除 trashed 的）
    /// V3.6.4 修复：同上，tag.photos.count 也包括 trashed 的
    static func inLibraryCount(_ tag: ImageGallery.Tag) -> Int {
        tag.photos.lazy.filter { !$0.isInTrash }.count
    }

    // MARK: - 剩余天数（V3.6.6 Trash UX 增强）

    /// 计算距离永久删除还剩多少天
    /// - Parameters:
    ///   - trashedAt: 进入回收站的时间（nil = 未在回收站）
    ///   - retentionDays: 保留时长（来自 @AppStorage）
    ///   - now: 当前时间（默认 Date()，测试可注入）
    /// - Returns: 剩余天数，nil = 未在回收站
    ///   - 0 = 即将过期（< 1 天）
    ///   - 负数 = 已过期（> retentionDays 天未清理）
    static func daysUntilPurge(
        trashedAt: Date?,
        retentionDays: Int,
        now: Date = Date()
    ) -> Int? {
        guard let trashedAt = trashedAt else { return nil }
        let elapsed = now.timeIntervalSince(trashedAt)
        let total = Double(retentionDays) * 86400
        let remaining = total - elapsed
        return Int(remaining / 86400)
    }

    // MARK: - 综合筛选（V4.36.6：Grid/List/Timeline 三视图共用）

    /// V4.36.6: 抽 PhotoGridView.recomputePhotos 逻辑到 static helper
    ///   旧版逻辑在 PhotoGridView 内联——List/Timeline 视图无法复用, 切换视图模式不生效
    ///   新版 3 视图 (grid/list/timeline) 都通过此函数计算 visiblePhotos
    ///   11 个参数覆盖 sidebar 全部 filter inputs + searchText + sortOption
    ///   V4.36.x: 加 4 个工具栏筛选 popover 维度（folder multi / tag multi / shape / rating）
    static func filtered(
        _ photos: [Photo],
        folder: Folder?,
        tag: Tag?,
        searchText: String,
        sortOption: SortOption,
        // V5.8: 砍 filterFavorites 参数——V5.7 砍 .favorites 侧边栏后 dead
        filterUnfiled: Bool,
        filterDuplicates: Bool,
        filterRecent7Days: Bool,
        filterLargeFiles: Bool,
        filterInTrash: Bool,
        // V4.36.x: 工具栏筛选按钮 4 维（空集短路；维度内 OR；维度间 AND）
        selectedFolderIDs: Set<UUID> = [],
        selectedTagIDs: Set<UUID> = [],
        selectedShapes: Set<PhotoShape> = [],
        minRating: Int = 0,
        // P4.1.1: 智能文件夹 filter — 跟工具栏 4 维同 pattern
        smartFolderFilter: FilterState? = nil
    ) -> [Photo] {
        var result = photos

        if let folder {
            result = result.filter { $0.folder?.id == folder.id }
        }
        if let tag {
            result = result.filter { photo in photo.tags.contains { $0.id == tag.id } }
        }
        // V5.8: 砍 filterFavorites 分支——dead
        if filterUnfiled {
            // V6.11: 加 !isInTrash——sidebar '待整理' 视图不该出现已 trash 照片
            //   PhotoStats.unfiled 纯函数 (L35) 已正确排除 trash, PhotoStats.filtered 此处不一致
            //   之前: trash 1 张无 folder 的照片 → '待整理' 仍显示, 跟 sidebar 数字对不上
            result = result.filter { $0.folder == nil && !$0.isInTrash }
        }
        if filterDuplicates {
            // V6.12: 用 result 而非 photos 算 hashCounts——sidebar 数字 跟 视图数字 一致
            //   V6.11 C6+C7 教训: PhotoStats 纯函数 跟 PhotoStats.filtered 语义对齐
            //   之前用 photos (input) 算 hashCounts 会让 hash 数包含上游已过滤掉的照片
            //   → 视图显示 0 但 sidebar (也用 photos 全集) 显示 N, 不一致
            let hashCounts = Dictionary(grouping: result) { $0.fileHash }.mapValues { $0.count }
            result = result.filter { photo in
                guard let hash = photo.fileHash else { return false }
                return (hashCounts[hash] ?? 0) > 1
            }
        }
        // V2: 最近 7 天
        if filterRecent7Days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            result = result.filter { $0.importedAt > cutoff }
        }
        // V2: 大图 > 5MB
        if filterLargeFiles {
            result = result.filter { $0.fileSize > 5_000_000 }
        }
        // V3.6: 回收站筛选
        if filterInTrash {
            result = result.filter { $0.trashedAt != nil }
        } else {
            // 非回收站视图：永远排除已删项
            result = result.filter { $0.trashedAt == nil }
        }
        // V4.36.x: 工具栏筛选按钮 4 维（AND 串联；空集短路）
        if !selectedFolderIDs.isEmpty { result = folderFilter(result, ids: selectedFolderIDs) }
        if !selectedTagIDs.isEmpty { result = tagFilter(result, ids: selectedTagIDs) }
        if !selectedShapes.isEmpty { result = shapeFilter(result, shapes: selectedShapes) }
        if minRating > 0 { result = ratingFilter(result, minRating: minRating) }
        // P4.1.1: 智能文件夹 filter — 跟工具栏 4 维同 pattern (复用 helper, 维度间 AND)
        //   smart folder filter 是 sidebarSelection 强制的, 跟 toolbar filter 独立 AND 应用
        //   nil = no smart folder active; .empty (isActive=false) = 跳过 no-op
        if let sff = smartFolderFilter, sff.isActive {
            if !sff.folders.isEmpty { result = folderFilter(result, ids: sff.folders) }
            if !sff.tags.isEmpty { result = tagFilter(result, ids: sff.tags) }
            if !sff.shapes.isEmpty { result = shapeFilter(result, shapes: sff.shapes) }
            if sff.minRating > 0 { result = ratingFilter(result, minRating: sff.minRating) }
        }
        // V3.6.3: 用 PhotoSearch 纯函数（含 folder.name 匹配）
        result = PhotoSearch.filter(result, query: searchText)
        // 排序
        return sortOption.apply(to: result)
    }

    // MARK: - P4.1.1: 智能文件夹 sidebar count helper
    /// 算 smart folder 命中的 photo 数 (sidebar row 显示用)
    /// V6.59 (audit P2.1): 改 lazy.filter.count, 之前 filtered(...) 跑完整 pipeline + sort + 1000-元素数组 alloc
    ///   之前: 20 smart folders × 5000 photos = 100,000 ops/sidebar render
    ///   现在: lazy.count 不 alloc 中间数组, 不排序, 仅应用 smart folder 4 维 filter
    ///   4 个维度都 short-circuit (empty 时跳过), 大部分 sidebar render 不需要 full filter
    static func smartFolderCount(_ photos: [Photo], smartFolderFilter: FilterState) -> Int {
        // smartFolderFilter.empty (默认) → 所有 photo 命中, count == photos.count, O(n)
        guard smartFolderFilter.isActive else { return photos.count }
        return photos.lazy.filter { matchesSmartFolderFilter($0, filter: smartFolderFilter) }.count
    }

    /// V6.59: 单 photo 命中 smart folder filter 判定 (smartFolderCount 用)
    ///   跟 filtered() 的 smart folder 分支 (L196-201) 语义一致, 但抽出供 lazy 用
    ///   不应用其他维度 (folder/tag/searchText 等) — smart folder 仅这 4 维
    private static func matchesSmartFolderFilter(_ photo: Photo, filter: FilterState) -> Bool {
        // V6.59: !photo.isInTrash — smart folder 永远排除已删照片 (跟 toolbar filter 一致)
        guard !photo.isInTrash else { return false }
        // V6.59: 4 维 AND, 各自短 (empty 不调 helper)
        if !filter.folders.isEmpty {
            guard let fid = photo.folder?.id else { return false }
            guard filter.folders.contains(fid) else { return false }
        }
        if !filter.tags.isEmpty {
            guard photo.tags.contains(where: { filter.tags.contains($0.id) }) else { return false }
        }
        if !filter.shapes.isEmpty {
            // V6.59: Photo 没有 stored shape 字段, 派生自 width/height (跟 shapeFilter 一致)
            guard filter.shapes.contains(PhotoShape.from(width: photo.width, height: photo.height)) else { return false }
        }
        if filter.minRating > 0 {
            guard photo.rating >= filter.minRating else { return false }
        }
        return true
    }

    // MARK: - 4 个纯函数 helper（V4.36.x：工具栏筛选按钮的可独立单测单元）

    /// 文件夹多选：photo.folder.id 在 ids 集合内即过
    /// folder == nil 的照片不在任何 folder id 集合内 → 自动排除
    static func folderFilter(_ photos: [Photo], ids: Set<UUID>) -> [Photo] {
        photos.filter { photo in
            guard let fid = photo.folder?.id else { return false }
            return ids.contains(fid)
        }
    }

    /// 标签多选：photo 含任一 ids 内的 tag 即过（OR 语义）
    /// 无 tag 的照片不命中任何 tag id → 自动排除
    static func tagFilter(_ photos: [Photo], ids: Set<UUID>) -> [Photo] {
        photos.filter { photo in
            photo.tags.contains { ids.contains($0.id) }
        }
    }

    /// 形状多选：photo 形状在 shapes 集合内即过
    /// 形状从 width/height 派生（PhotoShape.from；等号归 square）
    static func shapeFilter(_ photos: [Photo], shapes: Set<PhotoShape>) -> [Photo] {
        photos.filter { photo in
            shapes.contains(PhotoShape.from(width: photo.width, height: photo.height))
        }
    }

    /// 评分筛选：photo.rating >= minRating 即过（"≥N 星"语义）
    /// 边界：等于 minRating 也算过
    static func ratingFilter(_ photos: [Photo], minRating: Int) -> [Photo] {
        photos.filter { $0.rating >= minRating }
    }

    // MARK: - 日期分组（V4.37.0：Photos.app 风格日期分段表头）

    /// V4.37.0: Photos.app 风格日期分组——按 importedAt 5+1 个 bucket
    ///   今天 / 昨天 / 本周 / 本月 / X 月 / X 年
    ///   bucket 选择优先级（先匹配先返回）：
    ///     1. 今天 (isDateInToday)
    ///     2. 昨天 (isDateInYesterday)
    ///     3. 本周 (date > now - 7days)
    ///     4. 本月 (same month as now)
    ///     5. X 月 (same year as now, different month)
    ///     6. X 年 (different year)
    ///   同 bucket 内按 importedAt 降序（最新照片在前）
    ///   返回按 sortKey 降序（最新 group 在前）
    static func groupByDate(_ photos: [Photo], now: Date = Date(), calendar: Calendar = .current) -> [DateGroup] {
        var groups: [String: [Photo]] = [:]
        var order: [String: (label: String, sortKey: Date)] = [:]

        for photo in photos {
            let date = photo.importedAt
            let (key, label, sortKey) = bucketKey(for: date, now: now, calendar: calendar)
            groups[key, default: []].append(photo)
            if order[key] == nil {
                order[key] = (label, sortKey)
            }
        }

        return groups
            .map { (key, photos) -> DateGroup in
                let info = order[key]!
                return DateGroup(
                    id: key,
                    label: info.label,
                    sortKey: info.sortKey,
                    photos: photos.sorted { $0.importedAt > $1.importedAt }
                )
            }
            .sorted { $0.sortKey > $1.sortKey }
    }

    /// V4.37.0: 单张照片的 bucket 判定 — V6.37.1 label 走 Copy 让 zh-Hant/en 翻译
    private static func bucketKey(for date: Date, now: Date, calendar: Calendar) -> (key: String, label: String, sortKey: Date) {
        if calendar.isDateInToday(date) {
            return ("today", Copy.dateSectionToday, now)
        }
        if calendar.isDateInYesterday(date) {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return ("yesterday", Copy.dateSectionYesterday, yesterday)
        }
        // 本周（7 天内但不是今天/昨天）
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date > weekAgo {
            return ("thisWeek", Copy.dateSectionThisWeek, date)
        }
        // 本月（同月但不在 7 天内）
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return ("thisMonth", Copy.dateSectionThisMonth, date)
        }
        // 当前年内其他月
        let year = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)
        if year == currentYear {
            let month = calendar.component(.month, from: date)
            return ("\(year)-\(month)", Copy.dateSectionMonthLabel(month), date)
        }
        // 往年
        return ("\(year)", Copy.dateSectionYearLabel(year), date)
    }
}

/// V4.37.0: 日期分组（Photos.app 风格分段表头）
struct DateGroup: Identifiable {
    let id: String          // 唯一 key (e.g. "today" / "2024-05")
    let label: String       // 显示标签 (e.g. "今天" / "5 月" / "2024 年")
    let sortKey: Date       // 排序键（最新组在前）
    let photos: [Photo]     // 该日期分组的照片（按 importedAt 降序）
}
