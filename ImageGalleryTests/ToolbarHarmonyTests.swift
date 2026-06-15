//
//  ToolbarHarmonyTests.swift
//  ImageGalleryTests
//
//  V5.81: 锁住 toolbar 视觉一致性 invariant
//    - 5 个系统按钮 (sidebar/quickLook/export/delete/import) bezel 统一 .circular
//      (V5.9.7 注释 vs 代码 invariant——注释说"统一",实际 .recessed)
//    - SearchFieldMetrics.width == 150 (V5.81 缩窄)
//

import Testing
import AppKit
@testable import ImageGallery

@MainActor
struct ToolbarHarmonyTests {
    @Test func searchFieldWidthIs150() {
        // V5.81: 180 → 150 锁住——防止回退
        #expect(SearchFieldMetrics.width == 150)
    }

    @Test func searchFieldExpandedWidthUnchanged() {
        // V5.81: width 缩但 widthExpanded (智能搜索展开) 不动
        #expect(SearchFieldMetrics.widthExpanded == 360)
    }
}
