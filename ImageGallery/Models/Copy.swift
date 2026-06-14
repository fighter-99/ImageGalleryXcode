//
//  Copy.swift
//  ImageGallery
//
//  V5.50-2 NEW: 微文案字典 (microcopy dictionary)——所有用户可见字符串统一收纳
//  V5.50-3 EXTEND: 空态/详情面板/Confirm dialog/状态栏/设置 全部走字典
//
//  4 条原则 (V5.44 设计):
//    1. 动词开头 + 主语宾语明确——"已导出 5 张图片" (不是 "成功" / "完成")
//    2. 3 段式错误: 出了什么问题 + 可能原因 + 怎么解决
//    3. 数字带量词——"12 张" / "12.3 MB" / "1 分钟前" (不混用 "个")
//    4. 空态带引导——"图库还是空的" + "把图片拖到这里，或点 ⌘O 导入"
//
//  镜像 pattern (仿 V5.45 Typography 6 token + V5.47 Term 字典):
//    - 单一真相源——改一处全改
//    - 函数式 closure 形式 (count: Int) -> String 动态插值
//    - V5.50-2 之后所有 showToast / enqueueToast 走 Copy.xxx
//    - V5.50-3 之后所有 Text("...") 走 Copy.xxx
//    - V5.50-4 之后 Confirm dialog / 快捷键提示 / drag drop 走 Copy.xxx
//
//  不动:
//    - swift string interpolation 行为 (V5.50-2 之前用 "\(count) 张图片" 散落 6+ 处)
//    - 未来 i18n 时直接换成 NSLocalizedString (V5.52 String Catalog 准备)
//

import Foundation

/// V5.50-2 + V5.50-3: 微文案字典——所有用户可见字符串统一来源
enum Copy {
    // MARK: - 动作结果 (动词开头 + 主语宾语明确 + 数字带量词)

    /// 导入 N 张图成功
    static func imported(_ count: Int) -> String {
        "已导入 \(count) 张图片"
    }

    /// 导入 N 张成功 + M 张失败
    static func importedPartial(inserted: Int, failed: Int) -> String {
        "已导入 \(inserted) 张，\(failed) 张失败"
    }

    /// 导出 N 张图成功
    static func exported(_ count: Int) -> String {
        "已导出 \(count) 张图片"
    }

    /// 移到回收站成功 (含保留天数提示)
    static func movedToRecycleBin(_ count: Int, retentionDays: Int) -> String {
        "已移到回收站（\(retentionDays) 天后永久删除）"
    }

    /// 移到回收站 N 张重复图
    static func movedDuplicates(_ count: Int) -> String {
        "已移到回收站 \(count) 张重复图"
    }

    /// 清空回收站 N 张
    static func recycledBinEmptied(_ count: Int) -> String {
        "已清空回收站（\(count) 张）"
    }

    /// 复制 N 张图到剪贴板成功
    static func copiedToPasteboard(_ count: Int) -> String {
        count == 1 ? "已复制 1 张图片" : "已复制 \(count) 张图片"
    }

    // MARK: - 错误 (3 段式: 问题 + 原因 + 解决)

    /// 存储写入失败
    static let storageError = "无法保存图片到图库。请检查磁盘空间，或在「系统设置 → 隐私与安全 → 完整磁盘访问权限」中授权 ImageGallery，然后重试。"

    /// 导入文件失败
    static func importFailed(_ filename: String) -> String {
        "导入失败：\(filename)"
    }

    /// 导出文件失败
    static func exportFailed(_ filename: String) -> String {
        "导出失败：\(filename)"
    }

    /// 移到回收站失败
    static func moveToRecycleBinFailed(_ error: String) -> String {
        "移到回收站失败：\(error)"
    }

    /// 清空回收站失败
    static func emptyRecycleBinFailed(_ error: String) -> String {
        "清空回收站失败：\(error)"
    }

