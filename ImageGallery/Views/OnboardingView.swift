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
    // V6.32.2: 暗色模式感知 — inactive dot opacity
    @Environment(\.colorScheme) private var colorScheme

    /// V6.32.2: 暗色下 .secondary 更暗, 用 0.4 保持可见对比
    private var inactiveDotColor: Color {
        colorScheme == .dark ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.3)
    }

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            iconColor: .blue,
            title: Copy.onboardingImportTitle,
            subtitle: Copy.onboardingImportSubtitle,
            primaryHint: Copy.onboardingImportHint,
            primaryHintValue: "⌘O"  // shortcut glyph — 不本地化
        ),
        OnboardingPage(
            icon: "rectangle.dashed",
            iconColor: .purple,
            title: Copy.onboardingMarqueeTitle,
            subtitle: Copy.onboardingMarqueeSubtitle,
            primaryHint: Copy.onboardingMarqueeHint,
            primaryHintValue: Copy.onboardingMarqueeHintValue
        ),
        OnboardingPage(
            icon: "rotate.right",
            iconColor: .orange,
            title: Copy.onboardingMoreTitle,
            subtitle: Copy.onboardingMoreSubtitle,
            primaryHint: Copy.onboardingMoreHint,
            primaryHintValue: "⌘? / ⌘,"  // shortcut glyphs — 不本地化
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
            // V6.32.2: 暗色模式 — 暗色下 .secondary.opacity(0.3) 不够 visible (整体太暗),
            //   提升到 0.4 (暗色感知 .secondary 更暗, 需要更高 opacity 才能跟选中 dot 形成对比)
            HStack(spacing: 8) {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : inactiveDotColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: 16) {
                // V6.22.3: "跳过" — 用户可立即关闭
                Button(Copy.onboardingSkip) {
                    hasSeenOnboarding = true
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("onboarding.skipButton")  // V6.22.10 (XCUITest)

                Spacer()

                // V6.22.3: "上一步" / "下一步" 切换
                if currentPage > 0 {
                    Button(Copy.onboardingBack) {
                        withAnimation { currentPage -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Button(currentPage == Self.pages.count - 1 ? Copy.onboardingStart : Copy.onboardingNext) {
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