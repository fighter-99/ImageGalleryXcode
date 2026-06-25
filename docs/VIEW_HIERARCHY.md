# ImageGallery — View Hierarchy

> 视图树 + 工具栏 + 沉浸式 + sheets/popovers。
> 最后更新: V6.117 (NS 2-col form, 详情面板走 immersive drawer)

## 1. 顶层架构

```
ImageGalleryApp (SwiftUI App)
├ ImageGalleryAppDelegate (NSApplicationDelegate, 多 window frame)
├ Settings { SettingsView() }  (V6.41 Photos 真版)
├ Commands (菜单 + 12+ Notification.Name 桥接)
└ ContentView (主窗口)
   └ MainLayoutView (V3.5.17 拆出, 顶层 layout 协调)
      ├ pathBar: { pathBarPane } (V3.5.17 禁用, 空 @ViewBuilder)
      ├ split: { mainSplitPane } ← 核心
      │   └ MainSplitView (V6.117 NS 2-col form)
      │      ├ SidebarView (7 类)
      │      ├ Center:
      │      │  └ Group { switch viewMode }
      │      │     ├ .grid → PhotoGridPane
      │      │     │   └ PhotoGridView + 子组件
      │      │     ├ .list → PhotoListOrTimelinePane (kind = .list)
      │      │     └ .timeline → PhotoListOrTimelinePane (kind = .timeline)
      │      ├ Toolbar (8 个独立 ToolbarItem, V6.117)
      │      ├ .searchable (V6.74.4 recent searches)
      │      ├ Drop overlay (拖文件时全屏半透明)
      │      └ Toast (V6.29.1, 撤销 + 反馈)
      ├ undoManager / toastQueue / immersivePhoto / immersiveIndex
      ├ onImmersiveDismiss / onToastDismiss
      └ immersiveDetailContent (V6.111 沉浸式 ⓘ drawer closure)

ImmersivePhotoView (V6.111 全屏看图 + Photos 范式 ⓘ drawer)
├ chrome (顶部 工具栏 + 缩略图 + ⓘ 按钮)
├ body tap (切 chrome 显隐, V6.110.2)
├ 翻页 ←/→ (V6.110 esc 双按 fix)
└ ⓘ Drawer (Photos 范式右侧抽屉, V6.111.4)
   └ DetailPane (复用了被 main page 删的 DetailView 组件)

Sheets (浮在主窗口上)
├ CropSheet (V6.97.1)
├ MarkupSheet (V6.94.1)
├ BatchRenameSheet
├ SmartFolderCreateSheet
├ KeyboardShortcutsSheet (V6.39)
└ Alert (.alert Photos 真版, V6.45.1)

Popovers (从 toolbar 按钮弹)
├ FilterPanelView (V6.74.4 unified)
├ SortPopover (3 字段 + 自定义)
└ ViewPopover (3 ViewMode 选项)
```

## 2. 主页面布局 (V6.117 NS 2-col form)

```
┌─────────────────────────────────────────────────────────────┐
│ Toolbar (system, .toolbarRole(.editor))                      │
│  ┌──┬─────────┬──────────────────────────────────────┐       │
│  │☰ │导入    │导出  删除  预览│ 筛选  排序  视图  [▭▭]│      │
│  │  │(lead)   │(中段 6 item)              slider    │      │
│  └──┴─────────┴──────────────────────────────────────┘       │
│  ☰ = NS 系统渲染 sidebar toggle (V6.117 NS 2-col 自动)        │
│  ⌃ F = searchable 搜索框 (NS 系统渲染)                       │
├──────────────┬──────────────────────────────────────────────┤
│              │                                               │
│  Sidebar     │           Center (grid / list / timeline)      │
│  (NS 2-col)  │                                               │
│              │   ┌─────────────────────────────────────────┐ │
│  width:      │   │ 缩略图 grid (按 viewMode 切换 3 视图)    │ │
│  min 160     │   │                                          │ │
│  ideal 220   │   │  • 选中态: 蓝边框 + ⌫ badge + title 浮层  │ │
│  max 320     │   │  • 拖框选 + ⌘+ 缩放 + ⌘A 全选           │ │
│              │   │  • 右键 menu (视图/编辑/分享/删除 4 段)   │ │
│  7 类:       │   │                                          │ │
│  • Library   │   │  status bar: NS 系统渲染 (toolbar .principal)│
│  • Tags      │   │  选中时 "N selected" / 总数 "共 N 张"      │ │
│  • Folders   │   │                                          │ │
│  • Smart     │   │                                          │ │
│  • Trash     │   │                                          │ │
│              │   └─────────────────────────────────────────┘ │
└──────────────┴──────────────────────────────────────────────┘
     右边框 NS 系统渲染
     ⌘\ = 切 sidebar 显隐 (V6.103.5 pattern 双向 sync)
```

