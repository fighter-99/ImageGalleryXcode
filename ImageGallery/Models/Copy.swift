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
    static func imported(_ count: Int) -> String { "已导入 \(count) 张图片" }
    static func importedPartial(inserted: Int, failed: Int) -> String { "已导入 \(inserted) 张，\(failed) 张失败" }
    static func exported(_ count: Int) -> String { "已导出 \(count) 张图片" }
    static func movedToRecycleBin(_ count: Int, retentionDays: Int) -> String { "已移到回收站（\(retentionDays) 天后永久删除）" }
    static func movedDuplicates(_ count: Int) -> String { "已移到回收站 \(count) 张重复图" }
    static func recycledBinEmptied(_ count: Int) -> String { "已清空回收站（\(count) 张）" }
    static func copiedToPasteboard(_ count: Int) -> String {
        count == 1 ? "已复制 1 张图片" : "已复制 \(count) 张图片"
    }

    // MARK: - 错误 (3 段式)
    static let storageError = "无法保存图片到图库。请检查磁盘空间，或在「系统设置 → 隐私与安全 → 完整磁盘访问权限」中授权 ImageGallery，然后重试。"
    static func importFailed(_ filename: String) -> String { "导入失败：\(filename)" }
    static func exportFailed(_ filename: String) -> String { "导出失败：\(filename)" }
    static func moveToRecycleBinFailed(_ error: String) -> String { "移到回收站失败：\(error)" }
    static func emptyRecycleBinFailed(_ error: String) -> String { "清空回收站失败：\(error)" }
    static func batchMoveToRecycleBinFailed(_ error: String) -> String { "批量移到回收站失败：\(error)" }
    static let batchRatingFailed = "批量评分失败"
    static func recycleBinOperationFailed(_ error: String) -> String { "回收站操作失败：\(error)" }

    // MARK: - 空态 (含引导)
    static let emptyLibrary = "图库还是空的"
    static let emptyLibraryHint = "把图片拖到这里，或点击 ⌘O 导入"
    static let emptyRecycleBin = "回收站是空的"
    static let selectAPhoto = "选择一张图片"
    static let selectAPhotoHint = "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选"
    static let thumbnailLoadFailed = "加载失败"

    // MARK: - 详情面板
    static func photoPosition(current: Int, total: Int) -> String { "\(current) / \(total)" }
    static func photoPosition1Indexed(current: Int, total: Int) -> String { "\(current) / \(total)" }
    static func imageDimensions(width: Int, height: Int) -> String { "\(width) × \(height)" }
    static let renameHint = "给图片一个新名字（不包含扩展名）"
    static let tagLabel = "标签"
    static let addTagHint = "点击 + 添加标签"
    static let deletePhotoConfirm = "图片将从图库中移除，文件也会被永久删除。"
    static let emptyRecycleBinConfirm = "回收站里的所有照片将被永久删除，无法恢复。"
    static func recycleBinCount(_ count: Int) -> String { "回收站有 \(count) 张" }

    // MARK: - 状态栏
    static func totalCount(_ count: Int) -> String { "\(count) 张" }
    static func selectedCount(_ count: Int) -> String { "已选 \(count) 张" }
    static let statusSeparator = "·"
    static func daysRemaining(_ days: Int) -> String { "\(days)" }

    // MARK: - 设置面板
    static let viewModeGrid = "网格"
    static let viewModeList = "列表"
    static let viewModeTimeline = "时间线"
    static let recycleBinSubtitle = "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。"
    static func thumbnailSizeLabel(_ size: Int) -> String { "\(size)" }

    // MARK: - 侧栏 / 按钮
    static let newFolder = "新建文件夹"
    static let newTag = "新建标签"
    static let folderNamePlaceholder = "文件夹名称"
    static let cancel = "取消"
    static let create = "创建"
    static let confirm = "确定"
    static let delete = "删除"

    // MARK: - 筛选
    static let clearAllFilters = "清除全部"

    // MARK: - 拖拽导入
    static let dropReleaseToImport = "松开导入"
    static let dropSupportedTypes = "支持图片文件 / 文件夹"

    // MARK: - Confirm 对话框 (V5.50-4 补充)
    static func deletePhotosConfirm(retentionDays: Int) -> String { "选中的图片会移到回收站，\(retentionDays) 天后自动永久清除。可在回收站中恢复。" }
    static let newFolderPrompt = "为新文件夹命名"
    static let newFolderHint = "选\"跳过\"避免重复导入。"

    // MARK: - 重复图清理 (V5.50-4 补充)
    static func duplicatesFoundGroups(_ count: Int) -> String { "发现 \(count) 组重复" }
    static func duplicatesCleanable(_ count: Int, size: String) -> String { "可清理 \(count) 张 · \(size)" }
    static let duplicatesNone = "暂无重复图"
    static func duplicatesExplanation(retentionDays: Int) -> String { "每组保留导入时间最近的一张，其他移到回收站（\(retentionDays) 天后自动永久清除）" }

    // MARK: - 上下文菜单 (V5.50-4 补充)
    static let clearRating = "清除评分"

    // MARK: - 计数 / 辅助 (V5.50-4 补充)
    static func photoCount(_ count: Int) -> String { "\(count)" }
    static func yearLabel(_ year: String) -> String { year }
    static func daysBadge(_ days: Int) -> String { "\(days)" }
    static func sidebarCount(_ count: Int) -> String { "\(count)" }
    static func dateSectionCount(_ count: Int) -> String { "\(count) 张" }
    static func autoDeleteAfterDays(_ days: Int) -> String { "\(days) 天后自动永久清除" }

    // MARK: - 视图模式 (V5.50-4 扩展——菜单用全名，区别于设置面板的 "网格" 简称)
    static let viewModeGridFull = "缩略图视图"
    static let viewModeListFull = "列表视图"
    static let viewModeTimelineFull = "时间线视图"

    // MARK: - 应用菜单 (V5.50-4 扩展)
    static let settingsMenu = "设置…"
    static let quickLook = "快速查看"
    static let previousPhoto = "上一张"
    static let nextPhoto = "下一张"
    static let clearMenu = "清空菜单"
    static let noRecentFiles = "无最近文件"
    static func recentFile(index: Int, filename: String) -> String { "\(index). \(filename)" }

    // MARK: - Confirm 按钮 (V5.50-4 扩展)
    static let empty = "清空"
    static let skipAll = "全部跳过（保留现有）"
    static let importAll = "全部导入（可能重复）"
    static let deleteConfirmTitle = "确定要删除这张图片吗？"

    // MARK: - 输入框 (V5.50-4 扩展)
    static let tagNamePlaceholder = "标签名称"
}
