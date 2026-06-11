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

    // V3.6.7: 手动建 ModelContainer（SwiftData 26.5 SDK 的 modelContainer modifier 没 VersionedSchema 重载）
    let modelContainer: ModelContainer

    init() {
        // V3.6.7: 显式 VersionedSchema + MigrationPlan
        // 之前用 [Photo.self, Folder.self, Tag.self] 隐式 schema，依赖 SwiftData 轻量级自动迁移
        // 显式后：schema 版本可追溯 + 未来加字段有安全迁移路径
        let schema = Schema(versionedSchema: ImageGallerySchemaV1.self)
        // ModelConfiguration() 默认值：sqlite store 在 Application Support/ 目录
        modelContainer = try! ModelContainer(
            for: schema,
            migrationPlan: ImageGalleryMigrationPlan.self,
            configurations: ModelConfiguration()
        )
    }

    // View 菜单的 Toggle 通过 UserDefaults binding 与 ContentView 共享
    // （@AppStorage 重复定义被移除——ContentView 是唯一持有者，菜单项通过 Binding<Bool>(userDefaults:) 监听）
    private let showSidebarBinding = Binding<Bool>(userDefaults: "showSidebar", default: true)
    private let showDetailBinding  = Binding<Bool>(userDefaults: "showDetail",  default: true)

    var body: some Scene {
        // V3.5.D：WindowGroup 加 id 让 macOS 能稳定追踪窗口(用于 frame autosave)
        // 同时加 defaultSize 给首次启动一个合理尺寸
        // V4.0.0: 加 .windowToolbarStyle(.unified) + .windowStyle(.hiddenTitleBar)——
        //   原生 toolbar 半透明材质 + 隐藏 title bar 让 toolbar 延伸到顶部
        // V4.0.0.1: 改 .unified → .unifiedCompact——blur 太重与图标不和谐，
        //   unified 风格让背景抢戏；compact 更"贴底"，让 icon 主导
        //   （参考 Photos.app / Things / Bear：toolbar 是 backdrop，icon 才是主角）
        // V4.7.5: 探索 .unified 回归（去掉 compact）试图解决 .principal section 背景
        // V4.7.6: 回滚 V4.7.5——.unifiedCompact 与 .unified 都会给 .principal 加 section 背景
        //   根本解法：5 actions 改 .primaryAction placement（不再使用 .principal）
        //   .primaryAction 在 .unifiedCompact 下也不会被加 section 背景
        //   回归 V4.0.0.1 的 .unifiedCompact（blur 轻，符合"toolbar 是 backdrop"原意）
        WindowGroup("我的图馆", id: "main") {
            ContentView()
        }
        // V4.1.0 m: 默认 1280×800；contentMinSize 由 layout 决定
        //   侧栏 160pt + 工具栏 200pt + grid 400pt + 详情 320pt = 1080pt 横向最小
        //   纵向 toolbar 30 + 状态栏 24 + grid 200 = 254pt 最小
        //   13" MacBook (1280×800) 能完整用；更小屏幕 contentMinSize 会兜底
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)            // V4.0.0: 合并 title bar + toolbar
        // V4.8.0: 删 .windowToolbarStyle——NSToolbar 在 ContentView.configureNSToolbar
        //   直接设置 window.toolbarStyle = .unified（避免双重设置冲突）
        .modelContainer(modelContainer)  // V3.6.7：显式 VersionedSchema 容器
        // V4.13.0: macOS 标准 ⌘, 行为——独立 Preferences 窗口（不是 sheet）
        //   之前 V3.5.D 用 NotificationCenter + sheet 弹在主窗口内——与 Photos/Finder
        //   标准 ⌘, 行为不符（标准是独立 Preferences window，无交通灯，title = app name）
        //   Settings scene (macOS 13+) 自动绑定 ⌘, + SettingsLink (macOS 14+)
        Settings {
            SettingsView()
        }
        .commands {
            // macOS 原生 View 菜单（在 View 菜单里加 Toggle 项）
            CommandGroup(after: .sidebar) {
                Toggle("显示侧边栏", isOn: showSidebarBinding)
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Toggle("显示详情面板", isOn: showDetailBinding)
                    .keyboardShortcut("d", modifiers: [.command, .control])
            }
            // V4.13.0: 用 SettingsLink 触发 Settings scene（macOS 14+ 标准 API）
            //   自动绑定 ⌘,（之前 V3.5.D 手动 keyboardShortcut 已被系统接管）
            //   撤回 V3.5.D 旧方案：NotificationCenter + ContentView sheet 路径
            //   （applySettingsChrome extension 内 sheet 路径待 ContentView 清理）
            CommandGroup(after: .appInfo) {
                SettingsLink {
                    Text("设置…")
                }
            }
            // V4.7.0 NEW: Undo/Redo Edit menu 集成
            //   CommandGroup(replacing: .undoRedo) 替换系统默认 Undo/Redo（macOS 标准位置）
            //   之前 ⌘Z/⌘⇧Z 由 ContentKeyboardShortcuts.swift 里的 hidden Button 处理
            //   现在用 .keyboardShortcut 绑到菜单项——系统接管，原 hidden Button 移除
            CommandGroup(replacing: .undoRedo) {
                UndoRedoMenuButtons()
            }
        }
    }
}

// MARK: - 通知名（V3.5.D 新增）
//
// 菜单栏的"设置..."按钮发通知，ContentView 监听后弹出 SettingsView sheet。
extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    // V3.6.23: ⌘F 聚焦搜索框通知（ContentKeyboardShortcuts 发，ToolbarView 收）
    static let focusSearchField = Notification.Name("focusSearchField")
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

// MARK: - V4.7.0 NEW: Undo/Redo Edit menu 按钮
//
// 接收 ContentView 通过 .focusedSceneValue 暴露的 undoManager。
// 菜单 label 动态显示最近一次 action 描述（"撤销 删除选中"、"重做 添加标签"等），
// 与 macOS Photos / Finder / TextEdit 风格一致。
//
// canUndo/canRedo 状态联动 disable——无 undo 栈时菜单项灰显。
//
// ⌘Z / ⌘⇧Z 快捷键绑在菜单项上（V4.7.0 之前是 ContentKeyboardShortcuts.swift
// 里的 hidden Button）。两边并存会双重触发——所以 hidden Button 已移除。
//
struct UndoRedoMenuButtons: View {
    @FocusedValue(\.imageGalleryUndoManager) private var undoManager

    var body: some View {
        // 撤销——label 动态化（"撤销" + 最近 action 描述）
        Button(undoLabel) {
            undoManager?.undo()
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(undoManager?.canUndo != true)

        // 重做——label 动态化（"重做" + 最近 action 描述）
        Button(redoLabel) {
            undoManager?.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(undoManager?.canRedo != true)
    }

    /// "撤销 <action>"——无 action 时仅 "撤销"
    private var undoLabel: String {
        guard let desc = undoManager?.undoDescription, !desc.isEmpty else { return "撤销" }
        return "撤销 \(desc)"
    }

    /// "重做 <action>"——无 action 时仅 "重做"
    private var redoLabel: String {
        guard let desc = undoManager?.redoDescription, !desc.isEmpty else { return "重做" }
        return "重做 \(desc)"
    }
}
