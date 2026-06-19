//
//  ImageGalleryApp.swift
//  ImageGallery
//
//  应用入口。注册 SwiftData 容器、设置 AppDelegate、加 View 菜单。
//

import SwiftUI
import AppKit
import SwiftData
import Combine  // V4.36.x: 保留——HistoryStore/ImageGalleryUndoManager 等用 @Published
import os  // V6.08: ModelContainer 启动失败 log

// MARK: - P4.2: 通知名 (File 菜单 ⌘⇧R → ContentView batchRenameSheet 监听)
// V6.19.0 (P0 #1): 加 .shareRequested 通知 (File 菜单 ⌘⇧E → ContentView 弹 NSSharingServicePicker)
// V6.19.5 (P0 #16): 加 .newFolderRequested + .speakRequested (新文件夹菜单 + Speech 朗读)
extension Notification.Name {
    static let showBatchRenameSheet = Notification.Name("com.iridescent.ImageGallery.showBatchRenameSheet")
    static let shareRequested = Notification.Name("com.iridescent.ImageGallery.shareRequested")
    static let newFolderRequested = Notification.Name("com.iridescent.ImageGallery.newFolderRequested")
    static let speakRequested = Notification.Name("com.iridescent.ImageGallery.speakRequested")
}

// AppDelegate：处理应用层 macOS 事件
// V3.7.1 重写: 自实现窗口 frame 持久化 (替换 V6.12.6 的 setFrameAutosaveName, 不 work)
//   - 原因: setFrameAutosaveName 在 SwiftUI Scene 创建的 NSWindow 不生效
//     (SwiftUI 自己管 frame state, AppKit autosave 绑不住)
//   - 修法: NSWindowDelegate 监 windowDidResize/windowDidMove 写 UserDefaults
//     + applicationDidFinishLaunching 读 UserDefaults setFrame 恢复
//   - 4 个 key (size.w/h, position.x/y) — 简单, 不污染其他 key
//   - Photos.app / Finder / Safari 标准行为: 关在哪开回来还在哪
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // V3.7.1: frame 持久化 4 个 key
    private static let sizeWKey = "imageGalleryWindowSizeW"
    private static let sizeHKey = "imageGalleryWindowSizeH"
    private static let posXKey = "imageGalleryWindowPosX"
    private static let posYKey = "imageGalleryWindowPosY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // V6.22.10 (XCUITest): UI test launch arg 解析 — 在 setUp/tearDown 之前清 UserDefaults
        //   launch arg 在 appDidFinishLaunching 早期解析, 比 UserSettings init 早
        //   XCUITest 不能从 app 外部 reset UserDefaults, 必须 launch 时带 arg
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-reset-all") {
            let domain = Bundle.main.bundleIdentifier ?? ""
            UserDefaults.standard.removePersistentDomain(forName: domain)
            NSLog("V6.22.10: reset UserDefaults domain=\(domain) for XCUITest")
        }
        if args.contains("-uitest-reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
            NSLog("V6.22.10: reset hasSeenOnboarding for XCUITest")
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // V3.7.1: 挂 NSWindowDelegate 到所有 window + 恢复 stored frame
        //   SwiftUI Scene 创建的 NSWindow 在 applicationDidFinishLaunching 之后
        //   用 DispatchQueue.main.async 延迟到下一个 runloop, 拿得到 NSApp.windows
        DispatchQueue.main.async { [weak self] in
            self?.attachToAllWindows()
        }
    }

    private func attachToAllWindows() {
        for window in NSApp.windows {
            attach(to: window)
        }
    }

    private func attach(to window: NSWindow) {
        // 防止重复挂同一个 delegate (避免循环)
        if window.delegate === self { return }
        window.delegate = self
        // 应用 stored frame (启动恢复)
        applyStoredFrameIfAny(to: window)
    }

    private func applyStoredFrameIfAny(to window: NSWindow) {
        let defaults = UserDefaults.standard
        // 4 个 key 都要有才认为 stored frame 有效 (避免用 defaultSize 数据意外恢复)
        guard let w = defaults.object(forKey: Self.sizeWKey) as? Double,
              let h = defaults.object(forKey: Self.sizeHKey) as? Double,
              let x = defaults.object(forKey: Self.posXKey) as? Double,
              let y = defaults.object(forKey: Self.posYKey) as? Double else {
            return
        }
        // 验证 frame 合理 (e.g. 不超出屏幕)
        let frame = NSRect(x: x, y: y, width: w, height: h)
        // 屏幕可见性 check: 至少部分在主屏上
        guard let mainScreen = NSScreen.main else { return }
        let screenFrame = mainScreen.visibleFrame
        let intersection = frame.intersection(screenFrame)
        // 至少 50pt 宽 + 50pt 高 visible — 否则 frame 几乎全在屏幕外, 不恢复
        guard intersection.width > 50, intersection.height > 50 else { return }
        window.setFrame(frame, display: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - V3.7.1: NSWindowDelegate — 监听 window 变化 + 写 UserDefaults

    func windowDidResize(_ notification: Notification) {
        saveFrame(from: notification.object as? NSWindow)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(from: notification.object as? NSWindow)
    }

    private func saveFrame(from window: NSWindow?) {
        guard let window else { return }
        let frame = window.frame
        let defaults = UserDefaults.standard
        defaults.set(frame.size.width, forKey: Self.sizeWKey)
        defaults.set(frame.size.height, forKey: Self.sizeHKey)
        defaults.set(frame.origin.x, forKey: Self.posXKey)
        defaults.set(frame.origin.y, forKey: Self.posYKey)
    }
}

@main
struct ImageGalleryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // V3.6.7: 手动建 ModelContainer（SwiftData 26.5 SDK 的 modelContainer modifier 没 VersionedSchema 重载）
    let modelContainer: ModelContainer

    // V5.59-3: 单一 shared UserSettings 实例——@State 生命周期 = app 生命周期
    //   ContentView/ContentViewModel/SettingsView/menu commands 全部走这同一实例
    //   UserSettings.init() V5.58-1 从 UserDefaults 读 13 字段
    @State private var sharedSettings = UserSettings()

    // V5.60-7: ⌘? cheat sheet 状态——sheet 模式弹 KeyboardShortcutsSheet
    @State private var showShortcutsSheet = false

    init() {
        // V3.6.7: 显式 VersionedSchema + MigrationPlan
        // 之前用 [Photo.self, Folder.self, Tag.self] 隐式 schema，依赖 SwiftData 轻量级自动迁移
        // 显式后：schema 版本可追溯 + 未来加字段有安全迁移路径
        let schema = Schema(versionedSchema: ImageGallerySchemaV1.self)
        // ModelConfiguration() 默认值：sqlite store 在 Application Support/ 目录
        let config = ModelConfiguration()
        // V6.08: try! → do/catch + 自动重置 store——SwiftData 损坏 / schema 不兼容自愈
        //   之前: try! 启动崩溃, 用户被迫用 terminal 删 store 文件
        //   现在: 第一次失败删 store 重试, 绝大多数 schema 损坏情况自动恢复
        //   二次失败才 fatalError (OS-level 完全不可用: 磁盘满 / 权限完全拒绝)
        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: ImageGalleryMigrationPlan.self,
                configurations: config
            )
        } catch {
            Self.logger.error("ModelContainer 启动失败, 尝试重置 store: \(String(describing: error))")
            // V6.12: do/catch 替 try? removeItem——sandbox 权限 / 文件占用 / ACL 时
            //   删除静默失败, 下次 try ModelContainer 撞同一个 corrupt 文件, fatalError
            //   V6.08 commit 当时吞错 (OS-level 完全不可用就走 fatalError 提示用 terminal),
            //   实际 silent 失败让用户/开发者失去诊断线索。Logger.error 至少留线索
            do {
                try FileManager.default.removeItem(at: config.url)
                Self.logger.info("旧 store 删除成功: \(config.url.lastPathComponent, privacy: .public)")
            } catch {
                Self.logger.error("旧 store 删除失败: \(error.localizedDescription, privacy: .public) — 重试 ModelContainer 仍可能撞同文件")
            }
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: ImageGalleryMigrationPlan.self,
                    configurations: config
                )
                Self.logger.info("ModelContainer 重置成功, 旧 store 已删")
            } catch {
                // V6.22.5: fatalError 前加 .critical 级 logger (bug-scan HIGH → 但 V6.08 设计
                //   保留 fatalError, 给终端用户的"删除 store 文件"指引)
                //   logger.critical 输出到 Console.app 便于远程诊断
                Self.logger.critical("ModelContainer 重置后仍失败 (OS-level 完全不可用): \(String(describing: error), privacy: .public)")
                // bug-scan-allow: V6.08 设计 — SwiftData 完全不可用是 OS-level 不可恢复,
                //   fatalError 是最后一道防线引导用户去 terminal 删 store 文件
                fatalError("ModelContainer 重置后仍失败: \(String(describing: error))")
            }
        }
    }

    private static let logger = Logger(subsystem: "com.imagegallery.app", category: "App")

    // V5.59-3: 删 3 个 userDefaults-based bindings (showSidebarBinding/showDetailBinding/viewModeBinding)
    //   menu items 现在改用 $sharedSettings.X (V5.59-3 下面命令)——
    //   @Observable sharedSettings 自动广播, menu 改 → ContentView/SettingsView 即时同步
    //   删下面 extension Binding<Bool>(userDefaults:) helper (L185-191)——不再用

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
        // V5.51: "图馆" → "图库" typo 修复 + 走 Term.library 字典
        // V5.59-3: ContentView 传 sharedSettings——与 menu/SettingsView 共享同一 UserSettings 实例
        WindowGroup(Term.library, id: "main") {
            ContentView(settings: sharedSettings)
                // V5.60-7: cheat sheet 挂在 WindowGroup root view——Scene 级不支持 .sheet
                .sheet(isPresented: $showShortcutsSheet) {
                    KeyboardShortcutsSheet()
                }
                // V6.12.16: App 语言——SettingsView picker 改 sharedSettings.appLanguage, 这里 .environment 注入 locale
                //   所有 SwiftUI Text / Formatter / String(localized:) 自动跟随
                //   V6.12.17 Copy 迁 NSLocalizedString 后, 整个 UI 文案会按选的语言显示
                .environment(\.locale, Locale(identifier: sharedSettings.appLanguage.localeId))
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
        //   V5.59-3: 传 sharedSettings (与 ContentView/menu 同实例)——不再 scene-level 新建
        Settings {
            SettingsView(settings: sharedSettings)
        }
        .commands {
            // V4.36.x: File 菜单——Open Recent（macOS 标准子菜单）
            //   显示最近 20 个导入的照片 URL
            //   点击 → NSWorkspace.activateFileViewerSelecting 在 Finder 中揭示
            CommandGroup(replacing: .newItem) {
                // 替换默认的 New 菜单组
            }
            CommandGroup(after: .newItem) {
                // 标准的 "File > Open Recent" 位置
                Menu(Copy.openRecent) {
                    RecentPhotosMenu()
                }
                // V6.19.5 (P0 #16): 新文件夹 (菜单 + ⌘⇧N, Photos 范式)
                //   跟现有 ⌘N hidden button (ContentKeyboardShortcuts) 同路径 — 弹新建文件夹 alert
                //   V6.20.0 (code audit fix #1): 之前误调 model.createFolderFromAlert() (它 trim 空 name 早返) → silent failure
                //   现在走 NotificationCenter → ContentView+Lifecycle 设 model.showingNewFolderAlert = true (同 ⌘N)
                //   双 trigger 不冲突: ⌘N = hidden button (走 onNewFolder closure), ⌘⇧N = menu button (走 NotificationCenter)
                Button("新文件夹") {
                    NotificationCenter.default.post(name: .newFolderRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                // P4.2: 批量重命名 — ⌘⇧R
                //   走 NotificationCenter 通知 ContentView 弹 sheet (跟 V3.5.D .openSettingsRequested 同模式)
                //   ContentView+Lifecycle.batchRenameSheet 内 onReceive 监听
                Divider()
                Button(Copy.batchRenameTitle + "…") {
                    NotificationCenter.default.post(name: .showBatchRenameSheet, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                // V6.19.0 (P0 #1): 多图分享 — ⌘⇧E (跟 P4.2 批量重命名同 pattern)
                //   走 NotificationCenter → ContentView 弹 NSSharingServicePicker (AirDrop/Messages/Mail)
                //   单图分享走 cell context menu ShareLink (Photos.app 范式)
                Button("分享…") {
                    NotificationCenter.default.post(name: .shareRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            // V6.19.5 (P0 #16): Speech 朗读 — macOS 没有 .speech placement, 放 Edit 菜单用 .pasteboard 占位
            //   选 N 张 → 朗读 "已选 N 张照片, 第一张 <filename>" (zh-CN)
            //   AVSpeechSynthesizer 在 model.speakSelection() 实现
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("开始朗读") {
                    NotificationCenter.default.post(name: .speakRequested, object: nil)
                }
            }
            // V6.19.5 (P0 #16): Services 默认 submenu — macOS 自动接管 (系统 services, .systemServices placement)
            //   EmptyView — 留给系统 services 自动填充 (NSServices 注册的 providers)
            CommandGroup(replacing: .systemServices) {
                EmptyView()
            }
            // macOS 原生 View 菜单（在 View 菜单里加 Toggle 项）
            // V5.59-3: 3 Toggle + 3 Button 改用 $sharedSettings.X 替代已删的 3 userDefaults bindings
            CommandGroup(after: .sidebar) {
                Toggle(Copy.showSidebar, isOn: $sharedSettings.showSidebar)
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Toggle(Copy.showDetailPanel, isOn: $sharedSettings.showDetail)
                    .keyboardShortcut("d", modifiers: [.command, .control])
                // V4.37.0: macOS Photos 标准 ⌘I = Show Info Panel
                //   与 ⌘Ctrl+D 同一动作（toggle 详情面板）——Photos.app ⌘I 行为
                //   ⌘Ctrl+D 保留为项目传统快捷键不破坏现有用户习惯
                Toggle(Copy.showInfoPanel, isOn: $sharedSettings.showDetail)
                    .keyboardShortcut("i", modifiers: .command)
                // V4.37.1: ⌘Y 快速查看——macOS Finder/Photos 标准 Quick Look 入口
                //   与 toolbar .quickLook 按钮 + 空格键共用 ContentView.showQuickLook()
                //   disable 状态由 NSToolbar.validateToolbarItem 单选时启用控制
                QuickLookMenuItem()
                // V4.37.2: ⌘[ / ⌘] 上一张/下一张（macOS Quick Look / Finder Back/Forward 风格）
                //   复用 ContentView.goPrev/goNext（与 ←→ 方向键同路径，canPrev/canNext 边界检查共用）
                NavigateMenuItems()
                Divider()
                // V4.37.0: 视图切换（缩略图/列表/时间线）——macOS Photos / Finder View > View As 风格
                //   用 ⌥1/⌥2/⌥3 避开 ContentKeyboardShortcuts 占用的 ⌘1-6（侧边栏 section 切换）
                //   Photos.app 用 ⌘1-5 是因为它没有多 section 侧边栏
                Button {
                    sharedSettings.viewModeRaw = ViewMode.grid.rawValue
                } label: {
                    Text(Copy.viewModeGridFull)
                }
                .keyboardShortcut("1", modifiers: .option)
                Button {
                    sharedSettings.viewModeRaw = ViewMode.list.rawValue
                } label: {
                    Text(Copy.viewModeListFull)
                }
                .keyboardShortcut("2", modifiers: .option)
                Button {
                    sharedSettings.viewModeRaw = ViewMode.timeline.rawValue
                } label: {
                    Text(Copy.viewModeTimelineFull)
                }
                .keyboardShortcut("3", modifiers: .option)
            }
            // V6.22.6 (Bug 4): 删 SettingsLink CommandGroup
            //   macOS 14+ Settings scene (L221) 自动在 app menu 加 "设置…" + 绑 ⌘, — 不需要显式 SettingsLink
            //   之前同时存在 → 2 个 "设置…" 菜单项 (AppleScript 验证)
            //   撤回 V4.13.0 误加的 SettingsLink block
            // V4.7.0 NEW: Undo/Redo Edit menu 集成
            //   CommandGroup(replacing: .undoRedo) 替换系统默认 Undo/Redo（macOS 标准位置）
            //   之前 ⌘Z/⌘⇧Z 由 ContentKeyboardShortcuts.swift 里的 hidden Button 处理
            //   现在用 .keyboardShortcut 绑到菜单项——系统接管，原 hidden Button 移除
            CommandGroup(replacing: .undoRedo) {
                UndoRedoMenuButtons()
            }
            // V5.60-7: ⌘? 弹 cheat sheet——macOS 14+ CommandGroup(replacing: .help) 标准
            //   Help 菜单是系统默认菜单, macOS 自动接管 ⌘? shortcut
            //   加 Button("Keyboard Shortcuts…") 替代无操作
            CommandGroup(replacing: .help) {
                Button(Copy.keyboardShortcutsMenu) {
                    showShortcutsSheet = true
                }
            }
        }
    }
}

// MARK: - 通知名（V3.5.D 新增）
//
// V4.15.0: 删 .openSettingsRequested + .focusSearchField 2 个通知名
//   .openSettingsRequested：V4.13.0 ⌘, 改 Settings scene 后已 0 调用方
//   .focusSearchField：V4.8.1 NSSearchField 接管后 0 调用方
//   （V3.5.D 旧实现：菜单 post .openSettingsRequested → ContentView 弹 sheet；
//    V3.6.23 旧实现：⌘F post .focusSearchField → ToolbarView 自绘搜索框聚焦）

// MARK: - V5.59-3: 删 Binding<Bool>(userDefaults:) extension helper
//   原 V3.5.18: 让 View 菜单 Toggle 绑定 UserDefaults key, 不在 App 里再 @AppStorage 一次
//   V5.59-3: 全部 menu items 改用 $sharedSettings.X (@Observable 自动广播)——helper 不再需要

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
/// V4.36.x: 最近打开菜单——File > Open Recent
/// 显示 RecentPhotosStore 中的最近 20 个照片 URL
/// 点击 → 在 Finder 中揭示；空时显示"清空菜单"
/// V6.11: @ObservedObject + ObservableObject 包装 → @State + @Observable 直持
struct RecentPhotosMenu: View {
    @State private var store = RecentPhotosStore.shared

    var body: some View {
        Group {
            if store.urls.isEmpty {
                Text(Copy.noRecentFiles)
            } else {
                ForEach(Array(store.urls.enumerated()), id: \.element) { index, url in
                    Button {
                        store.revealInFinder(url)
                    } label: {
                        Text(Copy.recentFile(index: index + 1, filename: url.lastPathComponent))
                    }
                }
                Divider()
                Button(Copy.clearMenu) {
                    store.clear()
                }
            }
        }
    }
}

/// V4.37.1: 快速查看菜单项——⌘Y Quick Look
/// 复用 ToolbarController.onQuickLook closure（与 toolbar 按钮 / 空格键 同路径）
/// ContentView.showQuickLook 内部检查 singleSelectedPhoto——无选时是 no-op 不需要 disabled
struct QuickLookMenuItem: View {
    var body: some View {
        Button(Copy.quickLook) {
            ToolbarController.shared.onQuickLook?()
        }
        .keyboardShortcut("y", modifiers: .command)
    }
}

/// V4.37.2: 上一张/下一张菜单项——⌘[ / ⌘]
/// 复用 ToolbarController.onPrev/onNext closures（与 ←→ 方向键 同路径）
/// ContentView.goPrev/goNext 内部 canPrev/canNext 边界检查——无边界时是 no-op 不需要 disabled
struct NavigateMenuItems: View {
    var body: some View {
        Button(Copy.previousPhoto) {
            ToolbarController.shared.onPrev?()
        }
        .keyboardShortcut("[", modifiers: .command)
        Button(Copy.nextPhoto) {
            ToolbarController.shared.onNext?()
        }
        .keyboardShortcut("]", modifiers: .command)
    }
}

/// V4.36.x: RecentPhotosStore 的 ObservableObject 包装
/// V6.11: 删除整个包装类——RecentPhotosStore 升级 @Observable 后不需要包装
///   RecentPhotosMenu 改 @State 直持 RecentPhotosStore.shared
///   之前 2 处 recordImport/recordImports 显式同步 urls = store.urls 是为触发
///   @Published 重渲, 跟 @Observable 集成后 store.urls 写操作自动追踪
/*
@MainActor
final class RecentPhotosStoreObservable: ObservableObject {
    static let shared = RecentPhotosStoreObservable()
    private let store = RecentPhotosStore.shared

    @Published var urls: [URL] = []

    private init() {
        urls = store.urls
    }

    func recordImport(_ url: URL) {
        store.recordImport(url)
        urls = store.urls
    }

    func recordImports(_ newURLs: [URL]) {
        store.recordImports(newURLs)
        urls = store.urls
    }

    func clear() {
        store.clear()
        urls = store.urls
    }

    func revealInFinder(_ url: URL) {
        store.revealInFinder(url)
    }
}
*/

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
        guard let desc = undoManager?.undoDescription, !desc.isEmpty else { return Copy.undo }
        return Copy.undoWithAction(desc)
    }

    /// "重做 <action>"——无 action 时仅 "重做"
    private var redoLabel: String {
        guard let desc = undoManager?.redoDescription, !desc.isEmpty else { return Copy.redo }
        return Copy.redoWithAction(desc)
    }
}
