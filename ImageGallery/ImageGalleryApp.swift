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
    // V6.74.0: View 菜单 ⌘Y / ⌘[ / ⌘] 走 NotificationCenter (跟 .newFolderRequested 同 pattern)
    //   原 ToolbarController.shared.onQuickLook?() 等 closure 永远 nil (configureToolbar 早返没赋值)
    //   menu button 发通知, ContentView .onReceive 转给 model.grid.showQuickLook() / goPrev() / goNext()
    static let quickLookRequested = Notification.Name("com.iridescent.ImageGallery.quickLookRequested")
    static let navigatePrevRequested = Notification.Name("com.iridescent.ImageGallery.navigatePrevRequested")
    static let navigateNextRequested = Notification.Name("com.iridescent.ImageGallery.navigateNextRequested")
    // V6.94.1: Markup (PencilKit 标注) P0 #3 — Edit menu ⌘M 触发
    //   ContentView .onReceive 监听 → showingMarkup = true → 弹 MarkupSheet
    static let markupRequested = Notification.Name("com.iridescent.ImageGallery.markupRequested")
    // V6.97.1: Crop / Aspect P0 #5 — Edit menu ⌘⇧K 触发
    //   ContentView .onReceive 监听 → showingCropSheet = true → 弹 CropSheet
    //   复用 V6.94.1 markup 完全 wiring pattern (Notification + ContentView sheet)
    static let cropRequested = Notification.Name("com.iridescent.ImageGallery.cropRequested")
    // V6.96 P0 #7: Edit > Copy 菜单 — 走 NotificationCenter 模式 (跟 .markupRequested 同 pattern)
    //   ContentView .onReceive 监听 → model.grid.copyToPasteboard() (GridViewModel+Operations 已存在)
    static let copyRequested = Notification.Name("com.iridescent.ImageGallery.copyRequested")
    // V6.96 P0 #7: View > Zoom In / Zoom Out / Actual Size (⌘+ / ⌘- / ⌘0)
    //   走 NotificationCenter 模式, ContentView .onReceive 转给 model.grid.zoomIn/zoomOut/resetThumbnailSize
    static let zoomInRequested = Notification.Name("com.iridescent.ImageGallery.zoomInRequested")
    static let zoomOutRequested = Notification.Name("com.iridescent.ImageGallery.zoomOutRequested")
    static let actualSizeRequested = Notification.Name("com.iridescent.ImageGallery.actualSizeRequested")

    // V6.97.2: Shortcuts Siri / Spotlight / 快捷指令 app URL scheme 触发
    //   Intent perform() 调 NSWorkspace.openURL("imagegallery://..."), 主 app onOpenURL 接收
    //   这里分发到对应 Notification, ContentView+Lifecycle .onReceive 转给 GridViewModel 现有 operation
    //   跟 .cropRequested / .markupRequested 同 pattern (Photos.app Sonoma+ Siri 范式)
    static let shortcutsShowLastPhotoRequested = Notification.Name("com.iridescent.ImageGallery.shortcutsShowLastPhotoRequested")
    static let shortcutsSearchRequested = Notification.Name("com.iridescent.ImageGallery.shortcutsSearchRequested")
    static let shortcutsCropRequested = Notification.Name("com.iridescent.ImageGallery.shortcutsCropRequested")
    static let shortcutsFavoriteRequested = Notification.Name("com.iridescent.ImageGallery.shortcutsFavoriteRequested")
}

// V6.97.2: handleShortcutsURL — 主 app onOpenURL 接收 Siri / Spotlight / 快捷指令 app URL
//   URL scheme: imagegallery://<action>?<params>
//   4 个 action:
//     - show-last              打开最后一张 (immersive view)
//     - search?q=<query>       搜索 photos, query 是 URL-encoded 字符串
//     - crop?aspect=<aspect>   裁剪当前单选 photo, aspect 是 CropAspect rawValue (freeform/ratio_1_1/...)
//     - favorite               toggle 收藏当前单选 photo
//   不解析 URL → 直接发 Notification, 让 ContentView+Lifecycle 的 .onReceive handler 调 GridViewModel 现有 operation
//   跟 Photos.app Sonoma+ Siri 范式对齐: Siri 触发 → URL → 主 app 处理 (不用 App Group)
private func _unused_marker() {}  // V6.97.2: 占位避免 extension 后面直接接 struct 编译错误