**关键事实**:
- **3 块区域**: 侧边栏 + 工具栏 + 缩略图显示区域
- **没有 detail column** (V6.117 NS 2-col form, Color.clear 占位删)
- **看详情**: 进 immersive 全屏, ⓘ 按钮开右侧 drawer

## 3. Toolbar 8 项 (V6.117)

```
[☰ NS 系统] [导入(imprt)] [导出] [删除] [预览] [筛选] [排序] [视图] [缩略图slider] [导入(progress)]
              ↓                                                                              ↑
              leading (.navigation)                                                       trailing (.primaryAction)
                            中段 (.automatic/.principal)
```

| # | Item | Placement | 回调 | 快捷键 |
|---|---|---|---|---|
| 1 | ☰ sidebar toggle | .navigation (NS 系统渲染) | `columnVisibility ↔ showSidebar` 双向 onChange | ⌘\ |
| 2 | 导入 (imprt) | leading | (decorative, 跟 .primaryAction 重复) | — |
| 3 | 导出 | 中段 | `model.grid.batchExport()` | — |
| 4 | 删除 | 中段 | `model.grid.handleDelete()` | ⌘⌫ |
| 5 | 预览 (QuickLook) | 中段 | `model.grid.enterImmersiveFromSelection()` | ⌘Y / 空格 |
| 6 | 筛选 (含 badge) | 中段 | FilterPopover (V6.74.4 unified) | — |
| 7 | 排序 | 中段 | SortPopover (3 字段 + 自定义) | ⌃⌘S |
| 8 | 视图 | 中段 | ViewPopover (3 ViewMode 选项) | — |
| 9 | 缩略图 slider | trailing (中段后) | `model.grid.thumbnailSize` (100...250 step 10) | — |
| 10 | 导入 (progress) | .primaryAction | `model.importVM.startImport()` + ProgressView | ⌘O |

**Toolbar 演化史** (memory V6.62-V6.85):
- V4.x-V6.61: AppKit NSToolbar (ToolbarController 61KB)
- V6.62: 改 SwiftUI .toolbar + ToolbarItem
- V6.74: SwiftUI .toolbar 真版, 删 NSToolbar (-1380 LOC)
- V6.80-V6.85: toolbar 材质 5 次迭代 (regularMaterial/glass/bar/clear), 最终 V6.85 取消, 走系统默认
- V6.81-V6.83: 试过分组 (5 段), 失败 revert (SwiftUI macOS .toolbar 物理 3 段限制)
- V6.84: 抽 @ToolbarContentBuilder 修 type-check, .toolbarBackground(.bar) 修框线遮挡
- V6.85: 取消磨砂玻璃, 走系统默认 (跟 Photos 视觉一致)
- **V6.117**: 8 个独立 ToolbarItem (export/delete/quicklook/filter/sort/view/slider/import)

## 4. Sidebar 7 类 (V6.117 NS 2-col form)

