//
//  MainSplitView.swift
//  ImageGallery
//
//  三列布局：侧栏 / 内容 / 详情。
//  V3.5.17：从 ContentView.swift 拆出。
//
//  V6.62: NavigationSplitView 改造
//   - 用 NavigationSplitView 替代自定义 HStack + ColumnDragHandle
//   - NavigationSplitView 原生管理：
//     * 侧边栏显隐（工具栏 sidebar.leading 按钮 + ⌘⌥S）
//     * 列宽拖拽调整
//     * 侧边栏进出动画
//
//  子视图通过 @ViewBuilder 闭包传入，由 ContentView 在调用处构造。
//

import SwiftUI
import UniformTypeIdentifiers

/// V6.62: SwiftUI 工具栏动作合集 — 替代 AppKit NSToolbar 回调链
/// V6.74.5: 删 onToggleDetail — 用户不要 toolbar 上 ⓘ 按钮, 详情面板走 ⌘I/⌘⌃D 菜单 Toggle
struct ToolbarActions {
    var onImport: () -> Void = {}
    var onExport: () -> Void = {}
    var onDelete: () -> Void = {}
    var onQuickLook: () -> Void = {}
    var onToggleFilter: () -> Void = {}
    var onToggleSortDirection: () -> Void = {}
}

struct MainSplitView<Sidebar: View, Center: View>: View {
    /// V6.62: SwiftUI 工具栏动作
    let toolbarActions: ToolbarActions

    // V6.113: 删 @Binding showDetail — 主页面详情面板完全移除
    //   想看详情: 走 immersive ⓘ drawer (V6.111 实施)

    // V6.113: 删 @State columnVisibility — NavigationSplitView 替换成 HStack
    //   showSidebar @Binding 直接控制 sidebar 显示, 不再需要 columnVisibility 双向同步
    //   toolbar ⌘\ → ContentView 改 showSidebar → .frame(条件) → sidebar 隐藏
    @Binding var showSidebar: Bool
    @Binding var searchText: String
    @Binding var sortOption: SortOption
    @Binding var viewMode: ViewMode
    @Binding var thumbnailSize: Double
    @Binding var filterState: FilterState
    @Binding var selectionEmpty: Bool
    @Binding var selectionSingle: Bool
    @Binding var importProgress: Double
    @Binding var recentSearches: [String]
    // V6.74.4: onSearchSubmit 闭包 — 用户回车时调, ContentView 注入 { model.grid.recordRecentSearch($0) }
    let onSearchSubmit: (String) -> Void
    let allFolders: [Folder]
    let allTags: [Tag]
    @State private var showingFilter = false
    @State private var showingSortPopover = false
    @State private var showingViewPopover = false
    @Binding var isDropTargeted: Bool
    @Binding var isBoxSelecting: Bool

    let onDrop: ([NSItemProvider]) -> Bool
    let sidebar: Sidebar
    let center: Center
    // V6.113: 删 let detail: Detail — 主页面详情面板完全移除
    //   走 immersive ⓘ drawer (V6.111 实施) 查看详情

    init(
        // V6.113: 删 showDetail: Binding<Bool> — 主页面详情面板完全移除
        isDropTargeted: Binding<Bool>,
        isBoxSelecting: Binding<Bool>,
        onDrop: @escaping ([NSItemProvider]) -> Bool,
        toolbarActions: ToolbarActions = ToolbarActions(),
        searchText: Binding<String> = .constant(""),
        sortOption: Binding<SortOption> = .constant(.importedAtDesc),
        viewMode: Binding<ViewMode> = .constant(.grid),
        thumbnailSize: Binding<Double> = .constant(200),
        filterState: Binding<FilterState> = .constant(.empty),
        selectionEmpty: Binding<Bool> = .constant(true),
        selectionSingle: Binding<Bool> = .constant(false),
        importProgress: Binding<Double> = .constant(0),
        recentSearches: Binding<[String]> = .constant([]),
        onSearchSubmit: @escaping (String) -> Void = { _ in },
        allFolders: [Folder] = [],
        allTags: [Tag] = [],
        // V6.103.5: 重新加 showSidebar @Binding (跟 @State columnVisibility 双向 onChange 同步)
        //   之前 V6.103.5 试过 @State + onToggleSidebar 闭包, 但 ContentView 不能访问
        //   MainSplitView 私有 @State → 闭包无法直接同步 columnVisibility, 失败
        //   现在用 @Binding + onChange 双向同步 (条件判断避免循环)
        showSidebar: Binding<Bool> = .constant(true),
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder center: () -> Center
        // V6.113: 删 detail: () -> Detail 参数
    ) {
        self.toolbarActions = toolbarActions
        // V6.113: 删 self._showDetail = showDetail
        self._showSidebar = showSidebar
        self._searchText = searchText
        self._sortOption = sortOption
        self._viewMode = viewMode
        self._thumbnailSize = thumbnailSize
        self._filterState = filterState
        self._selectionEmpty = selectionEmpty
        self._selectionSingle = selectionSingle
        self._importProgress = importProgress
        self._recentSearches = recentSearches
        self.onSearchSubmit = onSearchSubmit
        self.allFolders = allFolders
        self.allTags = allTags
        self._isDropTargeted = isDropTargeted
        self._isBoxSelecting = isBoxSelecting
        self.onDrop = onDrop
        self.sidebar = sidebar()
        self.center = center()
        // V6.113: 删 self.detail = detail() — 字段已删
    }