// AppDelegate：处理应用层 macOS 事件
// V3.7.1 重写: 自实现窗口 frame 持久化 (替换 V6.12.6 的 setFrameAutosaveName, 不 work)
//   - 原因: setFrameAutosaveName 在 SwiftUI Scene 创建的 NSWindow 不生效
//     (SwiftUI 自己管 frame state, AppKit autosave 绑不住)
//   - 修法: NSWindowDelegate 监 windowDidResize/windowDidMove 写 UserDefaults
//     + applicationDidFinishLaunching 读 UserDefaults setFrame 恢复
//   - 4 个 key (size.w/h, position.x/y) — 简单, 不污染其他 key
//   - Photos.app / Finder / Safari 标准行为: 关在哪开回来还在哪
// V6.97.0 P3-2 fix: 4 个全局 key 改为 1 个主 key 存 per-window JSON — 解决 multi-window bug
//   - 之前: 所有 window 共用 4 个全局 key, 多窗口时互相覆盖
//     (主窗口 frame → attach 时 4 个 window 都用主窗口 frame 恢复
//      副窗口 resize → 写覆盖 4 个 key → 主窗口下次启动也变成副窗口 frame)
//   - 现在: 1 个主 key `imageGalleryWindowFrames` 存 [UUID: Frame] JSON
//     + NSMapTable<NSWindow, NSString> 持 weak ref 跟踪 window → UUID 映射
//     + 每个 window 独立 frame, 关掉再开新的不影响
//   - Backward compat: 检测 4 个老 key 存在 → 迁到主 key (写到第一个 attach 的 window UUID) → 删老 key
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // V6.97.0: frame 持久化 1 个主 key — 存 [UUID: Frame] JSON 字典
    //   UUID 字符串 = 每个 NSWindow 分配时的稳定 ID (NSMapTable weak ref 跟踪)
    private static let framesKey = "imageGalleryWindowFrames"

    // V6.97.0: 跟踪 NSWindow → UUID 映射 — NSMapTable 持 weak ref, window 关闭自动清
    //   strongToWeakObjects: value (UUID string) 强引用, key (NSWindow) 弱引用
    //   同一 window 重复 attach 拿到同一 UUID; 新 window 自动分配新 UUID
    private let windowIDs = NSMapTable<NSWindow, NSString>.strongToWeakObjects()

    // V6.97.0: 4 个老 key 常量保留 (迁移逻辑用) — V6.98+ 可删
    private static let legacySizeWKey = "imageGalleryWindowSizeW"
    private static let legacySizeHKey = "imageGalleryWindowSizeH"
    private static let legacyPosXKey = "imageGalleryWindowPosX"
    private static let legacyPosYKey = "imageGalleryWindowPosY"

    // V6.94.0: -uitest-reset-store 在 applicationWillFinishLaunching 处理 (早于 init)
    //   必须在 ImageGalleryApp.init() 之前删 SwiftData store + WAL files,
    //   否则 ModelContainer 第一次 try 命中旧文件句柄, 删文件会被拒
    func applicationWillFinishLaunching(_ notification: Notification) {
        // V6.94.0: 不调 super.perform — NSObject 没有默认 applicationWillFinishLaunching 实现
        //   (NSApplicationDelegate 是 protocol, 协议方法默认实现就是空)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-reset-store") {
            // V6.94.0: 用 ModelConfiguration 默认 url (跟 ImageGalleryApp.init 同一路径) — 单一真相源
            let config = ModelConfiguration()
            try? FileManager.default.removeItem(at: config.url)
            // V6.94.0: 删 WAL files (.store-shm + .store-wal) — SQLite lock 残留
            try? FileManager.default.removeItem(at: config.url.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: config.url.appendingPathExtension("wal"))
            NSLog("V6.94.0: reset SwiftData store at \(config.url) for XCUITest")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // V6.22.10 (XCUITest): UI test launch arg 解析 — 在 setUp/tearDown 之前清 UserDefaults
        //   launch arg 在 appDidFinishLaunching 早期解析, 比 UserSettings init 早
        //   XCUITest 不能从 app 外部 reset UserDefaults, 必须 launch 时带 arg
        // V6.70: 删 -uitest-reset-onboarding 处理 — OnboardingView 取消
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-reset-all") {
            let domain = Bundle.main.bundleIdentifier ?? ""
            UserDefaults.standard.removePersistentDomain(forName: domain)
            NSLog("V6.22.10: reset UserDefaults domain=\(domain) for XCUITest")
        }

        // V6.64.2: 启动 crash reporter — 监听 uncaught exception + 5 POSIX signals
        //   早挂早保护 — applicationDidFinishLaunching 早期, 防 SwiftData init 崩没监听
        CrashReporter.install()

       NSApp.setActivationPolicy(.regular)
       NSApp.activate(ignoringOtherApps: true)

        // V6.XX: 减少动态效果——读取系统 accessibility 设置
        //   Animations 枚举检查 reduceMotionOverride 标志，开启时所有 token 返回 nil
        reduceMotionOverride = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DistributedNotificationCenter.default().addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            reduceMotionOverride = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

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
        // V6.97.0: 给 window 分配稳定 UUID (NSMapTable weak ref 跟踪)
        //   同一 window 重复 attach 拿到同一 UUID; 新 window 自动分配
        let id = windowID(for: window)
        // V6.97.0: backward compat — 第一次 attach 时把 V3.7.1 老 4 key 迁到主 key
        //   静态方法 idempotent (老 key 不存在时 no-op, 已迁时 no-op)
        Self.migrateLegacyFrameIfNeeded(defaults: .standard, currentID: id)
        // 应用 stored frame (启动恢复)
        applyStoredFrameIfAny(to: window, id: id)
    }

    // V6.97.0: window → UUID 分配 — NSMapTable 查旧, 没命中分配新
    private func windowID(for window: NSWindow) -> String {
        if let existing = windowIDs.object(forKey: window) as String? {
            return existing
        }
        let new = UUID().uuidString
        windowIDs.setObject(new as NSString, forKey: window)
        return new
    }

    private func applyStoredFrameIfAny(to window: NSWindow, id: String) {
        let defaults = UserDefaults.standard
        let frames = Self.loadAllFrames(defaults: defaults)
        guard let frame = frames[id] else {
            return
        }

        // 验证 frame 合理:遍历所有屏幕(外接屏 + 主屏),任一屏 visible ≥ 30% 才恢复
        //   之前只验 NSScreen.main —— 外接显示器拔掉后,frame 落在已消失的屏幕上
        //   主屏可见性 0,被误判"不可见"丢弃 → 用户感觉窗口"消失"
        let visibleRatio: CGFloat = 0.3
        let isVisibleOnAnyScreen = NSScreen.screens.contains { screen in
            let intersection = frame.intersection(screen.visibleFrame)
            // 至少 30% 面积在屏幕 visible 区域 (macOS 可见 frame 排除 Dock/menu bar)
            guard intersection.width > 0, intersection.height > 0 else { return false }
            let visibleArea = intersection.width * intersection.height
            let frameArea = frame.width * frame.height
            return frameArea > 0 && visibleArea / frameArea >= visibleRatio
        }

        if isVisibleOnAnyScreen {
            window.setFrame(frame, display: true)
        } else {
            // 兜底:frame 几乎完全在所有屏幕外(常见于外接显示器切换)
            //   保留用户偏好尺寸,居中到主屏,避免窗口"消失"
            let primaryVisible = NSScreen.main?.visibleFrame ?? .zero
            let safeOrigin = NSPoint(
                x: primaryVisible.midX - frame.width / 2,
                y: primaryVisible.midY - frame.height / 2
            )
            let safeOriginClamped = NSPoint(
                x: max(primaryVisible.minX, min(safeOrigin.x, primaryVisible.maxX - frame.width)),
                y: max(primaryVisible.minY, min(safeOrigin.y, primaryVisible.maxY - frame.height))
            )
            let safeFrame = NSRect(origin: safeOriginClamped, size: frame.size)
            window.setFrame(safeFrame, display: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - V3.7.1: NSWindowDelegate — 监听 window 变化 + 写 UserDefaults
    // V6.97.0: saveFrame 改 per-window — 用 windowID 查 map, 写到主 key 下当前 window UUID

    func windowDidResize(_ notification: Notification) {
        saveFrame(from: notification.object as? NSWindow)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(from: notification.object as? NSWindow)
    }

    private func saveFrame(from window: NSWindow?) {
        guard let window else { return }
        let id = windowID(for: window)
        let frame = window.frame
        let defaults = UserDefaults.standard
        var frames = Self.loadAllFrames(defaults: defaults)
        frames[id] = frame
        Self.saveAllFrames(frames, defaults: defaults)
    }

    // V6.97.0: 主 key 读写 — JSON 字典 [UUID: Frame]
    //   Frame 用 [String: Double] 序列化 (Codable on CGRect 在不同 OS 行为不一致)
    //   static 让 unit test 可以直接调, 不构造 AppDelegate / NSWindow
    static func loadAllFrames(defaults: UserDefaults) -> [String: CGRect] {
        guard let data = defaults.data(forKey: framesKey),
              let raw = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else {
            return [:]
        }
        return raw.mapValues { dict in
            CGRect(
                x: dict["x"] ?? 0,
                y: dict["y"] ?? 0,
                width: dict["w"] ?? 800,
                height: dict["h"] ?? 600
            )
        }
    }

    static func saveAllFrames(_ frames: [String: CGRect], defaults: UserDefaults) {
        let encodable = frames.mapValues { frame in
            ["x": frame.origin.x, "y": frame.origin.y, "w": frame.width, "h": frame.height]
        }
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: framesKey)
        }
    }

    // V6.97.0: backward compat — 第一次 attach 时把 V3.7.1 老 4 key 迁到主 key
    //   写到当前 attach 的 window UUID 下 (假设第一个 attach 的是主窗口, NSApp.windows.first)
    //   一次性迁移, 删 4 个老 key
    //   static 让 unit test 可以直接调 (接收 id + defaults, 不依赖 NSWindow 实例)
    static func migrateLegacyFrameIfNeeded(defaults: UserDefaults, currentID: String) {
        guard let w = defaults.object(forKey: legacySizeWKey) as? Double,
              let h = defaults.object(forKey: legacySizeHKey) as? Double,
              let x = defaults.object(forKey: legacyPosXKey) as? Double,
              let y = defaults.object(forKey: legacyPosYKey) as? Double else {
            return  // 老 key 不存在, 不迁移
        }
        let frame = CGRect(x: x, y: y, width: w, height: h)
        var frames = loadAllFrames(defaults: defaults)
        // 主 key 没这个 UUID 的 frame 时, 写老 frame 进去 (防覆盖更晚 attach 的 window)
        if frames[currentID] == nil {
            frames[currentID] = frame
            saveAllFrames(frames, defaults: defaults)
        }
        // 删 4 个老 key — 一次性迁移完成
        defaults.removeObject(forKey: legacySizeWKey)
        defaults.removeObject(forKey: legacySizeHKey)
        defaults.removeObject(forKey: legacyPosXKey)
        defaults.removeObject(forKey: legacyPosYKey)
        NSLog("V6.97.0: migrated V3.7.1 legacy window frame to per-window key (UUID: \(currentID))")
    }
}

