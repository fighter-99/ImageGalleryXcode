# ImageGallery — Architecture

> 高层架构 + 模块划分。代码级状态查询以本文档为准。
> 最后更新: V6.117 (NS 2-col form, 详情面板主页面移除)

## 1. 概述

**ImageGallery** 是 macOS native 照片管理 app, 目标平台 macOS 15.5+ (Sequoia), SwiftUI + SwiftData, 纯原生无 Sandbox/无 Hardened Runtime (开发阶段本地签名 `Sign to Run Locally`)。

**核心特性** (按"我们做什么"组织):
- 3 视图 (grid / list / timeline) 浏览 SwiftData 库
- 7 类侧边栏 (Library/Tags/Folders/Smart/Trash)
- 沉浸式看图 (V6.110 ⓘ 按钮 + ⓘ drawer)
- 撤销/重做 (自写 ImageGalleryUndoManager, V6.14.10)
- 缩略图 / 元数据缓存 (ThumbnailCache + CroppedThumbnailCache)
- 回收站 (RecycleBinService 软删除 + 保留天数清理)
- i18n (en + zh-Hans, 320KB xcstrings)
- 8 项 SwiftUI toolbar (V6.80+, V6.117 当前)
- URL scheme 桥接 Siri/Shortcuts (V6.97.2)

**核心非特性** (明确不做):
- ~~人脸识别~~ / ~~地图视图~~ (V6.18 决策 P3+ 推)
- ~~EXIF 编辑~~ (V6.18 P0 取消)
- ~~Aperture/iPhoto import~~ (历史不支持)
- ~~Document-based / Sandbox~~ (V6.18 战略级, 1-2 周, 尚未实施)

## 2. 架构总览 (5 层)

```
┌──────────────────────────────────────────────────────────┐
│  Layer 1: App 入口                                         │
│    ImageGalleryApp.swift (SwiftUI App + AppDelegate)      │
│    WindowAccessor.swift (NSWindow 桥)                      │
│    Settings { SettingsView() } scene                       │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  Layer 2: ContentView 顶层装配                             │
│    ContentView.swift (800 行, 仅 2 个本地 @State)           │
│      ├→ MainSplitView (NS 2-col, 工具栏, 搜索)             │
│      │    ├→ SidebarView (7 类导航)                         │
│      │    └→ Center: PhotoGridView / PhotoListOrTimeline  │
│      ├→ ImmersivePhotoView (全屏看图 + ⓘ drawer)           │
│      └→ 各种 sheet (Crop/Markup/Rename/Smart/...)           │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  Layer 3: State (State of truth)                           │
│    ContentViewModel (根, ~600 行)                          │
│      ├→ grid: GridViewModel (~900 行, V6.28 NEW)            │
│      ├→ importVM: ImportViewModel (V6.28.1 NEW)            │
│      └→ windowVM: WindowViewModel (V6.74.2 NEW)            │
│    + UserSettings (@Observable, UserDefaults 双写)          │
│    + SwiftData @Query (sidebar/grid 直接拉)                │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  Layer 4: Models + Services                                │
│    Models: Photo / Folder / Tag / SmartFolder (SwiftData)  │
│    Services: ImageImporter / ThumbnailCache /              │
│              RecycleBinService / CrashReporter /           │
│              ImageGalleryUndoManager / MarkupService /     │
│              PhotoCropService / PhotoStorage               │
│    Pure: PhotoStats / PhotoSearch / GridLayout /           │
│          MasonryMath / BatchRenameTemplate / ...           │
└──────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────┐
│  Layer 5: Platform                                         │
│    SwiftData (V1+V2 VersionedSchema, 暂不开 V3)             │
│    AppKit (NSWindow/NSViewRepresentable/NSCache/NSWorkspace)│
│    ImageIO (EXIF + CGImageSource) / AVFoundation (TTS)     │
│    CryptoKit (SHA256 fileHash) / UniformTypeIdentifiers    │
│    PencilKit (via NSBezierPath) / os.Logger                │
└──────────────────────────────────────────────────────────┘
```