    /// V6.103.5: 改 columnVisibility @State 本地源 (NS 自己 manage)
    ///   之前 4 commit 用 binding 链都失败, Phase 3 方案 A: @State + onChange 反向同步
    ///   toolbar ⌘\ → onToggleSidebar 闭包 → ContentView 改 model.settings.showSidebar
    ///   闭包同步调 columnVisibility = .detailOnly / .all (绕过 binding)
    ///   onChange 反向写回 model.settings.showSidebar (持久化)

    // V6.84: toolbar items 抽成 @ToolbarContentBuilder computed — 减少 body 链 type-check 压力
    //   .toolbarBackground(.bar) + .toolbarRole(.editor) 触发 SwiftUI 推断递归, 拆开避免 60s 超时
    //   (memory V6.28 ContentView type-check timeout 同源教训 — 拆 modifier 链)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { toolbarActions.onExport() } label: {
                Label("导出", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
            }.help("导出")
        }
        ToolbarItem {
            Button { toolbarActions.onDelete() } label: {
                Label("删除", systemImage: "trash").labelStyle(.iconOnly)
            }.disabled(selectionEmpty).help("删除")
        }
        ToolbarItem {
            Button { toolbarActions.onQuickLook() } label: {
                Label("预览", systemImage: "eye").labelStyle(.iconOnly)
            }.disabled(selectionEmpty || !selectionSingle).help("快速查看 (空格)")
        }
        ToolbarItem {
            Button { showingFilter.toggle() } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease.circle").labelStyle(.iconOnly)
            }.help("筛选")
            .overlay(alignment: .topTrailing) {
                if filterState.isActive {
                    Text("\(filterState.activeCount)")
                        .font(Typography.badge).foregroundStyle(.white)
                        .padding(Spacing.xs).background(Color.red).clipShape(Circle())
                        .offset(x: 8, y: -8)
                }
            }
            .popover(isPresented: $showingFilter) {
                FilterPanelView(filterState: $filterState, folders: allFolders, tags: allTags, onClose: { showingFilter = false })
            }
        }
        ToolbarItem {
            Button { showingSortPopover.toggle() } label: {
                Label("排序", systemImage: sortOption.toolbarIcon).labelStyle(.iconOnly)
            }.help("排序")
            .popover(isPresented: $showingSortPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    sortFieldRow(icon: "calendar", name: "导入时间",
                                  isActive: sortOption == .importedAtDesc || sortOption == .importedAtAsc,
                                  direction: sortOption == .importedAtDesc ? "↓ 最新" : sortOption == .importedAtAsc ? "↑ 最早" : nil)
                        .onTapGesture {
                            if sortOption == .importedAtDesc { sortOption = .importedAtAsc }
                            else { sortOption = .importedAtDesc }
                            showingSortPopover = false
                        }
                    sortFieldRow(icon: "doc", name: "文件名",
                                  isActive: sortOption == .filenameDesc || sortOption == .filenameAsc,
                                  direction: sortOption == .filenameDesc ? "↓ Z→A" : sortOption == .filenameAsc ? "↑ A→Z" : nil)
                        .onTapGesture {
                            if sortOption == .filenameDesc { sortOption = .filenameAsc }
                            else { sortOption = .filenameDesc }
                            showingSortPopover = false
                        }
                    sortFieldRow(icon: "externaldrive.fill", name: "文件大小",
                                  isActive: sortOption == .fileSizeDesc || sortOption == .fileSizeAsc,
                                  direction: sortOption == .fileSizeDesc ? "↓ 最大" : sortOption == .fileSizeAsc ? "↑ 最小" : nil)
                        .onTapGesture {
                            if sortOption == .fileSizeDesc { sortOption = .fileSizeAsc }
                            else { sortOption = .fileSizeDesc }
                            showingSortPopover = false
                        }
                    Divider().padding(.vertical, 2)
                    sortFieldRow(icon: "arrow.up.arrow.down", name: "自定义排序",
                                  isActive: sortOption == .customOrder, direction: nil)
                        .onTapGesture { sortOption = .customOrder; showingSortPopover = false }
                }.padding(Spacing.sm).frame(width: 200)
            }
        }
        ToolbarItem {
            Button { showingViewPopover.toggle() } label: {
                Label("视图", systemImage: viewMode.icon).labelStyle(.iconOnly)
            }.help("视图模式")
            .popover(isPresented: $showingViewPopover) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ViewMode.allCases) { mode in
                        Button { viewMode = mode; showingViewPopover = false } label: {
                            Label(mode.label, systemImage: mode.icon).font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(mode == viewMode ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(4)
                    }
                }.padding(Spacing.xs + 2).frame(width: 140)
            }
        }
        // V6.79: toolbar 缩略图大小控件 — 1 个 Slider 替代 +- 两个 button
        //   绑 settings.thumbnailSize (持久化), 100...250 step 10 (跟 Settings 一致)
        //   SettingsView slider 已删 (V6.79.2), toolbar 唯一入口
        //   Photos 真版 view options 模式: toolbar 内嵌 slider (SwiftUI Slider 在 macOS 是 NSSlider)
        ToolbarItem {
            HStack(spacing: 6) {
                Slider(value: $thumbnailSize, in: 100...250, step: 10)
                    .frame(width: 120)
                    .accessibilityLabel("缩略图大小")
                    .accessibilityValue("\(Int(thumbnailSize)) px")
                Text("\(Int(thumbnailSize))")
                    .font(Typography.captionMono)
                    .foregroundStyle(Surface.textSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        ToolbarItem {
            Button { toolbarActions.onImport() } label: {
                if importProgress > 0 {
                    HStack(spacing: 4) {
                        ProgressView(value: importProgress).progressViewStyle(.linear).frame(width: 36)
                        Text("\(Int(importProgress * 100))%").font(.caption2.monospacedDigit())
                    }
                    // V6.97.6 (M1 audit fix): progress bar 切换加 transition
                    //   之前: importProgress 0↔>0 直接硬切, 2666 张导入完成时 100%→0% 闪
                    //   现在: .opacity transition 150ms 平滑切, Photos.app 真版行为
                    .transition(.opacity)
                } else {
                    Label("导入", systemImage: "square.and.arrow.down").labelStyle(.iconOnly)
                        .transition(.opacity)
                }
            }
            .help(importProgress > 0 ? "导入中..." : "导入 (⌘O)")
            // V6.97.6 (M1 audit fix): 整 button 加 animation, progress bar / icon 切换平滑
            //   之前没 animation → 完成时 importProgress 0→1→0, button label 硬切 (visible flicker)
            //   现在: value-driven animation, progress / icon 切换平滑 fade
            .animation(.easeOut(duration: 0.15), value: importProgress)
        }
        // V6.74.5: 删 .primaryAction ⓘ 按钮 — 用户不要 toolbar 上 toggle 详情面板的入口
        //   详情面板仍可通过 ⌘I / ⌘⌃D (ImageGalleryApp View menu Toggle) 控制
        //   隐藏详情面板 + showDetail toggle 路径: ImageGalleryApp.swift:323/329 Toggle menu
    }

    var body: some View {
        // V6.103.5: @State columnVisibility 本地源 — NS 自己 manage, toolbar ⌘\ 通过
        //   onToggleSidebar 闭包直接改 columnVisibility (绕过 binding 链)
        //   center ideal:800 仍生效 (V6.103.1 修复)
        // V6.113: 主页面详情面板完全移除 — 改用 HStack { sidebar + center } 简化布局
        //   走 immersive ⓘ drawer (V6.111 实施) 查看详情
        //   保留 @State columnVisibility (columnWidth 显示逻辑兼容, 实际 NavigationSplitView 已删)
        //   保留 sidebar 拖拽 / showSidebar ⌘\ toggle 行为
        HStack(spacing: 0) {
            // Sidebar — showSidebar 控显示, 跟 V6.103.5 ⌘\ / 拖边缘行为兼容
            if showSidebar {
                sidebar
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 320)
                    .transition(.opacity)
            }
            // Center — 永远占满剩余宽度
            center
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Animations.standard, value: showSidebar)
        // V6.113: 删 } detail: { if showDetail { detail... } } — 主页面详情面板完全移除
        // V6.93: 删 L243-247 重复的导出 ToolbarItem — toolbarContent 已包含导出 button (L111-113)
        //   V6.83 revert toolbar 分组时遗留的兜底代码, 一直未清, 导致 toolbar 有 2 个相同导出 button
        //   toolbarContent 是私有 @ToolbarContentBuilder 包含 9 个 ToolbarItem (导出/删除/预览/筛选/排序/视图/slider/导入/回退 export 兜底)
        //   删重复后 .toolbar { toolbarContent } 单一来源, 跟 segmented Picker(.segmented) 单一来源模式一致
        .toolbar { toolbarContent
            }.searchable(text: $searchText, placement: .toolbar, prompt: Copy.searchPlaceholder) {
            // V6.74.4: 搜索自动建议 — 显示最近 20 个搜索词 (Photos / Finder 范式)
            //   点 suggestion → searchCompletion 自动填入 searchText → 走 binding setter
            ForEach(recentSearches, id: \.self) { recent in
                Text(recent)
                    .searchCompletion(recent)
            }
            // V6.74.4: 清空最近搜索 — suggestion 末尾 button (History 概念)
            if !recentSearches.isEmpty {
                Divider()
                Button(Copy.clearRecentSearches) {
                    recentSearches = []
                }
            }
        }
        .onSubmit(of: .search) { onSearchSubmit(searchText) }
        // V6.103.5: 双向 onChange 同步 — 解决 toolbar ⌘\ + NS 拖边缘按钮 两路径同步问题
        //   showSidebar (ContentView) ↔ columnVisibility (NS @State)
        //   toolbar ⌘\ → ContentView 改 showSidebar → onChange → columnVisibility = ...
        //   NS 拖边缘 → 内部改 columnVisibility → onChange → showSidebar = ...
        //   关键: onChange 内部判断新值 ≠ 当前值才写, 避免 NS set → onChange → set 死循环
        //   NS 用 $columnVisibility binding 接受外部 set (V6.103.1/2 失败原因)
        //   现在 NS 仍然 manage 内部状态 (拖边缘按钮), 但通过 onChange 反向同步到 showSidebar
        // V6.113: 删 onChange 双向同步 columnVisibility — NavigationSplitView 替换成 HStack
        //   showSidebar 直接控制 sidebar 显示, .animation(value: showSidebar) 在 HStack 自动 animate
        .scrollDisabled(isBoxSelecting)
        // V6.85: 取消 toolbar 磨砂玻璃效果
        //   V6.84 加的 .toolbarBackground(.bar, for: .windowToolbar) 用户实测仍觉得磨砂感过重
        //   改成走系统默认 toolbar 样式 (无额外 background) — 跟 V6.80 之前 V6.62 一样
        //   保留 .toolbarRole(.editor) — editor role 影响 item 视觉锤/间距, 跟磨砂玻璃独立
        //   macOS 系统默认 toolbar 已有微妙 separator/divider, 不需要 SwiftUI 手动铺材质
        .toolbarRole(.editor)  // macOS 14+ — editor toolbar role (Photos 真版)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: onDrop)
        .overlay {
            if isDropTargeted {
                dropOverlay
                    .transition(.opacity)
            }
        }
    }

    // V6.80: 暂不引入 toolbarBackground API — SDK 签名未实测验证, 后续 V6.81+ 实施
    private func sortFieldRow(icon: String, name: String, isActive: Bool, direction: String?) -> some View {
        HStack {
            Label(name, systemImage: icon).font(.body).foregroundStyle(isActive ? .primary : .secondary)
            Spacer()
            if let dir = direction {
                Text(dir).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Material.dropOverlay)
                .opacity(0.95)
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 4, dash: [8, 4])
                )
                .padding(Spacing.sm)
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(Typography.emptyStateIconLarge)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(Copy.dropReleaseToImport)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Copy.dropSupportedTypes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }
}
