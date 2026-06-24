//
//  ContentView+Lifecycle.swift
//  ImageGallery
//
//  V6.100: 拆 5 sub-modifier 到 Views/Lifecycle/ (LifecycleModifiers/KeyboardModifiers/
//    DialogModifiers/SheetModifiers/NotificationModifiers)
//    原 contentBodyModifiers 250 行 / 53 参数已经踩过 type-check timeout (V6.97 P2-3 教训)
//    拆 5 sub-modifier 后 ContentView body chain 13 → 8 modifier, 编译秒过
//
//  V5.51-3: 从 ContentView.swift 抽出 appLifecycleHooks modifier
//  原位置 ContentView.swift:1744-1775
//  V4.10.0 引入——把 .onAppear + 6 个 .onChange 打包成 1 个 modifier 避免 type-check 超时
//

import SwiftUI
import SwiftData

// MARK: - V4.10.0: app lifecycle hooks extension
//
// 把 .onAppear + 6 个 .onChange 打包成 1 个语义化 modifier，让 body 链显著缩短。
// 同样的"抽到 extension 避免 type-check 超时"模式参考 applySettingsChrome / syncNSToolbar*。
// V5.59-2: 删 6 个 obsolete 参数 (storedThumbnailSize/storedSortOption/onStoredThumbnailChange/
//   onStoredSortOptionChange/onThumbnailChange/onSortOptionChange)——model.thumbnailSize/model.sortOption
//   已是 computed proxy 绑 settings, 无需手动 AppStorage 镜像
extension View {
    func appLifecycleHooks(
        thumbnailSize: CGFloat,
        sidebarSelection: SidebarSelection?,
        sortOption: SortOption,
        viewModeRaw: String,
        onAppear: @escaping () -> Void,
        onSidebarSelectionChange: @escaping (SidebarSelection?) -> Void
    ) -> some View {
        self
            .onAppear { onAppear() }
            // V3.6.13: viewModeRaw 通过 computed property 自动响应 AppStorage 变化
            .onChange(of: viewModeRaw) { _, _ in }
            .onChange(of: sidebarSelection) { _, new in onSidebarSelectionChange(new) }
    }
}

// V6.100: contentBodyModifiers 已拆 5 sub-modifier (在 Views/Lifecycle/)
//   - lifecycleModifiers (本文件 appLifecycleHooks + .task + 4 .onChange)
//   - keyboardModifiers (gridInputHandling + contentKeyboardShortcuts)
//   - dialogModifiers (batchActionDialogs + applySettingsChrome + exposeUndoManager)
//   - sheetModifiers (batchRenameSheet + shareSheet + markupSheet + cropSheet + smartFolderSheets)
//   - notificationModifiers (12 .onReceive + shortcutsHandler)
//
// V6.100.1: 留旧 contentBodyModifiers API 作为 backward compat wrapper, 标记 deprecated
//   ContentView body 改用 5 sub-modifier (chain -5 modifier)
//   V6.100.2+: ContentView caller 删 wrapper 调用

// MARK: - P4.2: 批量重命名 sheet
//
// Photos.app 范式: 弹 sheet, 模板实时 preview, Apply 调 ContentViewModel.batchRename
// File 菜单 ⌘⇧R 通过 NotificationCenter 触发 (绕过 menu 不能直接拿 SwiftUI state 的限制,
//   跟 V3.5.D .openSettingsRequested 同模式 — memory: V3.5.D 通知方案)
extension View {
    @MainActor
    func batchRenameSheet(
        model: ContentViewModel,
        selection: SelectionState,
        visiblePhotos: [Photo],
        showingBatchRename: Binding<Bool>
    ) -> some View {
        self
            .sheet(isPresented: showingBatchRename) {
                // 实时从 visiblePhotos 解析选中 (跟上一次 selection.selectedPhotos(in: visiblePhotos) 一致)
                let selectedPhotos = visiblePhotos.filter { selection.selectedIDs.contains($0.id) }
                BatchRenameSheet(
                    photos: selectedPhotos,
                    onApply: { template in
                        // 直接调 model.grid, 跟 batchMove 一样不通过 closure 包装
                        model.grid.batchRename(template: template)
                    }
                )
            }
            // P4.2: File 菜单 ⌘⇧R 通过通知触发 sheet
            //   收到通知 → 设 showingBatchRename = true (跟 V3.5.D .openSettingsRequested 同模式)
            .onReceive(NotificationCenter.default.publisher(for: .showBatchRenameSheet)) { _ in
                guard !selection.isEmpty else { return }
                showingBatchRename.wrappedValue = true
            }
    }
}