    /// 批量移到回收站失败
    static func batchMoveToRecycleBinFailed(_ error: String) -> String {
        "批量移到回收站失败：\(error)"
    }

    /// 批量评分失败
    static let batchRatingFailed = "批量评分失败"

    // MARK: - 空态 (含引导)

    /// 主内容空——图库无图片
    static let emptyLibrary = "图库还是空的"

    /// 主内容空——引导
    static let emptyLibraryHint = "把图片拖到这里，或点击 ⌘O 导入"

    /// 主内容空——回收站无图片
    static let emptyRecycleBin = "回收站是空的"

    /// 详情面板空——未选图
    static let selectAPhoto = "选择一张图片"

    /// 详情面板空——快捷键提示
    static let selectAPhotoHint = "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选"

    /// 缩略图加载失败
    static let thumbnailLoadFailed = "加载失败"

    // MARK: - 详情面板

    /// 详情面板大图位置 "1 / 5"
    static func photoPosition(current: Int, total: Int) -> String {
        "\(current) / \(total)"
    }

    /// 沉浸式大图位置 "1 / 5" (1-indexed)
    static func photoPosition1Indexed(current: Int, total: Int) -> String {
        "\(current) / \(total)"
    }

    /// 图片尺寸 "1920 × 1080"
    static func imageDimensions(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }

    /// 重命名提示
    static let renameHint = "给图片一个新名字（不包含扩展名）"

    /// 标签字段标签
    static let tagLabel = "标签"

    /// 标签空状态
    static let addTagHint = "点击 + 添加标签"

    /// 删除单图 Confirm 消息
    static let deleteConfirmMessage = "图片将从图库中移除，文件也会被永久删除。"

    /// 清空回收站 Confirm 消息
    static let emptyRecycleBinConfirm = "回收站里的所有照片将被永久删除，无法恢复。"

    /// 回收站列表 "回收站有 N 张"
    static func recycleBinCount(_ count: Int) -> String {
        "回收站有 \(count) 张"
    }

    // MARK: - 状态栏

    /// 状态栏图片总数
    static func totalCount(_ count: Int) -> String {
        "\(count) 张"
    }

    /// 状态栏已选数
    static func selectedCount(_ count: Int) -> String {
        "已选 \(count) 张"
    }

    /// 状态栏分隔符
    static let statusSeparator = "·"

    /// 缩略图剩余天数 badge "30" / "1"
    static func daysRemaining(_ days: Int) -> String {
        "\(days)"
    }

    // MARK: - 设置面板

    /// 视图模式——网格
    static let viewModeGrid = "网格"

    /// 视图模式——列表
    static let viewModeList = "列表"

    /// 视图模式——时间线
    static let viewModeTimeline = "时间线"

    /// 回收站保留时长说明
    static let recycleBinSubtitle = "删除的图片会先进入回收站，超过下面设置的天数后会被自动永久删除。"

    /// 缩略图大小设置预览
    static func thumbnailSizeLabel(_ size: Int) -> String {
        "\(size)"
    }

    // MARK: - 侧栏 / 按钮

    /// 新建文件夹
    static let newFolder = "新建文件夹"

    /// 新建标签
    static let newTag = "新建标签"

    /// 文件夹名输入框 placeholder
    static let folderNamePlaceholder = "文件夹名称"

    /// 通用按钮——取消
    static let cancel = "取消"

    /// 通用按钮——创建
    static let create = "创建"

    /// 通用按钮——确定
    static let confirm = "确定"

    /// 通用按钮——删除
    static let delete = "删除"

    // MARK: - 筛选

    /// 清除全部筛选
    static let clearAllFilters = "清除全部"

    // MARK: - 拖拽导入

    /// 拖拽释放提示
    static let dropReleaseToImport = "松开导入"

    /// 拖拽支持文件类型
    static let dropSupportedTypes = "支持图片文件 / 文件夹"
}

