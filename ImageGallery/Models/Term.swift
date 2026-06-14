//
//  Term.swift
//  ImageGallery
//
//  V5.51 NEW: 术语字典 (terminology dictionary)——所有用户可见"专有名词"统一收纳
//
//  V4.36.x 沉淀 (image-gallery-text-consistency.md) 已有 21 处修复决策:
//    - "图库" (不用 "图馆"——V4.36.x typo 至今未全清, V5.51 二次修正)
//    - "回收站" (不用 "垃圾箱")
//    - "图片" (不用 "照片"——跟系统 Photos.app 区分)
//
//  V5.44-4 设计原则 (4 选 1 收敛):
//    1. **专有名词进字典**——"图库/回收站/图片/照片" 等术语
//    2. **量词进字典**——"张" / "天" / "MB" 等
//    3. **格式进 Copy**——数字 + 量词组合 ("N 张", "N 天")——Copy 字典管
//    4. **DisplayName 走 enum 自身**——ViewMode.displayName / ThumbnailLayoutMode.displayName 已自带
//
//  镜像 pattern (仿 V5.45 Typography 6 token + V5.50-2 Copy 微文案):
//    - 单一真相源——改一处全改
//    - V5.51 之后新增 UI 文本先查 Term 字典
//    - 未来 i18n 时直接换 Term.xxx 为 NSLocalizedString
//
//  V5.51 实际修的 typo (顺手清):
//    - DetailView.swift:139 "图馆" → "图库" (V4.36.x typo)
//    - SidebarView.swift:250 "图馆" → "图库" (V4.36.x typo)
//
//  不动:
//    - swift identifier (枚举 case / func 名 / 变量名)——Term 只管用户可见字符串
//    - URL path / UserDefaults key——跟 i18n 无关
//    - 注释里的术语——Term 字典没法控制注释
//

import Foundation

/// V5.51: 术语字典——所有用户可见"专有名词"统一来源
///
/// 引用方式 (仿 V5.45 Typography 模式):
/// ```swift
/// Text("Hello \(Term.library)")      // 不用 Text("Hello 图库")
/// Text("\(count) \(Term.countUnit)")  // 不用 Text("\(count) 张")
/// ```
enum Term {
    // MARK: - 专有名词

    /// "图库"——不用 "图馆" (V4.36.x typo, V5.51 二次修正)
    static let library = "图库"

    /// "图片"——不用 "照片" (跟系统 Photos.app 区分, 减少概念混淆)
    static let photo = "图片"

    /// "回收站"——不用 "垃圾箱" (V4.36.x 决策, 跟 macOS Finder "废纸篓" 概念一致)
    static let recycleBin = "回收站"

    // MARK: - 量词

    /// "张"——图片计数单位 (不混用 "个")
    static let countUnit = "张"

    /// "天"——保留时长单位 (不混用 "日")
    static let dayUnit = "天"
}
