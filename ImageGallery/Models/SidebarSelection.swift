//
//  SidebarSelection.swift
//  ImageGallery
//
//  V5.51-1: 从 ContentView.swift 抽出——侧边栏选中项 enum
//  原位置 ContentView.swift:24-40
//  引用方：Views/SidebarView.swift / Views/DetailPane.swift /
//          Views/ContentKeyboardShortcuts.swift / SidebarSelectionTests
//
//  V6.08: .folder(Folder) / .tag(Tag) 改 .folder(UUID) / .tag(UUID)
//    之前直接存 SwiftData @Model 引用, folder/tag 删除后 sidebarSelection
//    仍引用已删除对象——访问 currentFolder 会 crash / KVO 失效
//    现在存 UUID, 每次访问 currentFolder/currentTag 从 modelContext 重新 fetch
//    自动反映删除状态 (fetch 不存在 → nil → 切回 .all)
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

    // V6.08: UUID 而非 @Model 引用——避免 dangling reference
    // 访问时 ContentViewModel.currentFolder/currentTag 从 modelContext fetch
    case folder(UUID)
    case tag(UUID)

    // V3.6 NEW: 回收站
    case recentlyDeleted
}