```
┌─────────────────────────────┐
│  Library                     │
│   📷 全部 (N)                │  V5.59 sidebarSelection default
│   📂 待整理 (N)              │  filterUnfiled
│   ⭐ 最近 7 天 (N)            │  filterRecent7Days
│   💾 大图 (N)                │  filterLargeFiles (>5MB)
│   📑 重复图 (N)              │  duplicateGroupCount
│                             │
│  Tags                        │
│   🏷 Tag1 (N)                │  P3.x tags
│   🏷 Tag2 (N)                │
│                             │
│  Folders                     │
│   📁 Folder1 (N)             │  P3.x folders
│   📁 Folder2 (N)             │
│                             │
│  Smart Folders (智能)         │  V6.18 智能文件夹
│   🧠 Smart1 (N)              │  filterData JSON
│   🧠 Smart2 (N)              │
│                             │
│  Trash                       │
│   🗑 回收站 (N)              │  V6.19 recycle bin
└─────────────────────────────┘
   右边框 NS 系统渲染
   ⌘1-9 跳转 (NS 原生 keyboard nav)
```

**实现细节**:
- List + 4 个 @Query (Folder/Tag/SmartFolder/Photo)
- 自定义 SidebarRow (hover + accent 圆角, V3.5.8 Photos 范式)
- SidebarSection 头/折叠
- List 原生 selection / drag-drop / context menu / keyboard nav (⌘1-9)

**演化史**:
- V3.5.8: Photos.app + Finder 混合风格
- V3.6.52: 改 @Binding SelectionState (跟 ContentView 单一真相源对齐)
- V6.10: 拖到 folder 注册 undo
- V6.18: 加 Smart Folders 智能文件夹
- V6.23: sidebar 视觉一致性 (智能文件夹独立 section + chevron menu 入口)
- V6.116: 删 V6.115 锦上添花 (Divider overlay + SidebarStatusBar)
- **V6.117**: NS 2-col form, 系统渲染 toggle/status bar/边框

## 5. Center 三视图 (V6.114 统一 grid layout)

### 5.1 .grid — PhotoGridPane

```
PhotoGridPane (V5.29 拆分)
├ PhotoGridView (调度)
│  ├ PhotoGridLayoutView (Masonry 布局)
│  ├ PhotoCellContent (单 cell UI)
│  ├ PhotoThumbnailView (缩略图 + shimmer)
│  ├ CellContextMenuModifier (右键菜单)
│  └ Drag 圈选 / 多选 / 拖入
├ PhotoGridEmptyState (空态)
├ PhotoGridLoadingState (加载态)
└ +Preview / +Reorder extensions
```

**V6.114 跟 timeline 共享 grid 布局**:
- 用 `SquareLayout.cellSize` + `GridLayout.computeRows` + `PhotoCellContent`
- timeline 删 80 行 TimelineThumbnail struct
- grid / timeline 像素级一致

### 5.2 .list — PhotoListOrTimelinePane (kind = .list)

```
PhotoListOrTimelinePane
├ List (V5.60-3 合并, 1 个 Pane + kind 路由, 节省 88 行)
├ PhotoRowView (单行 UI)
└ DateSectionHeader (日期分组)
```

### 5.3 .timeline — PhotoListOrTimelinePane (kind = .timeline)

```
PhotoListOrTimelinePane (kind = .timeline)
├ List 按月份分组
├ TimelineMonthSection
│  └ PhotoGridLayoutView (V6.114 复用 grid Masonry)
│     + PhotoCellContent
└ DateSectionHeader
```

**V6.31.1 切换动画**: crossfade + scale 0.95→1 (Photos.app 范式)。

## 6. Immersive View (V6.111-V6.110.2)

### 6.1 触发

- 工具栏 ⌘Y 快速查看 → `model.grid.enterImmersiveFromSelection()`
- 双击 photo (V6.39.1, default .immersive) → `handlePhotoDoubleTap` → `enterImmersive`
- cell context menu "快速查看"

### 6.2 视图树

