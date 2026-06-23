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

struct MainSplitView<Sidebar: View, Center: View, Detail: View>: View {
    /// V6.62: SwiftUI 工具栏动作
    let toolbarActions: ToolbarActions
    
    @Binding var showDetail: Bool
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
    let detail: Detail

    init(
        showDetail: Binding<Bool>,
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
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder center: () -> Center,
        @ViewBuilder detail: () -> Detail
    ) {
        self.toolbarActions = toolbarActions
        self._showDetail = showDetail
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
        self.detail = detail()
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 320)
        } content: {
            center
        } detail: {
            if showDetail {
                detail
                    .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 500)
            }
        }
        .toolbar {
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
                            .padding(4).background(Color.red).clipShape(Circle())
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
                    }.padding(8).frame(width: 200)
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
                    }.padding(6).frame(width: 140)
                }
            }
            // V6.79: toolbar 缩略图大小控件 — 1 个 Slider 替代 +- 两个 button
            //   绑 settings.thumbnailSize (持久化), 100...250 step 10 (跟 Settings 一致)
            //   SettingsView slider 已删 (V6.79.2), toolbar 唯一入口
            //   Photos 真版 view options 模式: toolbar 内嵌 slider
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
                    } else {
                        Label("导入", systemImage: "square.and.arrow.down").labelStyle(.iconOnly)
                    }
                }
                .help(importProgress > 0 ? "导入中..." : "导入 (⌘O)")
            }
            // V6.74.5: 删 .primaryAction ⓘ 按钮 — 用户不要 toolbar 上 toggle 详情面板的入口
            //   详情面板仍可通过 ⌘I / ⌘⌃D (ImageGalleryApp View menu Toggle) 控制
            //   隐藏详情面板 + showDetail toggle 路径: ImageGalleryApp.swift:323/329 Toggle menu
        }        .searchable(text: $searchText, placement: .toolbar, prompt: Copy.searchPlaceholder) {
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
        .scrollDisabled(isBoxSelecting)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: onDrop)
        .overlay {
            if isDropTargeted {
                dropOverlay
                    .transition(.opacity)
            }
        }
    }

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
            RoundedRectangle(cornerRadius: 12)
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
