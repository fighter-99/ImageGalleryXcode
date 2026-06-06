//
//  ImageGalleryApp.swift
//  ImageGallery
//
//  应用入口。注册 SwiftData 容器、设置 AppDelegate、加 View 菜单。
//

import SwiftUI
import AppKit
import SwiftData

// AppDelegate：处理应用层 macOS 事件
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct ImageGalleryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // View 菜单的 Toggle 通过 UserDefaults binding 与 ContentView 共享
    // （@AppStorage 重复定义被移除——ContentView 是唯一持有者，菜单项通过 Binding<Bool>(userDefaults:) 监听）
    private let showSidebarBinding = Binding<Bool>(userDefaults: "showSidebar", default: true)
    private let showDetailBinding  = Binding<Bool>(userDefaults: "showDetail",  default: true)

    var body: some Scene {
        // V3.5.D：WindowGroup 加 id 让 macOS 能稳定追踪窗口(用于 frame autosave)
        // 同时加 defaultSize 给首次启动一个合理尺寸
        WindowGroup("我的图馆", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)  // V3.5.D：首次启动合理尺寸
        .modelContainer(for: [Photo.self, Folder.self, Tag.self])
        .commands {
            // macOS 原生 View 菜单（在 View 菜单里加 Toggle 项）
            CommandGroup(after: .sidebar) {
                Toggle("显示侧边栏", isOn: showSidebarBinding)
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Toggle("显示详情面板", isOn: showDetailBinding)
                    .keyboardShortcut("d", modifiers: [.command, .control])
            }
            // V3.5.D：App 菜单的"设置..."项（macOS 标准位置 + ⌘, 快捷键）
            CommandGroup(after: .appInfo) {
                Button("设置…") {
                    NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - 通知名（V3.5.D 新增）
//
// 菜单栏的"设置..."按钮发通知，ContentView 监听后弹出 SettingsView sheet。
extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

// MARK: - UserDefaults Binding 辅助（V3.5.18：去掉 @AppStorage 重复）
//
// 让 View 菜单的 Toggle 也能绑定 UserDefaults key，但不需要在 App 里再 @AppStorage 一次。
// ContentView 是 key 的唯一持有者；这里只是监听同一个 key。
extension Binding where Value == Bool {
    init(userDefaults key: String, default defaultValue: Bool) {
        self.init(
            get: { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }
}