**核心原则**:
- 业务状态全在 model (Layer 3), View 不持业务 @State (ContentView 仅 2 个 transient UI state)
- 状态变化驱动 View 重渲 (`@Observable` + SwiftUI 自动 diff)
- View 通过 `Bindable(model).X` 拿 binding, 不直接写 model
- Service 是 stateless + MainActor, model 调 service 完成业务

## 3. 模块清单 (按目录)

### 3.1 根目录 (`ImageGallery/ImageGallery/*.swift`)

| 文件 | 职责 | LOC |
|---|---|---|
| `ImageGalleryApp.swift` | SwiftUI App 入口, AppDelegate (多 window frame), 12+ Notification.Name 桥接菜单 | ~700 |
| `ContentView.swift` | 顶层视图装配, 2 个本地 @State, mainSplitPane/sidebarPane/gridPane/immersivePane | ~800 |
| `ImageImporter.swift` | 主导入器, ImportProgress struct | ~600 |
| `ImageLoader.swift` | async 图片加载, 调 ThumbnailCache | ~400 |
| `ThumbnailCache.swift` | NSCache (400MB + 1500 count cap) + OSAllocatedUnfairLock | ~300 |
| `CroppedThumbnailCache.swift` | V6.97.1 crop 后缩略图独立 cache | ~150 |
| `ImageGalleryUndoManager.swift` | 自写 undo/redo stack (50 步 + 1s 合并), V6.14.10 替 Foundation | ~250 |
| `RecentPhotosStore.swift` | File > Open Recent 菜单数据源 | ~100 |
| `SortOption.swift` | 排序 enum | ~80 |
| `ThumbnailDensity.swift` | 缩略图密度 | ~50 |
| `SwiftDataLogging.swift` | ModelContext saveWithLog 扩展 | ~80 |
| `WindowAccessor.swift` | NSViewRepresentable 桥 NSWindow (V6.74.2 改 no-op fallback) | ~80 |
| `Localizable.xcstrings` | String Catalog 320KB, en + zh-Hans | 8184 行 |
| `Info.plist` | URL scheme `imagegallery://` (Shortcuts) | — |

### 3.2 Models (`ImageGallery/Models/`)

**SwiftData 实体** (V1+V2):
- `Photo.swift` (~500 行) — UUID PK, 12+ 字段 (filename/importedAt/folder/tags/fileHash/fileSize/width/height/isInTrash/markup/cropRect/...)
- `Folder.swift` — UUID PK, name + photos
- `Tag.swift` — UUID PK, name + photos
- `SmartFolder.swift` — V2 加 (P4.1), filterData: Data (FilterState JSON)

**State**:
- `Settings.swift` (~370 行) — UserSettings @Observable, 22 字段 (see DATA_MODEL.md)

**Schema**:
- `ImageGallerySchema.swift` — V1 + V2 VersionedSchema
- `ImageGalleryMigrationPlan.swift` — migration plan
- `SwiftDataLogging.swift` — saveWithLog error helper

**Enums + 纯函数** (37 个, 主要是 enum 和 struct):
- `AccentColor` / `AppearanceMode` / `Language` / `FontScale`
- `SortOption` / `ViewMode` / `ThumbnailLayoutMode` / `ThumbnailDensity`
- `SidebarSelection` / `SelectionState` / `FilterState` / `ToastInfo`
- `ExportFormat` / `TrashRetentionDays` / `DoubleClickAction` / `CropAspect` / `CropRect`
- `BatchRenameTemplate` / `BatchSetRatingMath` / `RatingShortcuts` / `RatingStarsMath`
- `PhotoShape` / `PhotoOrientation` / `PhotoDragItem`
- `GridLayout` / `SquareLayout` / `MasonryMath` / `MultiSelectMath` / `OptionListItem`
- `PhotoStats` (enum) / `PhotoStatsSnapshot` (V6.19.2 7 维单遍)
- `PhotoSearch` / `Term`
- `Copy.swift` (~600 行) — UI 字符串集中 enum (i18n key 来源)
- `ImageGalleryIntents.swift` / `ImageGalleryShortcuts.swift` — Siri/Shortcuts App Intents
- `MarkupService.swift` — PencilKit 标注 (NSBezierPath plist)
- `PhotoCropService.swift` — V6.97.1 裁剪服务 (CropRect JSON)

