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
    case squareFit = 2  // V6.12.12: 砍 .square 后唯一选项 (macOS Photos.app 按比例真版)
                        //   V5.46 NEW: macOS Photos.app 按比例 真版 (1:1 方格 + .fit letterbox)
                        //   V5.47: rawValue 保持 2 (不重排)——兼容 V5.46 老用户
                        //   V5.47: displayName 从 '方格 (完整)' 改成 '按比例' (因为 V5.47 砍了原 .masonry '按比例')
                        // V6.12.12: 仍保留 rawValue=2——不重排避免老 UserDefaults 数据迁移
                        //   老 rawValue=0 (.square) 用户会自动 fallback 到 .defaultValue (.squareFit)

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
        // V5.47: 原 '方格 (完整)' 改成 '按比例'——用户决定 .squareFit 才是 macOS Photos 真版
        //   之前 .masonry (justified row) 占用了 '按比例' 名字——V5.47 砍 .masonry 后名字空出来
        //   现在 '按比例' 语义更准确: image 按原比例 letterbox 进 1:1 cell
        case .squareFit: return "按比例"
        }
    }

    /// V6.12.12: 单 case 后 icon 简化——只 1 个选项, 不需区分密度
    var icon: String {
        switch self {
        case .squareFit: return "square.grid.2x2"
        }
    }

    /// V6.12.12: 单 case 后 masonryParams 简化——总是 rowHeight (1:1 方格)
    ///   V5.39.5 简化 + V5.46 增 .squareFit 分支 + V5.47 删 .masonry 分支
    ///   - .square:    uniformWidth = rowHeight (方形 cell, MasonryMath 用, .fill 裁切)
    ///   - .squareFit: uniformWidth = rowHeight (方形 cell, MasonryMath 用, .fit letterbox, V5.47 无 cell card)
    ///   - V6.12.12: 砍 .square 后只剩 .squareFit——总是 rowHeight
    ///
    /// stretchLastRow 字段已删——所有模式末行都保持 targetRowHeight (左对齐, Photos Days 风格)
    ///
    /// - Parameter rowHeight: 行高 (= thumbnailSize)
    /// - Returns: uniformWidth (nil = 走 aspect-based 宽度, non-nil = 固定宽度)
    func masonryParams(rowHeight: CGFloat) -> CGFloat? {
        switch self {
        case .squareFit: return rowHeight  // 1:1 方格, .fit letterbox
        }
    }
}