```
ImmersivePhotoView
├ chrome (顶部)
│  ├ 关闭按钮 (X)
│  ├ 缩略图 (右下小窗, 1/8 大小, Photos 范式)
│  └ ⓘ 按钮 (右上, V6.111)
│     └ onTap → drawer.toggle()
├ body tap (V6.110.2: 切 chrome 显隐, 不关 drawer)
│  └ @FocusState + .focusEffectDisabled(true) 避免双按 focus ring
├ 翻页 ←/→ (键盘)
└ ⓘ Drawer (V6.111.4 Photos 范式右侧抽屉)
   └ DetailPane (复用被 main page 删的 DetailView)
      ├ ImageCard
      ├ InfoCard
      ├ OperationsCard
      └ TagsCard
```

### 6.3 关键约束

- **V6.110.2 esc 双按 fix**: @FocusState + .focused + .focusEffectDisabled(true)
- **V6.111.5 body tap 不关 drawer**: 之前 V6.111 错 (点 body 也关 drawer), 现在只切 chrome
- **V6.111.4 drawer 内容**: 不再显示大图 (跟主页面区分), 只显示 info / operations / tags

## 7. Sheets

| Sheet | V | 触发 | 用途 |
|---|---|---|---|
| CropSheet | V6.97.1 | Edit menu ⌘⇧K / cell right-click | 9 handles 裁剪 |
| MarkupSheet | V6.94.1 | Edit menu ⌘M / cell right-click | PencilKit 标注 (自绘 NSBezierPath) |
| BatchRenameSheet | V3.5.x | toolbar / cell right-click | 模板批量重命名 |
| SmartFolderCreateSheet | P4.1 | sidebar + button / "另存为智能文件夹" | 创建智能文件夹 |
| KeyboardShortcutsSheet | V6.39 | Help menu | 快捷键速查 |

## 8. Popovers

| Popover | 触发 | 用途 |
|---|---|---|
| FilterPanelView (V6.74.4 unified) | toolbar 筛选按钮 | 7 维 filter (folder/tag/shape/rating/size/...) |
| SortPopover | toolbar 排序按钮 | 3 字段 (导入时间/文件名/文件大小) + 自定义排序 |
| ViewPopover | toolbar 视图按钮 | 3 ViewMode 选项 (grid/list/timeline) |

**V6.29.2**: Filter 按钮加 active badge (红点 + count, 选中态 Photos 真版)

## 9. Alert (.alert Photos 真版, V6.45.1)

3 个 destructive 操作改 `.confirmationDialog` → `.alert` (NSAlert 包装):
- 删除选中
- 清空回收站
- 重置 Onboarding

`.confirmationDialog` 是 iOS 风格 action sheet, 跟 Photos dialog 不一致 → 改 `.alert` macOS 真版。

## 10. Drop Overlay (V3.x)

```swift
.overlay {
    if isDropTargeted {
        dropOverlay
            .transition(.opacity)
    }
}

private var dropOverlay: some View {
    ZStack {
        Rectangle()
            .fill(Material.dropOverlay)
            .opacity(0.95)
        RoundedRectangle(cornerRadius: Radius.lg)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 4, dash: [8, 4]))
            .padding(Spacing.sm)
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(Typography.emptyStateIconLarge)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text(Copy.dropReleaseToImport)
            Text(Copy.dropSupportedTypes)
        }
    }
    .allowsHitTesting(false)
}
```

拖文件到主窗口时全屏半透明 overlay, 提示用户松手导入。

## 11. Toast 体系 (V6.29.1)

```
ToastInfo (struct, Models/ToastInfo.swift)
├ message: String
├ type: ToastView.ToastType (.info / .success / .error / .warning)
├ duration: ToastInfo.Duration (.short 2s / .long 5s / .indefinite)
└ undoAction: (() -> Void)? (V6.29.1 撤销按钮)

ToastView (Views/ToastView.swift)
├ 浮在主窗口底部居中
├ 自动 dismiss (Task.sleep)
├ close button (V6.21.1)
└ undo button (V6.29.1, Photos 真版)
```

**触发场景**:
- 导入完成 (成功/失败)
- 批量删除 (撤销)
- 批量重命名 (撤销)
- 批量移动 (撤销)
- 评分 (撤销)
- 旋转 (撤销)
- Trash 恢复 (撤销)
- 错误 (e.g. SidebarView drag-drop silent fail-open, V6.62)