**根 ViewModel**:
- `ContentViewModel.swift` (~600 行, V6.28 拆分) — 根 @Observable, 持 grid/importVM/windowVM

**子 ViewModel**:
- `GridViewModel.swift` (~900 行, V6.28 NEW) — 网格业务 + 4 个 extension 拆文件
- `GridViewModel+BatchOps.swift` / `+BatchRename.swift` / `+Operations.swift` — extension
- `ImportViewModel.swift` (~260 行, V6.28.1 NEW) — 导入业务
- `WindowViewModel.swift` (~185 行, V6.74.2 大幅简化) — window chrome 业务

### 3.3 Services (`ImageGallery/Services/`)

| 文件 | 职责 | LOC |
|---|---|---|
| `CrashReporter.swift` | @_cdecl handler + POSIX signals, 写 ~/Library/Logs/ImageGallery/ | ~150 |
| `PhotoStorage.swift` | 路径管理, Application Support/ImageGallery/Photos/ (fallback ~/Pictures) | ~150 |
| `RecycleBinService.swift` | @MainActor, recycle/restore/purge/purgeExpired, 保留天数清理 | ~300 |

### 3.4 Views (`ImageGallery/Views/`)

**顶层**:
- `MainSplitView.swift` (~400 行, V6.117 NS 2-col form) — 主分屏, ToolbarActions struct 集中回调
- `SidebarView.swift` (~700 行) — 7 类侧栏, 4 个 @Query
- `SidebarRow.swift` — 自定义行样式 (hover + accent)
- `Sidebar/SidebarSection.swift` — section 头/折叠
- `PhotoGridView.swift` (~250 行) — 网格入口
- `PhotoGridLayoutView.swift` / `PhotoGridPane.swift` / `PhotoGridEmptyState.swift` / `PhotoGridLoadingState.swift` / `PhotoGridView+Preview.swift` / `PhotoGridView+Reorder.swift` — Grid 子组件
- `PhotoListOrTimelinePane.swift` — list/timeline (kind enum 切换)
- `Grid/GridLayoutEngine.swift` — 纯函数 Masonry 布局算法
- `ImmersivePhotoView.swift` (~600 行) — 全屏看图 + Photos 范式右侧 drawer
- `DetailPane.swift` (11.8KB) — **未删**, 仅 ImmersivePhotoView 内部用 (V6.111)
- `DetailView.swift` / `+ImageCard.swift` / `+InfoCard.swift` / `+OperationsCard.swift` / `+TagsCard.swift` / `DetailViewComponents.swift` — 详情组件
- `MultiSelectDetailView.swift` / `TrashDetailView.swift` / `DuplicatesDetailView.swift` — 3 mode-specific 详情
- `SettingsView.swift` (~1100 行) — 主入口, V6.41 Photos 真版
- `SettingsView+Components.swift` / `+Panels.swift` — 子组件拆分
- `ContentView+BatchDialogs.swift` / `+GridInput.swift` / `+Lifecycle.swift` — ContentView extension
- `ContentKeyboardShortcuts.swift` / `ShortcutsHandler.swift` — 快捷键

**Sheet**:
- `CropSheet.swift` / `MarkupSheet.swift` / `BatchRenameSheet.swift` / `SmartFolderCreateSheet.swift` / `KeyboardShortcutsSheet.swift`

**Filter UI**:
- `FilterPanelView.swift` / `ActiveFiltersBar.swift` / `FilterPopover/*` (4 popover 组件)

**Popover 体系**:
- `PopoverChrome.swift` / `PopoverItemFactory.swift` / `OptionListPopoverController.swift` / `FilterPopover/FilterUnifiedPopoverController.swift` / `FilterPopoverCoordinator.swift` / `CategoryRowView.swift` / `RatingRowView.swift`

**Feedback**:
- `EmptyStateView.swift` / `ToastView.swift`