@main
struct ImageGalleryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // V6.97 P3-2: openWindow 环境 — 注入到 .commands 里的 "新建窗口" 按钮
    //   openWindow(id: "main") 创建新 WindowGroup 实例, 每窗口独立 ContentViewModel
    //   sharedSettings / modelContainer 走 @State 共享 (新窗口拿到同一实例)
    @Environment(\.openWindow) private var openWindow

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
        // V6.94.1: 改用 ImageGallerySchemaV3 (最新) — target schema 必须是最高版本
        //   migrationPlan 自动检测 V1/V2 store → lightweight V1→V2→V3 顺序应用
        let schema = Schema(versionedSchema: ImageGallerySchemaV3.self)
        // V6.97.2 (revised): 不用 App Group groupContainer — App 是 ad-hoc signing (Team ID not set)
        //   macOS 沙盒要求 App Group container 必须 Team-prefixed, ad-hoc app 创建失败 → ModelContainer bootstrap crash
        //   改回 ModelConfiguration() 默认路径 (~/Library/Application Support/default.store)
        //   Intent 全部走 URL scheme → 主 app onOpenURL 处理 (跟 Photos.app 范式)
        //   主 app 收到 URL 后调现有 @MainActor GridViewModel operations (cropSelected / batchSetRating 等)
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

    // V6.97.2: handleShortcutsURL — URL scheme 路由 → NotificationCenter
    //   4 个 action 跟 4 个 Notification 一一对应 (L37-41)
    //   search/crop 带 URL 参数, 通过 userInfo 透传到 .onReceive handler
    static func handleShortcutsURL(_ url: URL) {
        // 防御性: 只处理 imagegallery scheme
        guard url.scheme == "imagegallery" else {
            Self.logger.warning("handleShortcutsURL 收到非 imagegallery URL: \(url.absoluteString, privacy: .public)")
            return
        }
        let action = url.host ?? ""
        // 解析 query parameter (e.g. ?q=cat&aspect=ratio_16_9)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let queryValue = queryItems.first(where: { $0.name == "q" })?.value ?? ""
        let aspectValue = queryItems.first(where: { $0.name == "aspect" })?.value ?? "freeform"

        Self.logger.info("handleShortcutsURL action=\(action, privacy: .public) q=\(queryValue, privacy: .public) aspect=\(aspectValue, privacy: .public)")

        switch action {
        case "show-last":
            NotificationCenter.default.post(name: .shortcutsShowLastPhotoRequested, object: nil)
        case "search":
            NotificationCenter.default.post(
                name: .shortcutsSearchRequested,
                object: nil,
                userInfo: ["query": queryValue]
            )
        case "crop":
            NotificationCenter.default.post(
                name: .shortcutsCropRequested,
                object: nil,
                userInfo: ["aspect": aspectValue]
            )
        case "favorite":
            NotificationCenter.default.post(name: .shortcutsFavoriteRequested, object: nil)
        default:
            Self.logger.warning("handleShortcutsURL 未知 action: \(action, privacy: .public)")
        }
    }

    // V5.59-3: 删 3 个 userDefaults-based bindings (showSidebarBinding/showDetailBinding/viewModeBinding)
    //   menu items 现在改用 $sharedSettings.X (V5.59-3 下面命令)——
    //   @Observable sharedSettings 自动广播, menu 改 → ContentView/SettingsView 即时同步
    //   删下面 extension Binding<Bool>(userDefaults:) helper (L185-191)——不再用

    var body: some Scene {
        // V3.5.D：WindowGroup 加 id 让 macOS 能稳定追踪窗口(用于 frame autosave)
        // 同时加 defaultSize 给首次启动一个合理尺寸
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
                // V6.97.2: onOpenURL 处理 Siri / Spotlight / 快捷指令 app URL scheme
                //   Intent 在 perform() 里 NSWorkspace.openURL("imagegallery://action?param=...")
                //   主 app 收到 URL → 分发到 ContentView+Lifecycle 的 .onReceive handler
                //   走现有 @MainActor GridViewModel operations (cropSelected / batchSetRating / enterImmersive 等)
                //   跟 Photos.app Sonoma+ Siri 范式对齐: Siri 触发 → 主 app 处理 (不用 App Group)
                .onOpenURL { url in
                    Self.handleShortcutsURL(url)
                }
        }
        // V4.1.0 m: 默认 1280×800；contentMinSize 由 layout 决定
        //   侧栏 160pt + 工具栏 200pt + grid 400pt + 详情 320pt = 1080pt 横向最小
        //   纵向 toolbar 30 + 状态栏 24 + grid 200 = 254pt 最小
        //   13" MacBook (1280×800) 能完整用；更小屏幕 contentMinSize 会兜底
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        // V6.62: SwiftUI toolbar — NavigationSplitView 管理自己的工具栏
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
            // V6.62 (P4.13): 删空 CommandGroup(replacing: .newItem) { } (-3 LOC dead code) — 默认 New 已替换
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
                // V6.97 P3-2: File > New Window (⌘N) — macOS 标准快捷键
                //   openWindow(id: "main") 创建新 WindowGroup 实例, 跟主窗口共享 modelContainer
                //   每窗口独立 ContentViewModel (sidebar selection / sort / zoom 隔离)
                //   sharedSettings 走 @State 跨窗口共享 (用户偏好全局一致)
                Button(Copy.newWindow) {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button(Copy.newFolder) {
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
                Button(Copy.menuShare) {
                    NotificationCenter.default.post(name: .shareRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                // V6.39.1: File 菜单加 "清空回收站" — 跟 Settings page 同 path (NotificationCenter)
                //   destructive 操作不绑快捷键 (避免误触), 二次确认在 ContentView 走 confirmationDialog
                Divider()
                Button(Copy.menuEmptyTrash) {
                    NotificationCenter.default.post(name: .emptyTrashRequested, object: nil)
                }
                .help(Copy.menuEmptyTrashTooltip)
            }
            // V6.19.5 (P0 #16): Speech 朗读 — macOS 没有 .speech placement, 放 Edit 菜单用 .pasteboard 占位
            //   选 N 张 → 朗读 "已选 N 张照片, 第一张 <filename>" (zh-CN)
            //   AVSpeechSynthesizer 在 model.speakSelection() 实现
            //
            // V6.96 P0 #7: 加 Edit > Copy (⌘C) — macOS 原生 .pasteboard placement
            //   替换模式: .pasteboard 接管原生 Copy/Cut/Paste 槽位
            //   这里只注入 Copy, Cut/Paste 让系统默认 (跟 Photos.app 同 — Photos 也只覆盖 Copy)
            //   ContentView .onReceive(.copyRequested) → model.grid.copyToPasteboard()
            //   .disabled 状态由 model.grid.selectionEmpty 派生 (跟 toolbar 一致)
            CommandGroup(replacing: .pasteboard) {
                Button(Copy.copyAction) {
                    NotificationCenter.default.post(name: .copyRequested, object: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(Copy.menuStartSpeaking) {
                    NotificationCenter.default.post(name: .speakRequested, object: nil)
                }
                // V6.94.1: Markup (PencilKit 标注) — P0 #3
                //   Photos 真版 ⌘M 走 Edit menu, ContentView .onReceive 监听
                Button(Copy.markupMenu) {
                    NotificationCenter.default.post(name: .markupRequested, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command])
                // V6.97.1: Crop / Aspect — P0 #5
                //   跟 markup 完全对称 wiring (Notification + ContentView sheet)
                //   ⌘⇧K — 避 Photos ⌘R (Refresh) / ⌘K (Insert link) / 系统快捷键冲突
                Button(Copy.cropMenu) {
                    NotificationCenter.default.post(name: .cropRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
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
                    // V6.58 (audit P1.7): ⌃⌘S → ⌘\ 避开 ⌘⇧S (sort) 撞 's' 字面冲突
                    .keyboardShortcut("\\", modifiers: [.command])
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
                // V6.96 P0 #7: View > Actual Size (⌘0) / Zoom In (⌘+) / Zoom Out (⌘-)
                //   缩略图大小是 Photos 主 grid 概念, 不是图片 zoom (detail panel 用)
                //   走 NotificationCenter → model.grid.resetThumbnailSize() / zoomIn() / zoomOut()
                Button(Copy.actualSize) {
                    NotificationCenter.default.post(name: .actualSizeRequested, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
                Button(Copy.zoomIn) {
                    NotificationCenter.default.post(name: .zoomInRequested, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                Button(Copy.zoomOut) {
                    NotificationCenter.default.post(name: .zoomOutRequested, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
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
            // V6.64.2: 加 Divider + Reveal Crash Logs 项 — 让用户附 log 给 bug report
            CommandGroup(replacing: .help) {
                Button(Copy.keyboardShortcutsMenu) {
                    showShortcutsSheet = true
                }
                Divider()
                Button(Copy.helpRevealCrashLogs) {
                    CrashReporter.revealLogsInFinder()
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
/// V6.74.0: 改走 NotificationCenter.quickLookRequested (取代 ToolbarController.shared.onQuickLook?() nil closure 死路径)
/// ContentView.showQuickLook 内部检查 singleSelectedPhoto——无选时是 no-op 不需要 disabled
struct QuickLookMenuItem: View {
    var body: some View {
        Button(Copy.quickLook) {
            NotificationCenter.default.post(name: .quickLookRequested, object: nil)
        }
        .keyboardShortcut("y", modifiers: .command)
    }
}

/// V4.37.2: 上一张/下一张菜单项——⌘[ / ⌘]
/// V6.74.0: 改走 NotificationCenter (取代 ToolbarController.shared.onPrev/onNext?() nil closure 死路径)
/// ContentView.goPrev/goNext 内部 canPrev/canNext 边界检查——无边界时是 no-op 不需要 disabled
struct NavigateMenuItems: View {
    var body: some View {
        Button(Copy.previousPhoto) {
            NotificationCenter.default.post(name: .navigatePrevRequested, object: nil)
        }
        .keyboardShortcut("[", modifiers: .command)
        Button(Copy.nextPhoto) {
            NotificationCenter.default.post(name: .navigateNextRequested, object: nil)
        }
        .keyboardShortcut("]", modifiers: .command)
    }
}

/// V6.62 (P4.14): 删 commented-out RecentPhotosStoreObservable class (-32 LOC dead code)
///   之前 V4.36.x 加, V6.11 升级 @Observable 后注释保留 — 现在直接删

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
