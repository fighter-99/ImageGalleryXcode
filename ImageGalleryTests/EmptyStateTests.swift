//
//  EmptyStateTests.swift
//  ImageGalleryTests
//
//  V4.9.0: EmptyStateView 单元测试——守护 V3.6.9 起的统一空状态组件
//  V6.61: 适配新 Style 枚举 (取代 iconColor) — Style 4 档 accent/neutral/warning/destructive
//  验证：
//  - Action struct 构造（必填 + 可选字段）
//  - 4 个场景的构造可用性（无 CTA / 仅主 CTA / 仅次 CTA / 主+次 CTA）
//  - style 默认值（accent）
//
//  6 个空状态场景（V4.9.0 覆盖 3 个）:
//  1. 无图片（首次启动）→ 导入图片 [PhotoGridView 路径]
//  2. 空相册 → 导入图片 + 查看全部 [PhotoGridView 路径]
//  3. 无搜索结果 → 清除搜索 + 查看全部 [PhotoGridView 路径]
//  4. 加载中 [未实现 - 留 V4.10]
//  5. 权限缺失 [未实现 - 留 V4.10]
//  6. 回收站为空 → 查看全部 [TrashDetailView 路径]
//

import Testing
import SwiftUI
@testable import ImageGallery

struct EmptyStateTests {

    // MARK: - EmptyStateView.Action 构造

    @Test func actionWithAllFields() {
        // 主 CTA 完整 3 字段：label + systemImage + onTap
        var tapped = false
        let action = EmptyStateView.Action(
            label: "导入图片",
            systemImage: "square.and.arrow.down"
        ) {
            tapped = true
        }
        #expect(action.label == "导入图片")
        #expect(action.systemImage == "square.and.arrow.down")
        action.onTap()
        #expect(tapped == true)
    }

    @Test func actionWithoutSystemImage() {
        // 次 CTA 可省 systemImage（V4.9.0 secondaryAction 用例）
        var tapped = false
        let action = EmptyStateView.Action(label: "查看全部") {
            tapped = true
        }
        #expect(action.label == "查看全部")
        #expect(action.systemImage == nil)
        action.onTap()
        #expect(tapped == true)
    }

    // MARK: - EmptyStateView 4 个场景构造

    @Test func emptyStateWithoutActions() {
        // 场景: 简单空状态（如 EmptyDetailView "选择一张图片"）
        let view = EmptyStateView(
            icon: "photo",
            title: "选择一张图片",
            subtitle: "← → 切换 · ⌘+点击 多选"
        )
        #expect(view.icon == "photo")
        #expect(view.title == "选择一张图片")
        #expect(view.subtitle == "← → 切换 · ⌘+点击 多选")
        #expect(view.primaryAction == nil)
        #expect(view.secondaryAction == nil)
        #expect(view.style == .accent)  // 默认值
    }

    @Test func emptyStateWithPrimaryActionOnly() {
        // 场景: 首次启动 / 收藏空 → 单一主 CTA
        var tapped = false
        let view = EmptyStateView(
            icon: "photo.on.rectangle.angled",
            title: "还没有图片",
            subtitle: "拖入图片，或点击下方按钮开始添加",
            primaryAction: EmptyStateView.Action(
                label: "导入图片",
                systemImage: "square.and.arrow.down"
            ) { tapped = true }
        )
        #expect(view.primaryAction != nil)
        #expect(view.secondaryAction == nil)
        #expect(view.primaryAction?.label == "导入图片")
        view.primaryAction?.onTap()
        #expect(tapped == true)
    }

    @Test func emptyStateWithSecondaryActionOnly() {
        // 场景: 某些空状态只有次 CTA（如错误占位 "重试"）
        var tapped = false
        let view = EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "出错了",
            subtitle: "请重试或返回",
            style: .warning,
            secondaryAction: EmptyStateView.Action(
                label: "重试",
                systemImage: "arrow.clockwise"
            ) { tapped = true }
        )
        #expect(view.primaryAction == nil)
        #expect(view.secondaryAction != nil)
        #expect(view.secondaryAction?.label == "重试")
        #expect(view.style == .warning)
        view.secondaryAction?.onTap()
        #expect(tapped == true)
    }

    @Test func emptyStateWithBothActions() {
        // 场景: 无搜索结果 / 空 folder → 主 + 次 CTA
        var primaryTapped = false
        var secondaryTapped = false
        let view = EmptyStateView(
            icon: "magnifyingglass",
            title: "没有匹配的照片",
            subtitle: "试试其他关键词，或清除搜索",
            primaryAction: EmptyStateView.Action(
                label: "清除搜索",
                systemImage: "xmark.circle"
            ) { primaryTapped = true },
            secondaryAction: EmptyStateView.Action(
                label: "查看全部"
            ) { secondaryTapped = true }
        )
        #expect(view.primaryAction?.label == "清除搜索")
        #expect(view.secondaryAction?.label == "查看全部")
        #expect(view.secondaryAction?.systemImage == nil)  // 次 CTA 可省 systemImage
        view.primaryAction?.onTap()
        #expect(primaryTapped == true)
        view.secondaryAction?.onTap()
        #expect(secondaryTapped == true)
    }

    // MARK: - Style 定制 (V6.61 取代 iconColor)

    @Test func emptyStateWithCustomStyle() {
        // 场景: 错误状态用 destructive，警示状态用 warning
        let errorView = EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "权限不足",
            style: .destructive
        )
        #expect(errorView.style == .destructive)

        let warningView = EmptyStateView(
            icon: "trash",
            title: "回收站是空的",
            style: .warning
        )
        #expect(warningView.style == .warning)

        let neutralView = EmptyStateView(
            icon: "tray",
            title: "未分类文件夹",
            style: .neutral
        )
        #expect(neutralView.style == .neutral)
    }

    // MARK: - 6 个空状态场景文档（V4.9.0 覆盖）

    @Test func sixScenariosDocumented() {
        // V4.9.0 覆盖 3 个场景（无图片/空相册/无搜索结果 + 回收站空 = 4 个）
        // 加载中（场景 4）和权限缺失（场景 5）留 V4.10

        // 场景 1: 无图片（首次启动）
        // EmptyStateView + primaryAction: 导入图片

        // 场景 2: 空相册/标签
        // EmptyStateView + primaryAction: 导入图片 + secondaryAction: 查看全部

        // 场景 3: 无搜索结果
        // EmptyStateView + primaryAction: 清除搜索 + secondaryAction: 查看全部

        // 场景 6: 回收站为空（TrashDetailView count==0）
        // EmptyStateView + primaryAction: 查看全部

        // 场景 4: 加载中 - V4.10
        // 场景 5: 权限缺失 - V4.10

        // 此测试不验证逻辑（无 SwiftData）——只守护 6 个场景的"工程记忆"
        // 真正的功能验证靠 V4.9.0 commit message + 截图
        let coveredScenarios = 4
        let totalScenarios = 6
        #expect(coveredScenarios == 4, "V4.9.0 覆盖 4/6 场景，加载中+权限缺失留 V4.10")
        #expect(totalScenarios == 6, "总共 6 个空状态场景")
    }
}