// MARK: - V6.19.0 (P0 #1): 分享 sheet (NSSharingServicePicker 多图)
//
// Photos.app 范式: File 菜单 ⌘⇧S → 弹 NSSharingServicePicker (AirDrop / Messages / Mail / Add to Photos)
// 单图分享走 cell context menu ShareLink (V6.19.0 加), 不进此 sheet
// 走 NotificationCenter 触发 (跟 P4.2 batchRenameSheet 同模式)
extension View {
    @MainActor
    func shareSheet(model: ContentViewModel) -> some View {
        self
            // V6.20.0 (code audit fix #7): binding setter 在 sheet dismiss 时清空 model.grid.sharingURLs
            //   之前 setter 是 _ in {} → URLs 永不清理 → 第二次 ⌘⇧E 选不同图仍弹老 URLs
            //   同时 fix: viewDidAppear 不再 fire 第二次 picker bug (sheet 重新 present 时 SwiftUI
            //   重新 make NSViewController, viewDidAppear 自然 fire — 之前 URLs 残留时 sheet 不重新 present)
            // V6.28: sharingURLs 在 model.grid
            .sheet(isPresented: bindable(
                model.grid.sharingURLs != nil,
                onDismiss: { model.grid.sharingURLs = nil }
            )) {
                if let urls = model.grid.sharingURLs, !urls.isEmpty {
                    SharePickerView(urls: urls)
                        .frame(minWidth: 400, minHeight: 300)
                }
            }
            // V6.19.0: File 菜单 ⌘⇧S 通过通知触发 sheet
            //   model.grid.shareSelectedURLs() 拿选中 + 单图 fallback, 无选给 toast 提示
            // V6.20.3 (code audit fix #15): debounce 0.3s — 快速连点 ⌘⇧S 不堆叠 sheet
            //   之前每次 onReceive 立即设 sharingURLs + 弹 sheet — 用户狂点会闪烁 sheet UI
            //   现在 model.grid.shouldThrottleShareRequest() 用 instance Date 状态做 throttle
            .onReceive(NotificationCenter.default.publisher(for: .shareRequested)) { _ in
                guard !model.grid.shouldThrottleShareRequest() else { return }
                let urls = model.grid.shareSelectedURLs()
                guard !urls.isEmpty else { return }
                model.grid.sharingURLs = urls
            }
    }

    // V6.94.1: MarkupSheet — P0 #3 Markup feature
    //   弹 MarkupSheet (NSBezierPath 自绘 + 工具栏), Edit menu ⌘M 触发
    //   选中 1 张图时启用 (P0 #3 标注单图模式), 0/多张图弹 toast 提示
    //   跟 shareSheet 同模式 (extension View, .sheet + bindable)
    @MainActor
    func markupSheet(model: ContentViewModel, showingSheet: Bool) -> some View {
        self.sheet(isPresented: bindable(showingSheet, onDismiss: { model.grid.showingMarkupSheet = false })) {
            if let resolved = model.grid.resolvedSingle {
                MarkupSheet(photo: resolved.photo)
            } else {
                // 0 张或多张图选 — 弹空视图, dismiss 后回到 grid
                // (理论上 .onReceive 已 check 选中, 这里兜底)
                EmptyView()
            }
        }
    }

