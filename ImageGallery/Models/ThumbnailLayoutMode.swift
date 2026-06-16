//
//  ThumbnailLayoutMode.swift
//  ImageGallery
//
//  V6.12.12: 砍 .square 模式——5 commit 修不了 bug (.fill contentMode 下圆角/选中框)
//    V5.99.1 + V5.99.2 试过修圆角 + 选中框 (改 Radius.lg / 3pt stroke + tint)
//    V6.12.7 + V6.12.8 + V6.12.9 + V6.12.11 试过 cell bg 透明 / padding 4pt / 2pt 描边
//    V6.12.10 试过统一 contentMode = .fit (用户反对, 因为破坏 .square = .fill 裁切语义)
//    5 commit 全部失败, 用户决定: '取消按方格显示模式, 软件一直都改为按比例显示'
//    → 直接砍 .square case, 只保留 .squareFit (macOS Photos.app 真版)
//    → 所有 layoutMode 渲染分支变 trivial, 整 enum 简化为单 case
//
//  V5.17 → V5.47: 缩略图布局模式历史
//  - V5.17: .square (1:1 方格 + .fill 裁切 + cell card, iOS Photos.app Library 风格)
//  - V5.46: + .squareFit (1:1 方格 + .fit letterbox, macOS Photos.app 真版)
//  - V5.47: 砍 .masonry (justified row)——只留 .square / .squareFit 2 选项
//  - V6.12.12: 再砍 .square——只留 .squareFit (工作正常的模式)
//
//  V5.47 移除的 case:
//  - V6.12.12 移除的 case: .square (rawValue=0)
//    - 老用户 storedLayoutModeRaw=0 (曾选 square) → Settings.swift init() if 缺省 fallback .defaultValue (.squareFit)
//    - 老数据 rawValue=0 自动平滑回退到 .squareFit, 无需 migration
//    - 老数据 rawValue=1 (.masonry V5.47 已砍) → 已有 fallback .defaultValue 处理
//    - 老数据 rawValue=2 (.squareFit) → 直接用
//

import Foundation
import CoreGraphics

enum ThumbnailLayoutMode: Int, CaseIterable, Identifiable {
    case squareFit = 2  // macOS Photos.app 按比例真版 (1:1 方格 + .fit letterbox)
                        // V6.12.13 displayName "按比例" → "网格"
                        // V6.12.14 加 case .list 后, 不再是唯一选项
                        // V5.46 NEW + V5.47 rawValue=2 兼容 + V6.12.12 保留
    case list = 3       // V6.12.14 NEW: 用户 4 次请求 '布局模式加列表选项'
                        //   选中后自动切 viewMode = .list (ContentViewModel.onLayoutModeChange)
                        //   ThumbnailLayoutMode.list 不影响 grid 视图渲染——grid viewMode 强制切 .grid
                        //   是 toolbar layout picker 上 "列表" 按钮的 hook, 让用户无需记 ⌥2 快捷键
                        //   rawValue=3——避开已删 .square (0) + 已删 .masonry (1) + 现有 .squareFit (2)

    var id: Int { rawValue }

    /// V6.12.12: 唯一选项即 defaultValue
    ///   - 1:1 等大 cell + image letterbox (.fit, 不裁切)
    ///   - cell 无卡片背景 (透窗口色, V6.12.7)
    ///   - 每行每列 cell 中心完美对齐 (正方形 grid)
    ///   - 横向照片上下留 letterbox, 竖向照片左右留 letterbox, 1:1 square 填满
    ///   - macOS Photos.app Library 真版风格
    static let defaultValue: ThumbnailLayoutMode = .squareFit

    var displayName: String {
        switch self {
        // V6.12.13: "按比例" → "网格"——更准确
        //   当前 .squareFit 渲染 = 1:1 方格 (letterbox)——视觉上是"网格"布局
        //   "按比例" 名字误导 (用户以为是按 image 原比例渲染, 实际是按 1:1 网格 letterbox)
        //   跟 Photos.app / Finder / ViewMode.grid 命名一致
        //   之前 V5.47 '按比例' 是相对 .masonry '按比例满行'——V5.47 砍了 .masonry 后名字失去对比
        case .squareFit: return "网格"
        // V6.12.14: 新增 '列表' displayName
        //   用户 4 次请求 '布局模式加列表选项'——V6.12.14 落地
        //   语义上跟 ViewMode.list 重复——但用户视角: layout picker 有 list 就能切到 list 视图
        //   内部实现: 选中 .list → ContentViewModel 切 viewMode = .list
        case .list:       return "列表"
        }
    }

    /// V6.12.14: 2 case 后 icon 区分——square.grid.2x2 (grid) + list.bullet (list)
    var icon: String {
        switch self {
        case .squareFit: return "square.grid.2x2"
        case .list:      return "list.bullet"
        }
    }

    /// V6.12.14: 2 case 后 masonryParams——都返 rowHeight (1:1 方格)
    ///   .list 不影响 masonryParams (list view 不用 GridLayout)——保留 .squareFit 等价返回值
    ///   V5.39.5 简化 + V5.46 增 .squareFit 分支 + V5.47 删 .masonry 分支
    ///
    /// stretchLastRow 字段已删——所有模式末行都保持 targetRowHeight (左对齐, Photos Days 风格)
    ///
    /// - Parameter rowHeight: 行高 (= thumbnailSize)
    /// - Returns: uniformWidth (nil = 走 aspect-based 宽度, non-nil = 固定宽度)
    func masonryParams(rowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .squareFit: return rowHeight  // 1:1 方格, .fit letterbox
        case .list:      return rowHeight  // 不影响 GridLayout, 但保持 switch 完整性
        }
    }
}