**通用修饰符和组件**:
- `VisualEffectMaterial.swift` / `PressableButtonStyle.swift` / `HighlightedText.swift`
- `BoxSelectionGesture.swift` / `BoxSelectionOverlay.swift` / `TrackpadGestureModifier.swift`
- `ColumnDragHandle.swift` (V6.117 后未用) / `DateSectionHeader.swift` / `DropTargetHighlight.swift`
- `CellContextMenuModifier.swift` / `PhotoCellContent.swift` / `PhotoRowView.swift`
- `PhotoThumbnailView.swift` / `ThumbnailEffects.swift`
- `Lifecycle/DialogModifier.swift` / `KeyboardModifier.swift` / `NotificationModifier.swift` / `SheetModifier.swift` / `LifecycleModifiers.swift`

### 3.5 Design Tokens

- `DesignTokens.swift` (~50KB) — 颜色/间距/字体/圆角/动画 token, Photos 范式 Surface/Accent/Text 颜色组
- `Copy.swift` — 静态文案 enum (i18n key 来源)
- `Localizable.xcstrings` — 320KB 字符串目录 (en + zh-Hans)

### 3.6 关键已删模块 (历史)

- ~~`ToolbarController.swift`~~ (61KB) — V6.74.2 删, NSToolbar 死代码
- ~~`TitlebarAccessoryController.swift`~~ — V6.74.2 删
- ~~`TitlebarAccessoryView.swift`~~ — V6.74.2 删
- ~~`SidebarStatusBar` (SidebarView 内)~~ — V6.116 删
- ~~`SidebarDivider` overlay~~ — V6.116 删
- ~~`showDetail` / `detailColumnWidth` UserSettings 字段~~ — V6.113 删
- ~~`CommandGroup(after: .sidebar) { Toggle showDetail }`~~ — V6.113 删

## 4. 关键设计决策

### 4.1 State 单向数据流 (V6.28 大拆分)

`ContentViewModel` 是**唯一真相源**, 3 个子 model 拆解关注点:
- `GridViewModel` — 网格业务 (selection/visible/batch/single/search/sort/zoom/immersive)
- `ImportViewModel` — 导入业务 (startImport/handleDrop/dedup/progress)
- `WindowViewModel` — window chrome (V6.74.2 大幅简化)

View **不持业务 @State**。ContentView 仅 2 个 transient UI state (isMarqueeActive, boxSelectionRect)。View 通过 `Bindable(model).X` 拿 binding。

详见 `STATE_MANAGEMENT.md`。

### 4.2 SwiftData schema 策略 (V6.75 决策)

- **V1** = Photo / Folder / Tag
- **V2** = + SmartFolder
- **不开 V3** (isFavorite 改 computed, markup/crop 走 runtime Optional 字段)
- 理由: lightweight migration 够用, 改 schema V3 成本高

### 4.3 详情面板走 Immersive Drawer (V6.111-V6.117)

V5.x-V6.112 详情面板在主页面 (NS 3-col), V6.113 用户要求"彻底取消主页面的详情面板"。最终方案:
- **主页面**: NS **2-col form** (sidebar + center, 无 detail) — V6.117
- **看详情**: 进 immersive 全屏, ⓘ 按钮开 Photos 范式右侧 drawer, 看 image card / info card / operations card / tags card
- **DetailPane / DetailView 组件保留**, 仅 ImmersivePhotoView 内部使用

### 4.4 Toolbar 演化史 (V6.62-V6.85)

| V | 状态 |
|---|---|
| V4.x-V6.61 | AppKit NSToolbar (ToolbarController 61KB) |
| V6.62 | 改 SwiftUI .toolbar + ToolbarItem |
| V6.74 | SwiftUI .toolbar 真版, 删 NSToolbar (-1380 LOC) |
| V6.80-V6.85 | toolbar 材质 5 次迭代 (regularMaterial/glass/bar/clear), 最终 V6.85 取消, 走系统默认 |
| **V6.117** | 8 个独立 ToolbarItem (export/delete/quicklook/filter/sort/view/slider/import) |

### 4.5 撤销/重做自写 (V6.14.10)

替 Foundation.UndoManager, 原因: Swift Testing 并行 2 类 trap (cfprefsd 拖累 + Foundation.UndoManager 强引用环)。自写 ImageGalleryUndoManager:
- 50 步栈
- 1s coalescing (V6.35.3 rotate/rate, V6.36.3 扩到 batchMove/batchRename)
- 跟 SwiftData modelContext 配合, register undo 时序列化闭包

