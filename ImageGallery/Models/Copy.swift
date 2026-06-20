//
//  Copy.swift
//  ImageGallery
//
//  V5.50-2 + V5.50-3 + V5.50-4: 微文案字典 (microcopy dictionary)——所有用户可见字符串统一来源
//
//  4 条原则 (V5.44 设计):
//    1. 动词开头 + 主语宾语明确
//    2. 3 段式错误
//    3. 数字带量词
//    4. 空态带引导
//
//  未来 i18n 时直接换成 NSLocalizedString (V5.52 String Catalog 准备)
//

import Foundation

/// V5.50-2 + V5.50-3 + V5.50-4: 微文案字典——所有用户可见字符串统一来源
enum Copy {
    // MARK: - 动作结果
    static func imported(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "imported", defaultValue: "已导入 %lld 张图片"), count) }
    static func importedPartial(inserted: Int, failed: Int) -> String { String.localizedStringWithFormat(String(localized: "importedPartial", defaultValue: "已导入 %lld 张，%lld 张失败"), inserted, failed) }
    static func exported(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "exported", defaultValue: "已导出 %lld 张图片"), count) }
    static func movedToRecycleBin(_ count: Int, retentionDays: Int) -> String { String.localizedStringWithFormat(String(localized: "movedToRecycleBin", defaultValue: "已移到回收站（%lld 天后永久删除）"), count, retentionDays) }
    static func movedDuplicates(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "movedDuplicates", defaultValue: "已移到回收站 %lld 张重复图"), count) }
    static func recycledBinEmptied(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "recycledBinEmptied", defaultValue: "已清空回收站（%lld 张）"), count) }
    static func copiedToPasteboard(_ count: Int) -> String {
        count == 1 ? "已复制 1 张图片" : "已复制 \(count) 张图片"
    }

    // MARK: - 错误 (3 段式)
    static let storageError = String(localized: "storageError", defaultValue: "无法保存图片到图库。请检查磁盘空间，或在「系统设置 → 隐私与安全 → 完整磁盘访问权限」中授权 ImageGallery，然后重试。")
    static func importFailed(_ filename: String) -> String { String.localizedStringWithFormat(String(localized: "importFailed", defaultValue: "导入失败：%@"), filename) }
    static func exportFailed(_ filename: String) -> String { String.localizedStringWithFormat(String(localized: "exportFailed", defaultValue: "导出失败：%@"), filename) }
    static func moveToRecycleBinFailed(_ error: String) -> String { String.localizedStringWithFormat(String(localized: "moveToRecycleBinFailed", defaultValue: "移到回收站失败：%@"), error) }
    static func emptyRecycleBinFailed(_ error: String) -> String { String.localizedStringWithFormat(String(localized: "emptyRecycleBinFailed", defaultValue: "清空回收站失败：%@"), error) }
    static func batchMoveToRecycleBinFailed(_ error: String) -> String { String.localizedStringWithFormat(String(localized: "batchMoveToRecycleBinFailed", defaultValue: "批量移到回收站失败：%@"), error) }
    static let batchRatingFailed = String(localized: "batchRatingFailed", defaultValue: "批量评分失败")
    static func recycleBinOperationFailed(_ error: String) -> String { String.localizedStringWithFormat(String(localized: "recycleBinOperationFailed", defaultValue: "回收站操作失败：%@"), error) }

    // MARK: - 空态 (含引导)
    static let emptyLibrary = String(localized: "emptyLibrary", defaultValue: "图库还是空的")
    static let emptyLibraryHint = String(localized: "emptyLibraryHint", defaultValue: "把图片拖到这里，或点击 ⌘O 导入")
    static let emptyRecycleBin = String(localized: "emptyRecycleBin", defaultValue: "回收站是空的")
    static let selectAPhoto = String(localized: "selectAPhoto", defaultValue: "选择一张图片")
    static let selectAPhotoHint = String(localized: "selectAPhotoHint", defaultValue: "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选")
    static let thumbnailLoadFailed = String(localized: "thumbnailLoadFailed", defaultValue: "加载失败")

    // MARK: - 详情面板
    static func photoPosition(current: Int, total: Int) -> String { String.localizedStringWithFormat(String(localized: "photoPosition", defaultValue: "%lld / %lld"), current, total) }
    static func photoPosition1Indexed(current: Int, total: Int) -> String { String.localizedStringWithFormat(String(localized: "photoPosition1Indexed", defaultValue: "%lld / %lld"), current, total) }
    static func imageDimensions(width: Int, height: Int) -> String { String.localizedStringWithFormat(String(localized: "imageDimensions", defaultValue: "%lld × %lld"), width, height) }
    static let renameHint = String(localized: "renameHint", defaultValue: "给图片一个新名字（不包含扩展名）")
    static let tagLabel = String(localized: "tagLabel", defaultValue: "标签")
    static let addTagHint = String(localized: "addTagHint", defaultValue: "点击 + 添加标签")
    static let deletePhotoConfirm = String(localized: "deletePhotoConfirm", defaultValue: "图片将从图库中移除，文件也会被永久删除。")
    static let emptyRecycleBinConfirm = String(localized: "emptyRecycleBinConfirm", defaultValue: "回收站里的所有照片将被永久删除，无法恢复。")
    // V6.09: confirmationDialog title 入库——之前 ContentView+BatchDialogs:58 hardcoded
    static let emptyRecycleBinConfirmTitle = String(localized: "emptyRecycleBinConfirmTitle", defaultValue: "确定要清空回收站吗？")
    static func recycleBinCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "recycleBinCount", defaultValue: "回收站有 %lld 张"), count) }

    // MARK: - 状态栏
    static func totalCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "totalCount", defaultValue: "%lld 张"), count) }
    static func selectedCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "selectedCount", defaultValue: "已选 %lld 张"), count) }
    static let statusSeparator = String(localized: "statusSeparator", defaultValue: "·")
    static func daysRemaining(_ days: Int) -> String { String.localizedStringWithFormat(String(localized: "daysRemaining", defaultValue: "%lld"), days) }

    // MARK: - 设置面板
    static let viewModeGrid = String(localized: "viewModeGrid", defaultValue: "网格")
    static let viewModeList = String(localized: "viewModeList", defaultValue: "列表")
    static let viewModeTimeline = String(localized: "viewModeTimeline", defaultValue: "时间线")
    static let recycleBinSubtitle = String(localized: "recycleBinSubtitle", defaultValue: "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。")
    static func thumbnailSizeLabel(_ size: Int) -> String { String.localizedStringWithFormat(String(localized: "thumbnailSizeLabel", defaultValue: "%lld"), size) }

    // MARK: - 侧栏 / 按钮
    static let newFolder = String(localized: "newFolder", defaultValue: "新建文件夹")
    static let newTag = String(localized: "newTag", defaultValue: "新建标签")
    static let folderNamePlaceholder = String(localized: "folderNamePlaceholder", defaultValue: "文件夹名称")
    static let cancel = String(localized: "cancel", defaultValue: "取消")
    static let create = String(localized: "create", defaultValue: "创建")
    static let confirm = String(localized: "confirm", defaultValue: "确定")
    static let delete = String(localized: "delete", defaultValue: "删除")

    // MARK: - V6.14.3: 侧栏 label i18n 化
    //   之前 SidebarView 12 个 hardcoded 中文 ("全部"/"待整理"/"重复图"/"最近 7 天" 等)
    //   走 String(localized:defaultValue:) xcstrings 模式
    //   未来 zh-Hant 真翻译 (V6.15) 只需 xcstrings 加翻译, 代码不动
    // 智能文件夹 row label
    static let sidebarAll = String(localized: "sidebarAll", defaultValue: "全部")
    static let sidebarUnfiled = String(localized: "sidebarUnfiled", defaultValue: "待整理")
    static let sidebarDuplicates = String(localized: "sidebarDuplicates", defaultValue: "重复图")
    static let sidebarRecent7Days = String(localized: "sidebarRecent7Days", defaultValue: "最近 7 天")
    static let sidebarLargeFiles = String(localized: "sidebarLargeFiles", defaultValue: "大图（>5MB）")
    static let sidebarRecentlyDeleted = String(localized: "sidebarRecentlyDeleted", defaultValue: "回收站")
    // section header
    static let sidebarSectionLibrary = String(localized: "sidebarSectionLibrary", defaultValue: "我的图馆")
    // V6.23 (Bug fix): 智能文件夹独立 section — 之前跟"我的图馆"合并, "+" 在 Library header 语义错位
    //   Photos.app 范式: Smart Albums 独立 section, 跟 Library 平级; Folders/Tags 也是独立 section
    static let sidebarSectionSmartFolders = String(localized: "sidebarSectionSmartFolders", defaultValue: "智能文件夹")
    static let sidebarSectionFolders = String(localized: "sidebarSectionFolders", defaultValue: "我的文件夹")
    static let sidebarSectionTags = String(localized: "sidebarSectionTags", defaultValue: "标签")
    static let sidebarSectionRecycleBin = String(localized: "sidebarSectionRecycleBin", defaultValue: "最近删除")
    // 标签 section 空态
    static let emptyNoTags = String(localized: "emptyNoTags", defaultValue: "还没有标签")
    static let emptyNoTagsHint = String(localized: "emptyNoTagsHint", defaultValue: "新建一个标签，给照片打上分类标记")

    // MARK: - 筛选
    static let clearAllFilters = String(localized: "clearAllFilters", defaultValue: "清除全部")

    // MARK: - 拖拽导入
    static let dropReleaseToImport = String(localized: "dropReleaseToImport", defaultValue: "松开导入")
    static let dropSupportedTypes = String(localized: "dropSupportedTypes", defaultValue: "支持图片文件 / 文件夹")

    // MARK: - Confirm 对话框 (V5.50-4 补充)
    static func deletePhotosConfirm(retentionDays: Int) -> String { String.localizedStringWithFormat(String(localized: "deletePhotosConfirm", defaultValue: "选中的图片会移到回收站，%lld 天后自动永久清除。可在回收站中恢复。"), retentionDays) }
    static let newFolderPrompt = String(localized: "newFolderPrompt", defaultValue: "为新文件夹命名")
    static let newFolderHint = String(localized: "newFolderHint", defaultValue: "选\"跳过\"避免重复导入。")

    // MARK: - 重复图清理 (V5.50-4 补充)
    static func duplicatesFoundGroups(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "duplicatesFoundGroups", defaultValue: "发现 %lld 组重复"), count) }
    static func duplicatesCleanable(_ count: Int, size: String) -> String { String.localizedStringWithFormat(String(localized: "duplicatesCleanable", defaultValue: "可清理 %lld 张 · %@"), count, size) }
    static let duplicatesNone = String(localized: "duplicatesNone", defaultValue: "暂无重复图")
    static func duplicatesExplanation(retentionDays: Int) -> String { String.localizedStringWithFormat(String(localized: "duplicatesExplanation", defaultValue: "每组保留导入时间最近的一张，其他移到回收站（%lld 天后自动永久清除）"), retentionDays) }

    // MARK: - 上下文菜单 (V5.50-4 补充)
    static let clearRating = String(localized: "clearRating", defaultValue: "清除评分")

    // MARK: - 计数 / 辅助 (V5.50-4 补充)
    static func photoCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "photoCount", defaultValue: "%lld"), count) }
    static func yearLabel(_ year: String) -> String { year }
    static func daysBadge(_ days: Int) -> String { String.localizedStringWithFormat(String(localized: "daysBadge", defaultValue: "%lld"), days) }
    static func sidebarCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "sidebarCount", defaultValue: "%lld"), count) }
    static func dateSectionCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "dateSectionCount", defaultValue: "%lld 张"), count) }
    static func autoDeleteAfterDays(_ days: Int) -> String { String.localizedStringWithFormat(String(localized: "autoDeleteAfterDays", defaultValue: "%lld 天后自动永久清除"), days) }

    // MARK: - V6.22.2 (P2 #8): VoiceOver / a11y 标签
    static let accessibilitySelected = String(localized: "accessibilitySelected", defaultValue: "已选中")
    static let accessibilityUnselected = String(localized: "accessibilityUnselected", defaultValue: "未选中")
    static func accessibilityPhotoLabel(_ filename: String, rating: Int, selected: Bool) -> String {
        let ratingText = rating > 0 ? "，\(rating) 星" : ""
        let stateText = selected ? "，已选中" : ""
        return "\(filename)\(ratingText)\(stateText)"
    }

    // MARK: - 视图模式 (V5.50-4 扩展——菜单用全名，区别于设置面板的 "网格" 简称)
    static let viewModeGridFull = String(localized: "viewModeGridFull", defaultValue: "缩略图视图")
    static let viewModeListFull = String(localized: "viewModeListFull", defaultValue: "列表视图")
    static let viewModeTimelineFull = String(localized: "viewModeTimelineFull", defaultValue: "时间线视图")

    // MARK: - 应用菜单 (V5.50-4 扩展)
    static let quickLook = String(localized: "quickLook", defaultValue: "快速查看")
    static let previousPhoto = String(localized: "previousPhoto", defaultValue: "上一张")
    static let nextPhoto = String(localized: "nextPhoto", defaultValue: "下一张")
    static let clearMenu = String(localized: "clearMenu", defaultValue: "清空菜单")
    static let noRecentFiles = String(localized: "noRecentFiles", defaultValue: "无最近文件")
    static func recentFile(index: Int, filename: String) -> String { String.localizedStringWithFormat(String(localized: "recentFile", defaultValue: "%lld. %@"), index, filename) }

    // MARK: - Confirm 按钮 (V5.50-4 扩展)
    static let empty = String(localized: "empty", defaultValue: "清空")
    static let skipAll = String(localized: "skipAll", defaultValue: "全部跳过（保留现有）")
    static let importAll = String(localized: "importAll", defaultValue: "全部导入（可能重复）")
    static let deleteConfirmTitle = String(localized: "deleteConfirmTitle", defaultValue: "确定要删除这张图片吗？")
    // V6.09: alert title 入库——之前 DetailView:126 hardcoded
    static let renamePhotoTitle = String(localized: "renamePhotoTitle", defaultValue: "重命名")

    // MARK: - 输入框 (V5.50-4 扩展)
    static let tagNamePlaceholder = String(localized: "tagNamePlaceholder", defaultValue: "标签名称")
    // V6.11: DetailView:127 新文件名 placeholder 入库
    static let newFileNamePlaceholder = String(localized: "newFileNamePlaceholder", defaultValue: "新文件名")
    // V6.11: DetailView:395 .help 文案入库
    static let addTag = String(localized: "addTag", defaultValue: "添加标签")

    // MARK: - 排序 (V5.50-5 扩展)
    /// 7 个 label (含方向箭头) —— SortOption.label
    static let sortImportedDesc = String(localized: "sortImportedDesc", defaultValue: "导入时间 ↓")
    static let sortImportedAsc = String(localized: "sortImportedAsc", defaultValue: "导入时间 ↑")
    static let sortFilenameAsc = String(localized: "sortFilenameAsc", defaultValue: "文件名 A → Z")
    static let sortFilenameDesc = String(localized: "sortFilenameDesc", defaultValue: "文件名 Z → A")
    static let sortFileSizeDesc = String(localized: "sortFileSizeDesc", defaultValue: "文件大小 ↓")
    static let sortFileSizeAsc = String(localized: "sortFileSizeAsc", defaultValue: "文件大小 ↑")
    static let sortCustomOrder = String(localized: "sortCustomOrder", defaultValue: "自定义顺序")
    /// 4 个 shortLabel (工具栏按钮短名) —— SortOption.shortLabel
    static let sortCategoryImportTime = String(localized: "sortCategoryImportTime", defaultValue: "导入时间")
    static let sortCategoryFilename = String(localized: "sortCategoryFilename", defaultValue: "文件名")
    static let sortCategoryFileSize = String(localized: "sortCategoryFileSize", defaultValue: "文件大小")
    static let sortCategoryCustom = String(localized: "sortCategoryCustom", defaultValue: "自定义")

    // MARK: - View 菜单 / UndoRedo (V5.50-6 扩展)
    /// File > Open Recent 子菜单标题
    static let openRecent = String(localized: "openRecent", defaultValue: "最近打开")
    /// View 菜单 Toggle
    static let showSidebar = String(localized: "showSidebar", defaultValue: "显示侧边栏")
    static let showDetailPanel = String(localized: "showDetailPanel", defaultValue: "显示详情面板")
    static let showInfoPanel = String(localized: "showInfoPanel", defaultValue: "显示信息面板")
    /// Edit 菜单 Undo/Redo (无 action 描述时)
    static let undo = String(localized: "undo", defaultValue: "撤销")
    static let redo = String(localized: "redo", defaultValue: "重做")
    /// Edit 菜单 Undo/Redo (有 action 描述时——"撤销 <desc>")
    static func undoWithAction(_ action: String) -> String { String.localizedStringWithFormat(String(localized: "undoWithAction", defaultValue: "撤销 %@"), action) }
    static func redoWithAction(_ action: String) -> String { String.localizedStringWithFormat(String(localized: "redoWithAction", defaultValue: "重做 %@"), action) }

    // MARK: - 工具栏 (V5.50-7 扩展)
    /// NSToolbar accessibility label + tooltip (与 Copy.quickLook / Copy.delete 共用)
    static let toolbarToggleSidebar = String(localized: "toolbarToggleSidebar", defaultValue: "切换侧边栏")
    static let toolbarExport = String(localized: "toolbarExport", defaultValue: "导出")
    static let toolbarImport = String(localized: "toolbarImport", defaultValue: "导入")
    // V6.24 (P0 #3): 工具栏快捷键提示 — hover 时显示 "导入 (⌘O)" 风格, 跟 Photos.app 范式一致
    //   之前 tooltip 只显示按钮名, 不显示快捷键, Power user 永远记不得快捷键, 新用户不知道有快捷键
    //   现在所有 toolbar item 走统一 helper: tooltip = "label\n(快捷键)"
    static let toolbarShortcutImport = "⌘O"
    static let toolbarShortcutDelete = "⌘⌫"
    static let toolbarShortcutQuickLook = "⌘Y"
    static let toolbarShortcutToggleSidebar = "⌃⌘S"
    static let layoutMode = String(localized: "layoutMode", defaultValue: "布局模式")
    static let thumbnailSize = String(localized: "thumbnailSize", defaultValue: "缩略图大小")
    static let sort = String(localized: "sort", defaultValue: "排序")
    static let filter = String(localized: "filter", defaultValue: "筛选")
    /// NSToolbar 搜索 (NSSearchToolbarItem)
    static let search = String(localized: "search", defaultValue: "搜索")
    static let searchHint = String(localized: "searchHint", defaultValue: "搜索照片、标签、笔记")
    static let searchPlaceholder = String(localized: "searchPlaceholder", defaultValue: "搜索照片、标签…")
    /// 筛选 badge——"筛选 (3)" 表示激活 3 个筛选条件
    static func filterWithCount(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "filterWithCount", defaultValue: "筛选 (%lld)"), count) }

    // MARK: - 上下文菜单 / 详情面板 (V5.50-8 扩展)
    /// 移动 / 文件夹 / 标签
    static let removeFromFolder = String(localized: "removeFromFolder", defaultValue: "移出文件夹")
    static let moveToFolder = String(localized: "moveToFolder", defaultValue: "移动到文件夹")
    static let manageTags = String(localized: "manageTags", defaultValue: "管理标签")
    static let addTagAction = String(localized: "addTagAction", defaultValue: "加标签")
    static let deleteTag = String(localized: "deleteTag", defaultValue: "删除标签")
    static let deleteFolder = String(localized: "deleteFolder", defaultValue: "删除文件夹")
    /// 通用 action label
    static let copyAction = String(localized: "copyAction", defaultValue: "复制")
    static let revealInFinder = String(localized: "revealInFinder", defaultValue: "在 Finder 中显示")
    /// 评分——分组标题
    static let ratingCategory = String(localized: "ratingCategory", defaultValue: "评分")
    /// 评分——"N 星" 标签
    static func ratingStars(_ n: Int) -> String { String.localizedStringWithFormat(String(localized: "ratingStars", defaultValue: "%lld 星"), n) }
    /// 多选 / 回收站 / 重复图
    static let cancelMultiSelect = String(localized: "cancelMultiSelect", defaultValue: "取消多选 (Esc)")
    static let restoreSelected = String(localized: "restoreSelected", defaultValue: "恢复选中")
    static let permanentlyDeleteSelected = String(localized: "permanentlyDeleteSelected", defaultValue: "永久删除选中")
    /// "清空回收站"——区别于 Copy.empty = "清空" (按钮短名)
    static let emptyRecycleBinAction = String(localized: "emptyRecycleBinAction", defaultValue: "清空回收站")
    static let keepNewestPerGroup = String(localized: "keepNewestPerGroup", defaultValue: "保留每组最新")
    // MARK: - V6.08: 详情面板错误 toast
    /// 文件重命名失败 (DetailView.renamePhoto 磁盘 moveItem 失败)
    static func renameFailed(_ filename: String) -> String { String.localizedStringWithFormat(String(localized: "renameFailed", defaultValue: "重命名失败：%@"), filename) }

    // MARK: - P4.2: 批量重命名
    /// File 菜单项 + mini toolbar 按钮共用
    static let batchRenameTitle = String(localized: "batchRenameTitle", defaultValue: "批量重命名")
    /// Sheet 模板输入框 placeholder
    static let batchRenameTemplatePlaceholder = String(localized: "batchRenameTemplatePlaceholder", defaultValue: "photo_{n:3}")
    /// Sheet 标题 — "重命名 N 张照片" (printf 插值, 见 [[swift-stringlocalized-pitfalls]])
    static func batchRenameSheetTitle(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "batchRenameSheetTitle", defaultValue: "重命名 %lld 张照片"), count) }
    /// Sheet preview 尾巴 — "等 N 个" (前 3 张之外的提示)
    static func batchRenamePreviewSuffix(_ count: Int) -> String { String.localizedStringWithFormat(String(localized: "batchRenamePreviewSuffix", defaultValue: "等 %lld 个"), count) }
    /// Sheet 模板语法提示
    static let batchRenameTokenHint = String(localized: "batchRenameTokenHint", defaultValue: "可用占位符：{n} 序列号 · {n:N} 零填充 · {originalName} 原文件名")
    /// Apply 按钮
    static let apply = String(localized: "apply", defaultValue: "应用")

    // MARK: - P4.1.1: 智能文件夹
    /// Sheet 标题
    static let smartFolderSheetTitle = String(localized: "smartFolderSheetTitle", defaultValue: "新建智能文件夹")
    /// Name 字段 placeholder
    static let smartFolderNamePlaceholder = String(localized: "smartFolderNamePlaceholder", defaultValue: "智能文件夹名")
    /// Section: 图标
    static let smartFolderIconSection = String(localized: "smartFolderIconSection", defaultValue: "图标")
    /// Section: 筛选条件 (跟 V6.14.3 printf 插值, 见 [[swift-stringlocalized-pitfalls]])
    static let smartFolderFilterSection = String(localized: "smartFolderFilterSection", defaultValue: "筛选条件")
    static let smartFolderEmptyFilterHint = String(localized: "smartFolderEmptyFilterHint", defaultValue: "当前工具栏无筛选条件 (智能文件夹将匹配全部图库照片)")
    /// currentViewTitle fallback (smart folder 已删, 但 sidebarSelection 还在)
    static let smartFolderFallback = String(localized: "smartFolderFallback", defaultValue: "智能文件夹")

    // MARK: - V6.08: PhotoGridEmptyState 文案 (整个文件 hardcoded → Copy 字典)
    /// CTA 主/次按钮
    static let clearSearch = String(localized: "clearSearch", defaultValue: "清除搜索")
    /// 跟 toolbarImport("导入") 区别——空状态 CTA 是完整短语
    static let importAction = String(localized: "importAction", defaultValue: "导入图片")
    // V6.21.4 (audit fix #7): 删 hardcoded "(⌘O)" — 应该由 caller 拼接 (避免 i18n 风险)
    //   主 CTA label 现在用 "\(Copy.importAction) (⌘O)" 在 PhotoGridEmptyState 拼接
    // V6.21.4 (audit fix #6): 删 dragPhotosHere — 副 CTA "拖入图片" 死按钮改回 visual hint
    //   hintStartImport 已经有 "拖入图片，或点击'导入图片'开始添加" 文案
    static let viewAll = String(localized: "viewAll", defaultValue: "查看全部")
    // V6.11: ActiveFiltersBar fallback 文案入库 (folderName 查不到 / tagName 查不到时)
    static let unknownFolder = String(localized: "unknownFolder", defaultValue: "未知文件夹")
    static let unknownTag = String(localized: "unknownTag", defaultValue: "未知标签")
    // V6.12: ActiveFiltersBar '≥ N 星' 旁路 (Q14)
    static func minRatingStars(_ n: Int) -> String { String.localizedStringWithFormat(String(localized: "minRatingStars", defaultValue: "≥ %lld 星"), n) }
    // V6.12: StatusBar 'X 项筛选' 旁路 (Q7)
    static func activeFilterBadge(_ n: Int) -> String { String.localizedStringWithFormat(String(localized: "activeFilterBadge", defaultValue: "%lld 项筛选"), n) }
    // V6.12: StatusBar thumbnailSizeLabel 4 档旁路 (Q7)
    static let thumbnailSizeCompact = String(localized: "thumbnailSizeCompact", defaultValue: "特小 70pt")
    static let thumbnailSizeSmall = String(localized: "thumbnailSizeSmall", defaultValue: "小 110pt")
    static let thumbnailSizeMedium = String(localized: "thumbnailSizeMedium", defaultValue: "中 200pt")
    static let thumbnailSizeLarge = String(localized: "thumbnailSizeLarge", defaultValue: "大 250pt")
    // V6.12: DetailPane 存储错误 (Q9)
    static let storageUnavailableTitle = String(localized: "storageUnavailableTitle", defaultValue: "存储不可用")
    static let storageRetry = String(localized: "storageRetry", defaultValue: "重试")
    // V6.12: TrashDetailView help tooltip (Q10)
    static let emptyRecycleBinHelp = String(localized: "emptyRecycleBinHelp", defaultValue: "永久删除回收站里所有照片（无法恢复）")
    /// 空状态标题——按 empty 场景分类
    static let emptyNoMatchFilter = String(localized: "emptyNoMatchFilter", defaultValue: "没有匹配筛选的图片")
    static let emptyNoMatchSearch = String(localized: "emptyNoMatchSearch", defaultValue: "没有匹配的图片")
    static let emptyUnfiled = String(localized: "emptyUnfiled", defaultValue: "没有待整理的图片")
    static let emptyFolder = String(localized: "emptyFolder", defaultValue: "这个文件夹是空的")
    static let emptyTag = String(localized: "emptyTag", defaultValue: "没有带此标签的图片")
    static let emptyDuplicates = String(localized: "emptyDuplicates", defaultValue: "没有重复的图片")
    static let emptyRecent7Days = String(localized: "emptyRecent7Days", defaultValue: "最近 7 天没有新图")
    static let emptyLargeFiles = String(localized: "emptyLargeFiles", defaultValue: "没有大于 5 MB 的图")
    static let emptyNoPhotosYet = String(localized: "emptyNoPhotosYet", defaultValue: "还没有图片")
    /// 空状态副提示
    static let hintFilterAdjust = String(localized: "hintFilterAdjust", defaultValue: "尝试减少筛选条件或调整侧边栏")
    static let hintSearchOther = String(localized: "hintSearchOther", defaultValue: "试试其他关键词")
    static let hintMoveToFolder = String(localized: "hintMoveToFolder", defaultValue: "把图片移动到文件夹来整理")
    static let hintAutoImportToFolder = String(localized: "hintAutoImportToFolder", defaultValue: "导入图片后会自动放到此文件夹")
    static let hintAddTagInDetail = String(localized: "hintAddTagInDetail", defaultValue: "在详情中添加此标签")
    static let hintDuplicatesAuto = String(localized: "hintDuplicatesAuto", defaultValue: "重复图会自动出现在这里")
    /// 回收站空状态副提示——带 retentionDays 参数
    /// 之前 hardcoded \(TrashRetentionDays.defaultValue.rawValue) (永远 30)
    /// 现在接受 retentionDays, 跟 settings 同步——V6.08 bug 修
    static func hintTrashAutoPurge(days: Int) -> String {
        "删除的图片会出现在这里，\(days) 天后自动永久清除"
    }
    static let hintStartImport = String(localized: "hintStartImport", defaultValue: "拖入图片，或点击“导入图片”开始添加")

    // MARK: - V6.08: ModelContainer 启动失败 (SwiftData 损坏 / schema 不兼容)
    /// ModelContainer.init 失败时显示的全屏错误页文案
    static let databaseInitFailed = String(localized: "databaseInitFailed", defaultValue: "图库无法启动")
    static let databaseInitFailedHint = String(localized: "databaseInitFailedHint", defaultValue: "SwiftData 存储损坏，或当前版本不兼容旧数据库。")
    static let databaseInitReset = String(localized: "databaseInitReset", defaultValue: "重置数据库（删除本地所有数据）")
    static let databaseInitQuit = String(localized: "databaseInitQuit", defaultValue: "退出")
    static let databaseInitResetConfirm = String(localized: "databaseInitResetConfirm", defaultValue: "重置会永久删除所有照片记录、文件夹、标签和回收站。导入的原图文件不会删除（仍在 Finder 里）。确定要继续吗？")
    static let databaseInitResetSuccess = String(localized: "databaseInitResetSuccess", defaultValue: "数据库已重置")

    // MARK: - V6.12.15: SettingsView + KeyboardShortcutsSheet + ImageGalleryApp 硬编码英文入库
    /// About 页面 app 名（之前 SettingsView.swift:452 hardcoded "ImageGallery"）
    /// i18n 准备：未来可 NSLocalizedString("CFBundleDisplayName") 替
    static let appName = String(localized: "appName", defaultValue: "ImageGallery")
    /// About 页面 credit（之前 SettingsView.swift:488 hardcoded "Built with SwiftUI + SwiftData"）
    static let builtWithStack = String(localized: "builtWithStack", defaultValue: "Built with SwiftUI + SwiftData")
    /// KeyboardShortcutsSheet 标题（之前 KeyboardShortcutsSheet.swift:21 hardcoded "Keyboard Shortcuts"）
    static let keyboardShortcutsTitle = String(localized: "keyboardShortcutsTitle", defaultValue: "Keyboard Shortcuts")
    /// 通用 "Done" 按钮（之前 KeyboardShortcutsSheet.swift:24 hardcoded "Done"）
    /// 其他 sheet 关闭按钮 (rename dialog / delete confirm / add tag) 也复用
    static let done = String(localized: "done", defaultValue: "Done")
    /// Help 菜单 "Keyboard Shortcuts…" 项（之前 ImageGalleryApp.swift:205 hardcoded "Keyboard Shortcuts…"）
    static let keyboardShortcutsMenu = String(localized: "keyboardShortcutsMenu", defaultValue: "Keyboard Shortcuts…")

    // MARK: - V6.12.18: SettingsView / DetailView / ActiveFiltersBar / ContentViewModel 硬编码入库
    // SettingsView — toolbar 按钮
    static let settingsResetAll = String(localized: "settingsResetAll", defaultValue: "恢复全部为默认")
    static let settingsResetAllTooltip = String(localized: "settingsResetAllTooltip", defaultValue: "恢复全部设置为默认")
    // V6.31.3: reset 二次确认 — 防止误触清空用户偏好
    static let settingsResetConfirmTitle = String(localized: "settingsResetConfirmTitle", defaultValue: "恢复全部为默认？")
    static let settingsResetConfirmMessage = String(localized: "settingsResetConfirmMessage", defaultValue: "这将清空你所有的偏好设置（默认排序、视图模式、缩略图大小、外观模式等）。")
    static let settingsResetConfirmAction = String(localized: "settingsResetConfirmAction", defaultValue: "恢复默认")
    static let settingsHelpLabel = String(localized: "settingsHelpLabel", defaultValue: "帮助")
    static let settingsHelpTooltip = String(localized: "settingsHelpTooltip", defaultValue: "使用帮助")
    // SettingsView — picker/slider label
    static let languageLabel = String(localized: "languageLabel", defaultValue: "语言")
    static let settingsSortLabel = String(localized: "settingsSortLabel", defaultValue: "排序")
    static let settingsLayoutLabel = String(localized: "settingsLayoutLabel", defaultValue: "布局")
    static let settingsSizeLabel = String(localized: "settingsSizeLabel", defaultValue: "大小")
    static let settingsAppearanceLabel = String(localized: "settingsAppearanceLabel", defaultValue: "外观")
    static let settingsAutoDedupeLabel = String(localized: "settingsAutoDedupeLabel", defaultValue: "导入时自动去重")
    static let settingsAutoThumbnailsLabel = String(localized: "settingsAutoThumbnailsLabel", defaultValue: "导入时生成缩略图")
    static let settingsFormatLabel = String(localized: "settingsFormatLabel", defaultValue: "格式")
    static let settingsQualityLabel = String(localized: "settingsQualityLabel", defaultValue: "质量")
    static let settingsRetentionLabel = String(localized: "settingsRetentionLabel", defaultValue: "保留时长")
    // SettingsView — Links section
    static let settingsProjectHomepage = String(localized: "settingsProjectHomepage", defaultValue: "项目主页")
    static let settingsHelpDocs = String(localized: "settingsHelpDocs", defaultValue: "使用帮助")
    static let settingsIssueTracker = String(localized: "settingsIssueTracker", defaultValue: "问题反馈")
    // SettingsView — 版权 + 预览 tooltip
    static let settingsCopyright = String(localized: "settingsCopyright", defaultValue: "© 2026 ImageGallery")
    static let settingsThumbnailSizeHelpTooltip = String(localized: "settingsThumbnailSizeHelpTooltip", defaultValue: "实时预览缩略图大小")
    /// SettingsView.safeExternalLink 错误兜底（urlString 是开发者填错的 URL）
    static func settingsAccessibilityLinkMisconfigured(_ urlString: String) -> String { String.localizedStringWithFormat(String(localized: "settingsAccessibilityLinkMisconfigured", defaultValue: "链接配置错误: %@"), urlString) }
    // DetailView — 评分显示
    static let detailNoRating = String(localized: "detailNoRating", defaultValue: "未评分")
    /// DetailView 删除照片 alert message — 带 Term 插值（Term.photo + Term.library）
    static func deletePhotoConfirmWithTerms(photo: String, library: String) -> String {
        String.localizedStringWithFormat(
            String(localized: "deletePhotoConfirmWithTerms", defaultValue: "%@将从%@中移除，文件也会被永久删除。"),
            photo, library
        )
    }
    /// SettingsView 导出质量滑杆右侧百分比显示
    static func exportQualityPercent(_ value: Int) -> String {
        String.localizedStringWithFormat(String(localized: "exportQualityPercent", defaultValue: "%lld%%"), value)
    }
    /// ActiveFiltersBar 分组 filter chip 文本 — `label · count`
    static func activeFilterChip(label: String, count: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "activeFilterChip", defaultValue: "%@ · %lld"),
            label, count
        )
    }
    /// 详情面板评分星按钮 help — 当前已设的星 (点击清除)
    static func ratingCurrent(_ n: Int) -> String { String.localizedStringWithFormat(String(localized: "ratingCurrent", defaultValue: "当前 %lld 星（点击清除）"), n) }
    /// 详情面板评分星按钮 help — hover 时设的星
    static func ratingSetTo(_ n: Int) -> String { String.localizedStringWithFormat(String(localized: "ratingSetTo", defaultValue: "设为 %lld 星"), n) }
    // ActiveFiltersBar — chip tooltip
    static let activeFiltersClearAllTooltip = String(localized: "activeFiltersClearAllTooltip", defaultValue: "清除所有筛选条件")
    static let activeFiltersRemoveFilterTooltip = String(localized: "activeFiltersRemoveFilterTooltip", defaultValue: "移除此筛选")
    // ContentViewModel — titlebar 右上角 ⓘ 按钮
    static let titlebarInfoLabel = String(localized: "titlebarInfoLabel", defaultValue: "信息面板")
    static let titlebarInfoTooltipShow = String(localized: "titlebarInfoTooltipShow", defaultValue: "显示信息面板 (⌘I)")
    static let titlebarInfoTooltipHide = String(localized: "titlebarInfoTooltipHide", defaultValue: "隐藏信息面板 (⌘I)")

    // MARK: - V6.37.1: 模型枚举 displayName
    // AccentColor — 强调色 9 个 case
    static let accentColorSystem = String(localized: "accentColorSystem", defaultValue: "跟随系统")
    static let accentColorBlue = String(localized: "accentColorBlue", defaultValue: "蓝色")
    static let accentColorPurple = String(localized: "accentColorPurple", defaultValue: "紫色")
    static let accentColorPink = String(localized: "accentColorPink", defaultValue: "粉色")
    static let accentColorRed = String(localized: "accentColorRed", defaultValue: "红色")
    static let accentColorOrange = String(localized: "accentColorOrange", defaultValue: "橙色")
    static let accentColorYellow = String(localized: "accentColorYellow", defaultValue: "黄色")
    static let accentColorGreen = String(localized: "accentColorGreen", defaultValue: "绿色")
    static let accentColorGraphite = String(localized: "accentColorGraphite", defaultValue: "石墨色")

    // AppearanceMode — 外观 3 个 case
    static let appearanceModeSystem = String(localized: "appearanceModeSystem", defaultValue: "跟随系统")
    static let appearanceModeLight = String(localized: "appearanceModeLight", defaultValue: "浅色")
    static let appearanceModeDark = String(localized: "appearanceModeDark", defaultValue: "深色")

    // PhotoShape — 形状 3 个 case (filter popover / sidebar)
    static let photoShapeLandscape = String(localized: "photoShapeLandscape", defaultValue: "横图")
    static let photoShapePortrait = String(localized: "photoShapePortrait", defaultValue: "竖图")
    static let photoShapeSquare = String(localized: "photoShapeSquare", defaultValue: "方形")

    // FontScale — 字体大小 4 档
    static let fontScaleCompact = String(localized: "fontScaleCompact", defaultValue: "紧凑")
    static let fontScaleDefault = String(localized: "fontScaleDefault", defaultValue: "默认")
    static let fontScaleRelaxed = String(localized: "fontScaleRelaxed", defaultValue: "舒适")
    static let fontScaleLarge = String(localized: "fontScaleLarge", defaultValue: "超大")

    // Language — Settings picker 3 种
    static let languageZhHans = String(localized: "languageZhHans", defaultValue: "简体中文")
    static let languageZhHant = String(localized: "languageZhHant", defaultValue: "繁體中文")
    static let languageEn = String(localized: "languageEn", defaultValue: "English")

    // TrashRetentionDays — `\(rawValue) 天` (Int → %lld)
    static func trashRetentionDays(_ days: Int) -> String {
        String.localizedStringWithFormat(String(localized: "trashRetentionDays", defaultValue: "%lld 天"), days)
    }

    // ThumbnailLayoutMode — 缩略图布局 2 个 case
    static let layoutModeSquareFit = String(localized: "layoutModeSquareFit", defaultValue: "网格")
    static let layoutModeList = String(localized: "layoutModeList", defaultValue: "列表")

    // ThumbnailDensity — 缩略图密度 4 档
    static let thumbnailDensityCompact = String(localized: "thumbnailDensityCompact", defaultValue: "极小")
    static let thumbnailDensitySmall = String(localized: "thumbnailDensitySmall", defaultValue: "小")
    static let thumbnailDensityMedium = String(localized: "thumbnailDensityMedium", defaultValue: "中")
    static let thumbnailDensityLarge = String(localized: "thumbnailDensityLarge", defaultValue: "大")

    // PhotoStats — 日期分组 6 个 (其中 2 个 Int → %lld)
    static let dateSectionToday = String(localized: "dateSectionToday", defaultValue: "今天")
    static let dateSectionYesterday = String(localized: "dateSectionYesterday", defaultValue: "昨天")
    static let dateSectionThisWeek = String(localized: "dateSectionThisWeek", defaultValue: "本周")
    static let dateSectionThisMonth = String(localized: "dateSectionThisMonth", defaultValue: "本月")
    static func dateSectionMonthLabel(_ month: Int) -> String {
        String.localizedStringWithFormat(String(localized: "dateSectionMonthLabel", defaultValue: "%lld 月"), month)
    }
    static func dateSectionYearLabel(_ year: Int) -> String {
        String.localizedStringWithFormat(String(localized: "dateSectionYearLabel", defaultValue: "%lld 年"), year)
    }

    // MARK: - V6.37.2: 详情面板
    // DetailView 顶部导航按钮 .help tooltip
    static let detailPrevHelp = String(localized: "detailPrevHelp", defaultValue: "上一张 (←)")
    static let detailNextHelp = String(localized: "detailNextHelp", defaultValue: "下一张 (→)")
    // DetailView undo description (含 tag.name / filename 插值, %@)
    static func undoRemoveTag(_ tagName: String) -> String {
        String.localizedStringWithFormat(String(localized: "undoRemoveTag", defaultValue: "移除标签 %@"), tagName)
    }
    static func undoRename(_ filename: String) -> String {
        String.localizedStringWithFormat(String(localized: "undoRename", defaultValue: "重命名为 %@"), filename)
    }
    static func undoAddTag(_ tagName: String) -> String {
        String.localizedStringWithFormat(String(localized: "undoAddTag", defaultValue: "添加标签 %@"), tagName)
    }

    // MARK: - V6.37.3: Settings + Onboarding + 快捷键速查
    // SettingsCategory enum 5 case (.library 用 Term.library)
    static let settingsCategoryGeneral = String(localized: "settingsCategoryGeneral", defaultValue: "通用")
    static let settingsCategoryAppearance = String(localized: "settingsCategoryAppearance", defaultValue: "外观")
    static let settingsCategoryAccent = String(localized: "settingsCategoryAccent", defaultValue: "强调色")
    static let settingsCategoryAbout = String(localized: "settingsCategoryAbout", defaultValue: "关于")
    // SettingsView 主视图
    static let settingsTitle = String(localized: "settingsTitle", defaultValue: "设置")
    // GeneralSettingsView — 默认排序 + 字体大小 + 默认视图
    static let settingsDefaultSortTitle = String(localized: "settingsDefaultSortTitle", defaultValue: "默认排序")
    static let settingsDefaultSortSubtitle = String(localized: "settingsDefaultSortSubtitle", defaultValue: "启动时图片按以下规则排序")
    static let settingsFontSizeTitle = String(localized: "settingsFontSizeTitle", defaultValue: "字体大小")
    static let settingsFontSizeSubtitle = String(localized: "settingsFontSizeSubtitle", defaultValue: "调整 app 内所有文字大小。macOS 没系统级 Dynamic Type 设置, 这是 in-app 入口。")
    static let settingsFontSizeInterfaceLabel = String(localized: "settingsFontSizeInterfaceLabel", defaultValue: "界面文字")
    static let settingsDefaultViewTitle = String(localized: "settingsDefaultViewTitle", defaultValue: "默认视图")
    static let settingsDefaultViewSubtitle = String(localized: "settingsDefaultViewSubtitle", defaultValue: "启动应用时的缩略图布局形状。视图模式 (网格/列表/时间线) 仍可通过 View 菜单或 ⌥1/⌥2/⌥3 快捷键切换。")
    static let settingsLanguageTitle = String(localized: "settingsLanguageTitle", defaultValue: "语言 / Language")
    static let settingsLanguageSubtitle = String(localized: "settingsLanguageSubtitle", defaultValue: "App 显示语言。需重启 app 让部分 SwiftUI 文案刷新。")
    // AppearanceSettingsView — 缩略图大小 + 外观 + 导入 + 导出
    static let settingsThumbnailSizeTitle = String(localized: "settingsThumbnailSizeTitle", defaultValue: "缩略图大小")
    static let settingsThumbnailSizeSubtitle = String(localized: "settingsThumbnailSizeSubtitle", defaultValue: "默认缩略图尺寸。拖动 slider 实时预览缩略图大小。当前会话用 toolbar 临时改的会在重启后恢复。")
    static let settingsAppearanceTitle = String(localized: "settingsAppearanceTitle", defaultValue: "外观")
    static let settingsAppearanceSubtitle = String(localized: "settingsAppearanceSubtitle", defaultValue: "应用整体外观。\u{201C}跟随系统\u{201D} 会随 macOS 切换自动调整。")
    static let settingsImportTitle = String(localized: "settingsImportTitle", defaultValue: "导入")
    static let settingsImportSubtitle = String(localized: "settingsImportSubtitle", defaultValue: "拖入或选择文件夹导入图片时的默认行为。")
    static let settingsExportTitle = String(localized: "settingsExportTitle", defaultValue: "导出")
    static let settingsExportSubtitle = String(localized: "settingsExportSubtitle", defaultValue: "导出图片时的默认格式和质量。")
    // LibrarySettingsView — 自动清理
    static let settingsAutoCleanupTitle = String(localized: "settingsAutoCleanupTitle", defaultValue: "自动清理")
    static let settingsAutoCleanupSubtitle = String(localized: "settingsAutoCleanupSubtitle", defaultValue: "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。")
    // AccentSettingsView — 强调色
    static let settingsAccentSectionTitle = String(localized: "settingsAccentSectionTitle", defaultValue: "强调色")
    static let settingsAccentSectionSubtitle = String(localized: "settingsAccentSectionSubtitle", defaultValue: "选择应用的主色调，影响按钮、选中状态、链接等。")
    // AboutSettingsView
    static let settingsAppInfoTitle = String(localized: "settingsAppInfoTitle", defaultValue: "应用信息")
    static let settingsLinksTitle = String(localized: "settingsLinksTitle", defaultValue: "链接")
    static let settingsCopyrightTitle = String(localized: "settingsCopyrightTitle", defaultValue: "版权")

    // OnboardingView — 3 卡 sheet
    static let onboardingImportTitle = String(localized: "onboardingImportTitle", defaultValue: "导入你的照片")
    static let onboardingImportSubtitle = String(localized: "onboardingImportSubtitle", defaultValue: "支持 JPG、PNG、HEIC、TIFF 等常见格式\n拖入文件夹即可批量导入，或按 ⌘O 选择文件")
    static let onboardingImportHint = String(localized: "onboardingImportHint", defaultValue: "导入快捷键")
    static let onboardingMarqueeTitle = String(localized: "onboardingMarqueeTitle", defaultValue: "拖动鼠标框选多张照片")
    static let onboardingMarqueeSubtitle = String(localized: "onboardingMarqueeSubtitle", defaultValue: "在空白处按下左键拖动，可一次性选择一片区域内的所有照片\n类似 macOS Finder 和 Photos.app 的交互")
    static let onboardingMarqueeHint = String(localized: "onboardingMarqueeHint", defaultValue: "尝试")
    static let onboardingMarqueeHintValue = String(localized: "onboardingMarqueeHintValue", defaultValue: "空白处拖动")
    static let onboardingMoreTitle = String(localized: "onboardingMoreTitle", defaultValue: "更多功能")
    static let onboardingMoreSubtitle = String(localized: "onboardingMoreSubtitle", defaultValue: "右键图片可看到分享、旋转、评分等操作\n按 ⌘? 查看所有快捷键，按 ⌘, 打开设置")
    static let onboardingMoreHint = String(localized: "onboardingMoreHint", defaultValue: "快捷键")
    static let onboardingSkip = String(localized: "onboardingSkip", defaultValue: "跳过")
    static let onboardingBack = String(localized: "onboardingBack", defaultValue: "上一步")
    static let onboardingNext = String(localized: "onboardingNext", defaultValue: "下一步")
    static let onboardingStart = String(localized: "onboardingStart", defaultValue: "开始使用")

    // KeyboardShortcutsSheet — ⌘? 速查 6 section 28 entry
    static let shortcutsSectionFile = String(localized: "shortcutsSectionFile", defaultValue: "文件")
    static let shortcutsImportImage = String(localized: "shortcutsImportImage", defaultValue: "导入图片")
    static let shortcutsNewFolder = String(localized: "shortcutsNewFolder", defaultValue: "新建文件夹")
    static let shortcutsExportSelected = String(localized: "shortcutsExportSelected", defaultValue: "导出选中")
    static let shortcutsSectionEdit = String(localized: "shortcutsSectionEdit", defaultValue: "编辑")
    static let shortcutsCopyToPasteboard = String(localized: "shortcutsCopyToPasteboard", defaultValue: "复制到剪贴板")
    static let shortcutsUndo = String(localized: "shortcutsUndo", defaultValue: "撤销")
    static let shortcutsRedo = String(localized: "shortcutsRedo", defaultValue: "重做")
    static let shortcutsSectionView = String(localized: "shortcutsSectionView", defaultValue: "视图")
    static let shortcutsViewGrid = String(localized: "shortcutsViewGrid", defaultValue: "网格视图")
    static let shortcutsViewList = String(localized: "shortcutsViewList", defaultValue: "列表视图")
    static let shortcutsViewTimeline = String(localized: "shortcutsViewTimeline", defaultValue: "时间线视图")
    static let shortcutsQuickLook = String(localized: "shortcutsQuickLook", defaultValue: "快速查看")
    static let shortcutsImmersive = String(localized: "shortcutsImmersive", defaultValue: "进入沉浸式")
    static let shortcutsSectionSidebar = String(localized: "shortcutsSectionSidebar", defaultValue: "侧栏 / 详情")
    static let shortcutsToggleSidebar = String(localized: "shortcutsToggleSidebar", defaultValue: "切换侧栏")
    static let shortcutsToggleDetail = String(localized: "shortcutsToggleDetail", defaultValue: "切换详情面板")
    static let shortcutsToggleInfo = String(localized: "shortcutsToggleInfo", defaultValue: "切换信息面板")
    static let shortcutsSectionSortFilter = String(localized: "shortcutsSectionSortFilter", defaultValue: "排序 / 筛选")
    static let shortcutsToggleSort = String(localized: "shortcutsToggleSort", defaultValue: "切换排序方向")
    static let shortcutsResetFilter = String(localized: "shortcutsResetFilter", defaultValue: "重置筛选")
    static let shortcutsFocusSearch = String(localized: "shortcutsFocusSearch", defaultValue: "聚焦搜索框")
    static let shortcutsSectionNavigation = String(localized: "shortcutsSectionNavigation", defaultValue: "导航 / 缩放")
    static let shortcutsPrevPhoto = String(localized: "shortcutsPrevPhoto", defaultValue: "上一张")
    static let shortcutsNextPhoto = String(localized: "shortcutsNextPhoto", defaultValue: "下一张")
    static let shortcutsZoomIn = String(localized: "shortcutsZoomIn", defaultValue: "放大缩略图")
    static let shortcutsZoomOut = String(localized: "shortcutsZoomOut", defaultValue: "缩小缩略图")
    static let shortcutsResetZoom = String(localized: "shortcutsResetZoom", defaultValue: "重置缩略图大小")
    static let shortcutsOpenSettings = String(localized: "shortcutsOpenSettings", defaultValue: "设置")

    // MARK: - V6.37.4: 侧栏 + 智能文件夹
    // SidebarSectionHeader — 新建按钮 a11y + 折叠/展开 hint
    static let sidebarAddAccessibility = String(localized: "sidebarAddAccessibility", defaultValue: "新建")
    static let sidebarAccessibilityCollapse = String(localized: "sidebarAccessibilityCollapse", defaultValue: "单击折叠")
    static let sidebarAccessibilityExpand = String(localized: "sidebarAccessibilityExpand", defaultValue: "单击展开")
    // SidebarRow — a11y label (含 %@)
    static func sidebarRowShowLabel(_ name: String) -> String {
        String.localizedStringWithFormat(String(localized: "sidebarRowShowLabel", defaultValue: "显示 %@"), name)
    }
    // SidebarView — 智能文件夹 section 菜单 + 列表项
    static let sidebarNewSmartFolder = String(localized: "sidebarNewSmartFolder", defaultValue: "新建智能文件夹")
    static let sidebarCollapse = String(localized: "sidebarCollapse", defaultValue: "折叠")
    static let sidebarExpand = String(localized: "sidebarExpand", defaultValue: "展开")
    static let sidebarDeleteSmartFolder = String(localized: "sidebarDeleteSmartFolder", defaultValue: "删除智能文件夹")
    // SmartFolderCreateSheet — 4 维 filter 摘要 (含 %lld)
    static func smartFolderFolderCount(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "smartFolderFolderCount", defaultValue: "%lld 文件夹"), count)
    }
    static func smartFolderTagCount(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "smartFolderTagCount", defaultValue: "%lld 标签"), count)
    }
    static func smartFolderShapeCount(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "smartFolderShapeCount", defaultValue: "%lld 形状"), count)
    }
    static func smartFolderMinRating(_ rating: Int) -> String {
        String.localizedStringWithFormat(String(localized: "smartFolderMinRating", defaultValue: "≥%lld 星"), rating)
    }
    // SmartFolder enum — 13 个 icon displayName
    static let smartFolderIconStar = String(localized: "smartFolderIconStar", defaultValue: "星标")
    static let smartFolderIconHeart = String(localized: "smartFolderIconHeart", defaultValue: "喜欢")
    static let smartFolderIconFlame = String(localized: "smartFolderIconFlame", defaultValue: "热门")
    static let smartFolderIconLeaf = String(localized: "smartFolderIconLeaf", defaultValue: "自然")
    static let smartFolderIconStarCircle = String(localized: "smartFolderIconStarCircle", defaultValue: "精选")
    static let smartFolderIconHeartCircle = String(localized: "smartFolderIconHeartCircle", defaultValue: "收藏")
    static let smartFolderIconBookmark = String(localized: "smartFolderIconBookmark", defaultValue: "书签")
    static let smartFolderIconTag = String(localized: "smartFolderIconTag", defaultValue: "标签")
    static let smartFolderIconFolder = String(localized: "smartFolderIconFolder", defaultValue: "文件夹")
    static let smartFolderIconPhotoStack = String(localized: "smartFolderIconPhotoStack", defaultValue: "相册")
    static let smartFolderIconSun = String(localized: "smartFolderIconSun", defaultValue: "明亮")
    static let smartFolderIconMoon = String(localized: "smartFolderIconMoon", defaultValue: "夜景")
    static let smartFolderIconSparkle = String(localized: "smartFolderIconSparkle", defaultValue: "精选集")

    // MARK: - V6.37.5: 选中操作条 + Toast + 上下文菜单
    // SelectionMiniToolbar — 5 action label + .help tooltip
    //   注: 复用 Copy.tagLabel / Copy.delete / Copy.selectedCount / Copy.sidebarUnfiled / Copy.create
    //     "未整理" → Copy.sidebarUnfiled ("待整理") — 跟 sidebar 命名统一
    //     "X 张已选" → Copy.selectedCount(_:) ("已选 X 张") — 跟既有格式统一
    static let miniToolbarTagHelp = String(localized: "miniToolbarTagHelp", defaultValue: "给选中照片加标签")
    static let miniToolbarMove = String(localized: "miniToolbarMove", defaultValue: "移动")
    static let miniToolbarMoveHelp = String(localized: "miniToolbarMoveHelp", defaultValue: "移动到文件夹")
    static let miniToolbarRenameHelp = String(localized: "miniToolbarRenameHelp", defaultValue: "按模板批量重命名 (⌘⇧R)")
    static let miniToolbarExport = String(localized: "miniToolbarExport", defaultValue: "导出")
    static let miniToolbarExportHelp = String(localized: "miniToolbarExportHelp", defaultValue: "导出选中照片")
    static let miniToolbarDeleteHelp = String(localized: "miniToolbarDeleteHelp", defaultValue: "移到回收站")
    static let miniToolbarAddTagTitle = String(localized: "miniToolbarAddTagTitle", defaultValue: "加标签")
    static let miniToolbarEmptyTags = String(localized: "miniToolbarEmptyTags", defaultValue: "还没有标签")
    static let miniToolbarNewTagPlaceholder = String(localized: "miniToolbarNewTagPlaceholder", defaultValue: "新标签")
    // ToastView — undo/close .help (含 ⌘Z glyph)
    //   注: 复用 Copy.undo ("撤销") 给主 Text, .help 单独走新 key 保留快捷键 glyph
    static let toastUndoHelp = String(localized: "toastUndoHelp", defaultValue: "撤销 (⌘Z)")
    static let toastCloseHelp = String(localized: "toastCloseHelp", defaultValue: "关闭")
    // CellContextMenuModifier — 3 tier 分组 (视图 / 编辑 / 分享) + 旋转 submenu
    static let contextMenuRotateLeft = String(localized: "contextMenuRotateLeft", defaultValue: "向左旋转")
    static let contextMenuRotateRight = String(localized: "contextMenuRotateRight", defaultValue: "向右旋转")
    static let contextMenuRotateSubmenu = String(localized: "contextMenuRotateSubmenu", defaultValue: "旋转")
    static let contextMenuViewSubmenu = String(localized: "contextMenuViewSubmenu", defaultValue: "视图")
    static let contextMenuEdit = String(localized: "contextMenuEdit", defaultValue: "编辑")
    static let contextMenuShare = String(localized: "contextMenuShare", defaultValue: "分享")
}
