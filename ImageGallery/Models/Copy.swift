//
//  Copy.swift
//  ImageGallery
//
//  V5.50-2 NEW: 微文案字典 (microcopy dictionary)——所有用户可见字符串统一收纳
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
//    - V5.50-3 (下次 sprint) 文本改动先查此表
//
//  不动:
//    - swift string interpolation 行为 (V5.50-2 之前用 "\(count) 张图片" 散落 6+ 处)
//    - 未来 i18n 时直接换成 NSLocalizedString (V5.52 String Catalog 准备)
//

import Foundation

/// V5.50-2: 微文案字典——所有用户可见字符串统一来源
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

    /// 详情面板空——未选图
    static let selectAPhoto = "选择一张图片"

    /// 详情面板空——快捷键提示
    static let selectAPhotoHint = "← → 切换 · ⌘+点击 多选 · ⌥+拖动 框选"

    /// 缩略图加载失败
    static let thumbnailLoadFailed = "加载失败"

    /// 缩略图剩余天数
    static func daysRemaining(_ days: Int) -> String {
        "\(days)"
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
}