## 5. 关键技术栈细节

### 5.1 macOS 部署目标

- `MACOSX_DEPLOYMENT_TARGET = 15.5` (Sequoia)
- `arm64-apple-macos26.5` SDK (Xcode 26)
- 真机/模拟器 macOS 26+ 测试

### 5.2 SwiftData

- **是** SwiftData (`@Model` + `@Query` + `ModelContainer`)
- VersionedSchema V1 + V2
- Lightweight migration only
- 多个 ModelContainer seam (测试用)
- `SwiftDataLogging.swift` 提供 saveWithLog error propagation

### 5.3 AppKit 桥接 (反向, 不正桥)

- `NSViewRepresentable` 桥 NSWindow (WindowAccessor, V6.74.2 改 no-op fallback)
- `NSApplicationDelegate` (AppDelegate, 多 window frame 持久化)
- `NSWindowDelegate` (per-window frame, V6.97.0 JSON 多窗口)
- `NSCache<NSString, NSImage>` (ThumbnailCache + CroppedThumbnailCache)
- `NSPasteboard` (GridViewModel copyToPasteboard)
- `NSSharingServicePicker` (V6.19.0 shareRequested)
- `NSWorkspace` (Open Recent 揭示文件)
- `NSSetUncaughtExceptionHandler` / `signal()` via `@_cdecl` (CrashReporter)
- **无 NSHostingController** — 纯 SwiftUI App
- **无 NSToolbar** — V6.74.2 删

### 5.4 Concurrency

- `@MainActor` + `@Observable` + `final class` 是 model 标准范式
- `OSAllocatedUnfairLock` 用于 ThumbnailCache 统计
- `Task.detached` 用于 ImageLoader async

### 5.5 持久化路径

- 照片数据: `Application Support/ImageGallery/Photos/` (fallback `~/Pictures`)
- 缩略图: NSCache in-memory (不持久化)
- 撤销: in-memory stack (不持久化, 关 app 丢)
- 设置: UserDefaults (UserSettings didSet 双写)
- 窗口 frame: JSON per-window (V6.97.0+)
- 崩溃日志: `~/Library/Logs/ImageGallery/crash-<timestamp>.log`

### 5.6 URL Scheme / Shortcuts

- `imagegallery://` (Info.plist `CFBundleURLTypes`)
- Bundle ID: `com.iridescent.ImageGallery` (推断)
- 4 个 App Intent MVP (V6.97.2): Crop/Aspect/Search/Open
- App Group entitlement FAIL ad-hoc signing, 改 URL scheme pattern

### 5.7 国际化

- String Catalog (`Localizable.xcstrings`)
- 2 locale: en (Base) + zh-Hans
- 320KB / 8184 行
- 600+ i18n key (V6.37 全 sweep 完)

## 6. 演进约束 (什么时候加 / 不加)

### 6.1 保持不加 (V6.18 战略级 P3+)

- 人脸识别 (Photos 闭环已好, 增量价值低)
- 地图视图 (隐私 + Photos 闭环)
- EXIF 编辑 (复杂 + 错率高)
- iCloud 同步 (Sandbox 没开)

### 6.2 战略级待做 (V6.18 1-2 周)

- Document-based app (NSDocument + Sandboxing)
- Hardened Runtime + 公证 (Notarization)
- App Store 提交准备

### 6.3 P1 持续做 (V6.x 范围)

- a11y 真版 (Toolbar 8 item + Contextual 5 + Toast + StatusBar, V6.64)
- Dynamic Type (V6.33.1 + V6.78)
- Photos 真版 Settings (V6.41-V6.51 10 commit)
- Performance cache (V6.38.x 5 tier)

## 7. 相关文档

- `STATE_MANAGEMENT.md` — ContentViewModel + 3 子 + binding pattern
- `VIEW_HIERARCHY.md` — MainSplitView tree + toolbar + immersive + sheets
- `DATA_MODEL.md` — SwiftData entities + UserSettings

## 8. 更新记录

| Date | V | 摘要 |
|---|---|---|
| 2026-06-25 | V6.117 | 初版, NS 2-col form, 详情面板走 immersive drawer, View 树全面梳理 |
