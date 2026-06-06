//
//  ImageGalleryTests.swift
//  ImageGalleryTests
//
//  V3.5.D：测试 target 入口文件。
//  这里只放最基础的"环境就绪"测试,具体业务测试在各自的专门文件里。
//

import Testing
@testable import ImageGallery

struct ImageGalleryTests {
    /// 验证测试 target 能正常导入 ImageGallery 模块 + DesignTokens 加载
    @Test func designTokensLoad() {
        // 访问 Surface 触发 DesignTokens 模块初始化
        let surface = Surface.canvas
        let accent = AccentColor.system
        _ = surface
        _ = accent
    }
}