    // V6.97.1: Crop sheet modifier — 跟 markupSheet 完全对称 wiring pattern
    //   接 showingCropSheet, 选中 1 张图时弹 CropSheet, 0/多张走兜底
    func cropSheet(model: ContentViewModel, showingSheet: Bool) -> some View {
        self.sheet(isPresented: bindable(showingSheet, onDismiss: { model.grid.showingCropSheet = false })) {
            if let resolved = model.grid.resolvedSingle {
                // V6.97.1.1 (Bug fix C1): 传 model 给 CropSheet, save() 走 model.grid.cropSelected
                //   (C1 undo 死修法 — 之前直接调 PhotoCropService.applyCrop 绕过 undo register)
                CropSheet(photo: resolved.photo, model: model)
            } else {
                EmptyView()
            }
        }
    }

    private func bindable(_ isPresent: Bool, onDismiss: @escaping () -> Void = {}) -> Binding<Bool> {
        Binding(
            get: { isPresent },
            set: { newValue in
                if !newValue { onDismiss() }
            }
        )
    }
}

// V6.19.0 (P0 #1): NSSharingServicePicker SwiftUI wrapper
//   NSSharingServicePicker 是 AppKit-only, 用 NSViewControllerRepresentable 包
//   onAppear 自动调 picker.show() 弹系统 share UI
struct SharePickerView: NSViewControllerRepresentable {
    let urls: [URL]

    func makeNSViewController(context: Context) -> NSViewController {
        let controller = SharePickerController(urls: urls)
        return controller
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}

    final class SharePickerController: NSViewController {
        let urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            // 弹 NSSharingServicePicker — AirDrop / Messages / Mail / Save / Add to Photos
            //   sheet 容器是 NSView, picker show relativeTo view
            // V6.20.3 (code audit fix #12): picker 升级为 ivar, 保证 ARC 持有直到 user dismiss
            //   之前 picker 是局部 let — closure capture 持有, 但 Apple 文档说 picker 必须 retained
            //   直到 dismissed. ivar 化避免任何边缘 case 下 ARC 早释放
            self.picker = NSSharingServicePicker(items: urls)
            // 0.1s 延迟让 sheet 动画完成再弹 picker (跟系统 Photos 行为一致)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                guard let picker = self.picker else { return }
                picker.show(relativeTo: NSRect(x: 200, y: 150, width: 1, height: 1), of: self.view, preferredEdge: .minY)
                // V6.20.3: picker show 后立即置 nil — show 调用后 NSSharingServicePicker 自己 retain
                //   我们 ivar 不再需要, 释放让 ARC 管生命周期
                self.picker = nil
            }
        }

        private var picker: NSSharingServicePicker?
    }
}

// MARK: - P4.1.1: 智能文件夹创建 sheet
//
// Photos.app "Save as Smart Album" 范式
// 入口: SidebarView Library section "+" 按钮 → onCreateSmartFolder → 设 model.showingNewSmartFolderSheet
// 此处 host sheet — ContentView 是 model @Bindable owner (跟 batchRenameSheet 同模式)
extension View {
    @MainActor
    func smartFolderCreateSheet(
        model: ContentViewModel,
        showingSheet: Binding<Bool>,
        pendingFilter: FilterState
    ) -> some View {
        self
            .sheet(isPresented: showingSheet) {
                SmartFolderCreateSheet(
                    initialFilter: pendingFilter,
                    onSave: { name, iconName, filterState in
                        // 直接调 model, 跟 createFolderFromAlert 范式一致
                        model.createSmartFolder(name: name, iconName: iconName, filterState: filterState)
                    }
                )
            }
    }

