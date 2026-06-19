//
//  OnboardingView.swift
//  ImageGallery
//
//  V6.22.3 (P2 #10): First-run onboarding 3-card sheet
//   - Photos.app 范式: 首次启动弹 3 张功能卡片
//   - 用户可 ⇧ 跳过, 但默认 welcome tour
//   - hasSeenOnboarding 持久化, 只显示一次
//   - 关闭后不再出现 (除非 Settings 重置)
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            iconColor: .blue,
            title: "导入你的照片",
            subtitle: "支持 JPG、PNG、HEIC、TIFF 等常见格式\n拖入文件夹即可批量导入，或按 ⌘O 选择文件",
            primaryHint: "导入快捷键",
            primaryHintValue: "⌘O"
        ),
        OnboardingPage(
            icon: "rectangle.dashed",
            iconColor: .purple,
            title: "拖动鼠标框选多张照片",
            subtitle: "在空白处按下左键拖动，可一次性选择一片区域内的所有照片\n类似 macOS Finder 和 Photos.app 的交互",
            primaryHint: "尝试",
            primaryHintValue: "空白处拖动"
        ),
        OnboardingPage(
            icon: "rotate.right",
            iconColor: .orange,
            title: "更多功能",
            subtitle: "右键图片可看到分享、旋转、评分等操作\n按 ⌘? 查看所有快捷键，按 ⌘, 打开设置",
            primaryHint: "快捷键",
            primaryHintValue: "⌘? / ⌘,"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // V6.22.3: TabView macOS 14+ 也支持 .page, 但 indexViewStyle 在 macOS 不支持
            //   用 custom page indicator — 3 个圆点, 当前 active 实心
            TabView(selection: $currentPage) {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    OnboardingPageView(page: Self.pages[index])
                        .tag(index)
                        .padding(.horizontal, 60)
                }
            }

            // V6.22.3: 自定义 page indicator (macOS 适配)
            //   TabView content + 底部 dots, 类似 iOS page indicator 风格但用 SwiftUI
            HStack(spacing: 8) {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: 16) {
                // V6.22.3: "跳过" — 用户可立即关闭
                Button("跳过") {
                    hasSeenOnboarding = true
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("onboarding.skipButton")  // V6.22.10 (XCUITest)

                Spacer()

                // V6.22.3: "上一步" / "下一步" 切换
                if currentPage > 0 {
                    Button("上一步") {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Button(currentPage == Self.pages.count - 1 ? "开始使用" : "下一步") {
                    if currentPage == Self.pages.count - 1 {
                        hasSeenOnboarding = true
                    } else {
                        withAnimation { currentPage += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.startButton")  // V6.22.10 (XCUITest)
            }
            .padding(20)
        }
        .frame(width: 640, height: 460)
        // V6.22.3: .sheet present 时用 environment dismiss
        //   hasSeenOnboarding binding 让 ContentView 在用户点 "开始使用" / "跳过" 时 dismiss
    }
}

/// V6.22.3: 单卡片 — icon + title + subtitle + hint badge
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.icon)
                .font(.system(size: 64, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(page.iconColor)
                .accessibilityHidden(true)  // title 已经描述了功能

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            // V6.22.3: 底部 hint badge — 提示快捷键
            //   类似 Photos.app / Things.app 的 "Pro tip" 风格
            HStack(spacing: 8) {
                Text(page.primaryHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(page.primaryHintValue)
                    .font(.caption.weight(.medium).monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// V6.22.3: 单页 content model
private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let primaryHint: String
    let primaryHintValue: String
}