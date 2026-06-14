//
//  SidebarSelection.swift
//  ImageGallery
//
//  V5.51-1: 从 ContentView.swift 抽出——侧边栏选中项 enum
//  原位置 ContentView.swift:24-40
//  引用方：Views/SidebarView.swift / Views/DetailPane.swift /
//          Views/ContentKeyboardShortcuts.swift / SidebarSelectionTests
//

import Foundation

/// 侧边栏选中项类型
enum SidebarSelection: Hashable {
    case all
    // V5.7: 砍 .favorites——收藏 = 评分 ≥ 5，访问走筛选 popover
    //   侧边栏只放主导航，不再掺杂筛选视图
    case unfiled
    case duplicates

    // V2: 智能文件夹
    case recent7Days       // 最近 7 天导入
    case largeFiles        // 大图 > 5MB

    case folder(Folder)
    case tag(Tag)

    // V3.6 NEW: 回收站
    case recentlyDeleted
}