    // V6.97 P2-3: 智能文件夹编辑 sheet — 跟 create sheet 同 pattern, 多传 existingSmartFolder
    //   sheet 入口在 SidebarView (smart folder 右键菜单 "编辑筛选条件"), 触发 model.grid.editingSmartFolder
    //   onSave 调 model.updateSmartFolder 走 SwiftData update 而不是 insert
    @MainActor
    func smartFolderEditSheet(
        model: ContentViewModel,
        editingSmartFolder: Binding<SmartFolder?>,
        pendingFilter: FilterState
    ) -> some View {
        self
            .sheet(item: editingSmartFolder) { sf in
                SmartFolderCreateSheet(
                    initialFilter: pendingFilter,
                    onSave: { name, iconName, filterState in
                        model.updateSmartFolder(sf, name: name, iconName: iconName, filterState: filterState)
                    },
                    existingSmartFolder: sf
                )
            }
    }
}

// MARK: - V6.97 P2-3: smartFolderAndShareSheets 打包 5 个 modifier 解决 type-check 超时
//
// 原 ContentView body chain 13+ modifier 包含:
//   .batchRenameSheet / .smartFolderCreateSheet / .smartFolderEditSheet
//   / .shareSheet / .onReceive(.newFolderRequested) / .onReceive(.speakRequested)
//
// Swift 编译器推断 60s 超时。打包成单 modifier 后 chain 缩短 ~6, 秒过
//
// 包含:
//   1. smartFolderCreateSheet — Library section "+" 触发
//   2. smartFolderEditSheet — sidebar smart folder 右键 "编辑筛选条件" 触发
//   3. shareSheet — File 菜单 ⌘⇧E 触发 NSSharingServicePicker
//   4. onReceive(.newFolderRequested) — File 菜单 ⌘⇧N (修了 V6.20.0 silent failure)
//   5. onReceive(.speakRequested) — Edit > Speak 触发
extension View {
    @MainActor
    func smartFolderAndShareSheets(
        model: ContentViewModel,
        bindableGrid: Bindable<GridViewModel>
    ) -> some View {
        self
            .smartFolderCreateSheet(
                model: model,
                showingSheet: bindableGrid.showingNewSmartFolderSheet,
                pendingFilter: model.grid.pendingSmartFolderFilter ?? .empty
            )
            .smartFolderEditSheet(
                model: model,
                editingSmartFolder: bindableGrid.editingSmartFolder,
                pendingFilter: model.grid.pendingSmartFolderEditFilter ?? .empty
            )
            .shareSheet(model: model)
            .onReceive(NotificationCenter.default.publisher(for: .newFolderRequested)) { _ in
                model.grid.newFolderName = ""
                model.grid.showingNewFolderAlert = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .speakRequested)) { _ in
                model.grid.speakSelection()
            }
    }
}

// MARK: - V6.22.3 (P2 #10): Onboarding sheet extension
//
// V6.70 (Onboarding removal): 删 onboardingSheet extension — 新手引导取消
//   之前 15 行 (含 1 个 bindable getter + OnboardingView 调用)
//   现在直接 0 行, 整 extension 删
//   对应 OnboardingView.swift 已删, hasSeenOnboarding 字段下一步删
//   替代: 用户首启动直接看到 PhotoGridEmptyState + 导入 CTA (V6.21.2)

// MARK: - V3.5.18: 设置面板 chrome helper (从 ContentView+SettingsChrome.swift 合并过来)
//
// V6.05: 合并到 ContentView+Lifecycle.swift——co-located with usage (line ~166 .applySettingsChrome)
//   删独立的 ContentView+SettingsChrome.swift 文件
//   之前 V5.51-2 抽出来是为避免 ContentView.swift body 链 type-check 超时
//   现在 ContentView.swift 已经分段 (ContentView+Lifecycle/ToolbarSync/... 6 个文件)
//   单独文件 27 行冗余, 合并到本文件让相关 chrome helper 集中
//
// V4.13.0: 撤回 onOpenSettings + showSettings 参数——⌘, 现在走 Settings scene
//   独立 Preferences 窗口（macOS 标准），不再需要 ContentView sheet 路径
//   简化后只应用强调色（.tint + .environment(\.appAccent)）
extension View {
    func applySettingsChrome(tintColor: Color) -> some View {
        self
            .tint(tintColor)
            .environment(\.appAccent, tintColor)
    }
}