## 12. Status Bar (V6.117 NS 系统渲染)

NS NavigationSplitView **自动渲染** sidebar status bar 在 toolbar `.principal` 段:
- 0 选: 总数 "共 N 张"
- N 选: "已选 N 张" + 总大小
- Trash: 回收站大小

之前 V6.115 手工实现的 SidebarStatusBar (V6.116 删)。

## 13. 关键 View 模式

### 13.1 ViewBuilder 闭包注入 (V6.111+)

```swift
struct MainLayoutView<PathBar, Split>: View {
    let pathBar: () -> PathBar
    let split: () -> Split
    ...
}

// ContentView.swift
MainLayoutView(
    pathBar: { pathBarPane },
    split: { mainSplitPane },
    immersiveDetailContent: immersiveDetailContent
)
```

**用途**: V6.111 immersive ⓘ drawer closure 注入, 让 ImmersivePhotoView 顶部 chrome 显示 ⓘ 按钮, 翻页时 drawer 自动跟新。

### 13.2 @State + @Binding 双向 sync (V6.103.5)

```swift
@State private var columnVisibility: NavigationSplitViewVisibility = .all
@Binding var showSidebar: Bool

.onChange(of: showSidebar) { _, newValue in
    let newVisibility: NavigationSplitViewVisibility = newValue ? .all : .detailOnly
    if columnVisibility != newVisibility {  // 条件判断避免循环
        columnVisibility = newVisibility
    }
}
.onChange(of: columnVisibility) { _, newValue in
    let newShowSidebar = (newValue != .detailOnly)
    if showSidebar != newShowSidebar {  // 条件判断避免循环
        showSidebar = newShowSidebar
    }
}
```

V6.103.1-3 unconditional binding.write 跟 NS 内部 diff 冲突 → 死循环; V6.103.5 加条件判断修复。

### 13.3 @FocusState 焦点 (V6.110.2)

```swift
@FocusState private var isPhotoFocused: Bool

Image(...)
    .focused($isPhotoFocused)
    .focusEffectDisabled(true)  // 避免双按 focus ring
    .onAppear {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isPhotoFocused = true
        }
    }
```

V6.110.2 修 esc 双按 bug, 0.05s asyncAfter 避免 window focus 未稳定。

### 13.4 @ToolbarContentBuilder (V6.84)

```swift
@ToolbarContentBuilder
private var toolbarContent: some ToolbarContent {
    ToolbarItem { ... }
    ToolbarItem { ... }
    ...
}
```

V6.84 抽 toolbar items 修 type-check 超时, 跟 V6.28 ContentView type-check timeout 同源教训 (拆 modifier 链)。

## 14. 关键约束清单

- [x] ContentView 不持业务 @State (仅 2 transient UI state)
- [x] View 通过 Bindable(model).X 拿 binding
- [x] 业务状态全在 model (V6.28 大拆分)
- [x] 工具栏 8 项 (V6.117 flat, 不用 ToolbarItemGroup 分组)
- [x] NS 2-col form (V6.117, 无 detail column)
- [x] 详情走 immersive ⓘ drawer (V6.111)
- [x] ⌘\ 切 sidebar (V6.103.5 pattern)
- [x] ViewBuilder 闭包注入 (V6.111 immersiveDetailContent)
- [x] @FocusState + .focusEffectDisabled (V6.110.2)

## 15. 相关文档

- `ARCHITECTURE.md` — 高层架构 + 模块划分
- `STATE_MANAGEMENT.md` — ContentViewModel + 3 子 + binding pattern
- `DATA_MODEL.md` — SwiftData entities + UserSettings

## 16. 更新记录

| Date | V | 摘要 |
|---|---|---|
| 2026-06-25 | V6.117 | 初版, NS 2-col form, 详情面板走 immersive drawer, toolbar 8 项, sidebar 7 类, immersive ⓘ drawer 体系, sheets/popovers 全面梳理 |
