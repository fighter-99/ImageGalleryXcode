# ImageGallery — State Management

> 业务状态 + @Observable 模式 + SwiftData @Query + binding pattern。
> 最后更新: V6.117 (V6.28 大拆分 + V6.38 perf cache 体系)

## 1. 核心原则

```
┌──────────────────────────────────────────────┐
│  1. 业务状态全在 model, View 不持业务 @State    │
│  2. View 通过 Bindable(model).X 拿 binding     │
│  3. 状态变化驱动 View 重渲 (@Observable)       │
│  4. Service stateless + MainActor              │
│  5. 派生数据 cache 化 (V6.38 perf 体系)         │
└──────────────────────────────────────────────┘
```

View 唯一的本地 `@State` 是 **transient UI state** (e.g. isMarqueeActive, boxSelectionRect)。

## 2. Root Model 拆分 (V6.28 大拆分)

### 2.1 拆分前后对比

| V | 状态 | LOC |
|---|---|---|
| V5.60 前 | 1 个 ContentViewModel (900 行) | — |
| V5.60-V6.27 | 1 个 ContentViewModel (~1450 行) | 单体大 class |
| V6.28 | 拆 ContentViewModel (350) + GridViewModel (871 NEW) | -50% LOC |
| V6.28.1 | 拆 ImportViewModel (257 NEW), ContentViewModel (456) | 续拆 |
| V6.28.2 | 拆 WindowViewModel (184 NEW), ContentViewModel (350) | 续拆 |
| **V6.117** | **ContentViewModel (350) + Grid (871) + Import (257) + Window (184) = 1662** | — |

V6.28 拆分 P1 #30 100% 完成。

### 2.2 拆分结构 (V6.117 当前)

```
ContentViewModel (Core + Root, ~350 行)
├ settings: UserSettings
├ modelContext: ModelContext? (注入)
├ sidebarSelection / filterState / toastQueue / undoManager
├ importVM: ImportViewModel ← 子模型
├ windowVM: WindowViewModel ← 子模型
├ grid: GridViewModel ← 子模型
├ viewMode / appearanceMode / accentColor / layoutMode (settings 镜像)
├ sidebarColumnWidth (settings 镜像)
├ configureToolbar / checkStorage / createFolder / createSmartFolder
├ toggleSortDirection / serializeSelection / restoreSelection
├ enqueueToast / scheduleDismiss
└ Import 业务: startImport / handleDrop / importPhotos

GridViewModel (Grid 业务, ~900 行)
├ selection: SelectionState
├ searchText / sortOption / thumbnailSize
├ visiblePhotos / selectedPhotosInVisible / resolvedSingle (V6.38 cache)
├ currentFolder / currentTag / currentSmartFolder (V6.38.0 cache)
├ currentIndex / canPrev / canNext / isMultiSelect
├ libraryStats (V6.19.2 7 维单遍)
├ representativePhoto / currentViewTitle / currentViewSubtitle
├ single ops: copyToPasteboard / shareSelectedURLs / rotateSelected
│            / speakSelection / deleteSinglePhoto / handleDelete / handleTap
├ batch ops: batchDelete / batchMove / batchAddTag / batchRename
│           / batchSetRating / batchExport / emptyTrash
└ immersive: enterImmersive / immersivePhoto / immersiveIndex

ImportViewModel (Import 业务, ~260 行, V6.28.1 NEW)
├ importProgress: ImportProgress?
├ importDuplicateCheck: ImportDuplicateCheck?
├ pendingImportURLs / supportedImageExtensions
├ startImport (NSOpenPanel)
├ handleDropImport / handleDrop (NSItemProvider → URLs)
└ runImportWithDuplicateCheck / importPhotos

WindowViewModel (Window 业务, ~185 行, V6.74.2 大幅简化)
├ titlebarAccessory
├ configureToolbar(window:)  ← V6.74.2 大幅简化 (删 NSToolbar 死代码)
└ windowDidBecomeKey observer
```

### 2.3 子模型依赖 (V6.28 解决循环)

**问题**: 子模型需要调 Core 业务 (e.g. enqueueToast) + 访问 shared resources (settings, modelContext, undoManager)。

**V6.28 解决**: **Core back-ref + shared resources 注入**

```swift
@MainActor
@Observable
final class GridViewModel {
    /// V6.28: Core back-ref (weak 避免 retain cycle)
    @ObservationIgnored weak var core: ContentViewModel?

    /// V6.28: shared settings (Core 同实例, init 注入)
    @ObservationIgnored let settings: UserSettings

    /// V6.28: shared undoManager (Core 同实例, init 注入)
    @ObservationIgnored let undoManager: ImageGalleryUndoManager

    /// V6.28: toast callback — Core 的 enqueueToast (避免重复 toast queue)
    @ObservationIgnored var enqueueToastHandler:
        (String, ToastView.ToastType, ToastInfo.Duration, _ undoAction: (() -> Void)?) -> Void = { _, _, _, _ in }
    ...
}
```

**Init 流程**:
```swift
// ContentViewModel.init
self.grid = GridViewModel(core: self, settings: settings, undoManager: undoManager, enqueueToast: enqueueToast)
self.importVM = ImportViewModel(core: self, ...)
self.windowVM = WindowViewModel(core: self, ...)
```

**关键约束**:
- 子模型对 Core 是 `weak var core` — 避免 retain cycle
- `settings` / `undoManager` 是 `let` (immutable ref) — 避免双初始化
- `enqueueToastHandler` 是 closure (不是 closure capture Core) — 避免循环

## 3. @Observable + binding 模式

### 3.1 @Observable 标准范式

```swift
@MainActor
@Observable
final class ContentViewModel {
    var sidebarSelection: SidebarSelection? = nil  // @Observable tracked
    @ObservationIgnored var modelContext: ModelContext? = nil  // 不触发重渲
    ...
}
```

**@ObservationIgnored 用法**:
- `modelContext` (注入引用, 不会变)
- `settings` / `undoManager` (immutable 引用)
- `core` (back-ref)
- 缓存字段 (V6.38 perf)
- `lastShareRequestTime` 等 transient state
- `speechSynthesizer` (AVFoundation 实例, 不需要观察)

### 3.2 Binding 模式 (V6.76 优化)

**V5.60 模式 (历史, 仍兼容)**:
```swift
// V5.60: setter 路径不能直接 model.X = Y, 走 private func
Button { model.toggleSortDirection() } label: { ... }
```

**V6.76 模式 (V5.60 推翻, V6.77 全面替换)**:
```swift
// V6.76: 真相源统一 1 层 (View → model.X), 删 25 个 private var proxy
Bindable(model).sidebarSelection
Bindable(model.grid).searchText
```

**关键约束**:
- `@Observable` 子结构不能 `$model.grid.X` 出 Binding — 需 inline `Bindable(model.grid).X`
- 这跟 ObservableObject 时代不同 (`$model.grid.X` 可以)

### 3.3 @AppStorage 桥接 (V5.59)

```swift
// V5.59: 12 @AppStorage 不能进 class, 由 view 推到 Settings 字段
@AppStorage("showSidebar") private var showSidebar = true  // View 端

// Model 端
var showSidebar: Bool { settings.showSidebar }  // computed
```

ContentViewModel + GridViewModel **共持同一 UserSettings 实例** (ImageGalleryApp.sharedSettings 注入)。

## 4. SwiftData @Query 模式

### 4.1 @Query 不能进 class (V5.52 约束)

`@Query` 是 SwiftUI 提供的 property wrapper, 只能在 View 里用。ContentViewModel / GridViewModel 不能直接用。

**解法 (V5.52)**:
1. View 用 `@Query` 拉数据
2. `.onChange(of: queryResult)` 推到 model
3. Model 缓存为 `@ObservationIgnored` 字段

```swift
// View
@Query private var allPhotos: [Photo]
.onChange(of: allPhotos) { _, newValue in
    model.grid.allPhotos = newValue
}

// Model
@ObservationIgnored var allPhotos: [Photo] = []  // 缓存
```

### 4.2 GridViewModel 4 个 @Query 缓存 (V6.28)

```swift
@ObservationIgnored var allPhotos: [Photo] = []
@ObservationIgnored var folders: [Folder] = []
@ObservationIgnored var allTags: [Tag] = []
@ObservationIgnored var smartFoldersCache: [SmartFolder] = []
```

ContentView.swift / SidebarView.swift 用 `@Query`, 推到 GridViewModel 缓存。

## 5. 派生数据 cache 体系 (V6.38 P0 perf)

### 5.1 为什么需要 cache

**V6.38 性能审计发现 4 个 CRITICAL**:
- (C1) GridViewModel.visiblePhotos 无缓存, 每次 ContentView.body 触发 5-10× 全库 filter+sort
- (C2) currentFolder/currentTag/currentSmartFolder 每次访问 modelContext.fetch 无缓存
- (C3) ContentView.body 复合放大 + 5-7× visiblePhotos
- (C4) PhotoGridView.computeCellFrames 在 GeometryReader 内 O(n) 重算

**预估影响**: grid 浏览 5-10× / zoom 2× / sidebar 切换 3-9× 减速。

### 5.2 V6.38 Cache 体系 (5 tier)

**V6.38.0 Tier 1**:
- `visiblePhotos` cache (Hasher 14-key invalidation)
- `currentFolder` / `currentTag` / `currentSmartFolder` cache (SidebarSelection keyed)
- `currentViewSubtitle` 单次 evaluate

**V6.38.1 Tier 2**:
- `selectedPhotosInVisible` cache (selectedIDs + visibleCacheKey 复合 key)

**V6.38.2 Tier 3**:
- `resolvedSingle` cache (singleSelectedID + visibleCacheKey 复合 key)
- `computeCellFrames` cache (GeometryReader 内 5 layout 参)

**跳过的**:
- Tier 2 #1 @Query 去重
- Tier 2 #2 lifecycle fan-out
- Tier 3 #3 Task 限流
- Tier 3 #4 handleTap precomputed Set

### 5.3 Cache 标准模式

```swift
@ObservationIgnored private var cachedVisiblePhotos: [Photo] = []
@ObservationIgnored private var cachedVisibleKey: Int = 0
@ObservationIgnored private var visibleCacheValid: Bool = false

var visiblePhotos: [Photo] {
    if !visibleCacheValid || cachedVisibleKey != computeKey() {
        cachedVisiblePhotos = recomputeVisiblePhotos()
        cachedVisibleKey = computeKey()
        visibleCacheValid = true
    }
    return cachedVisiblePhotos
}
```

**Cache 触发**:
- `.onChange(of: searchText/sortOption/filterState)` → `visibleCacheValid = false`
- `.onChange(of: allPhotos)` (from @Query) → `visibleCacheValid = false`
- SwiftData ModelContext save → `visibleCacheValid = false`

**关键测试覆盖**:
- 13 + 12 + 5 = 30 新 perf tests (V6.38.x)
- 验证 cache hit/miss 行为, key 一致性

## 6. 撤销/重做 (V6.14.10 自写)

### 6.1 为什么自写

替 `Foundation.UndoManager`, 原因: **Swift Testing 并行 2 类 trap** (memory):
- (1) `cfprefsd` 拖累: UserDefaults 在 parallel test 跨进程冲突 (V6.12.21 用 FakeUserDefaults 缓解, 但 UndoManager 仍引 Foundation)
- (2) `Foundation.UndoManager` 强引用环: 跟 SwiftData @Model / modelContext 持有导致 deinit 永远不触发

### 6.2 ImageGalleryUndoManager 设计

```swift
@MainActor
final class ImageGalleryUndoManager {
    struct UndoEntry {
        let label: String
        let undo: () -> Void
        let redo: () -> Void
        let coalesceId: String?  // V6.35.3+ 支持 1s 合并
        let timestamp: Date
    }

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private let maxDepth: Int = 50  // 50 步栈

    func registerUndoOnly(label:undo:redo:coalesceId:)  // V6.29.1 toast 撤销
    func registerUndo(...)
    func undo()
    func redo()
}
```

**Coalescing 策略** (V6.35.3 / V6.36.3):
- V6.35.3: rotate / rate 操作 1s 合并
- V6.36.3: 扩展到 batchMove / batchRename
- 同一 coalesceId 1s 内多次 register → 合并为 1 个 undo entry

## 7. Settings 镜像 (V5.59)

ContentViewModel + GridViewModel **不直接写 UserDefaults**, 走 `UserSettings` (UserDefaults 双写 @Observable):

```swift
// UserSettings (Models/Settings.swift)
@MainActor @Observable
final class UserSettings {
    var showSidebar: Bool = true {
        didSet { defaults.set(showSidebar, forKey: "showSidebar") }
    }
    var sidebarSelection: String = "all" {
        didSet { defaults.set(sidebarSelection, forKey: "sidebarSelection") }
    }
    ...
}

// ContentViewModel computed wrapper
var viewMode: ViewMode {
    get { ViewMode(rawValue: settings.viewModeRaw) ?? .grid }
    set { settings.viewModeRaw = newValue.rawValue }
}
```

**init 时反序列化** (V5.59-2):
```swift
init() {
    if defaults.object(forKey: "showSidebar") != nil {
        self.showSidebar = defaults.bool(forKey: "showSidebar")
    }
    ...
}
```

## 8. Binding 模式决策树 (V6.77 推行)

```
View 想拿 model.X 的 binding?
├ X 在 ContentViewModel 直接字段 (e.g. sidebarSelection)?
│   ├ Yes → Bindable(model).X
│   └ No → 继续
├ X 在 ContentViewModel computed (e.g. viewMode)?
│   ├ Yes → 看是否已开 get/set:
│   │   ├ Yes → Bindable(model).X (computed 也能 Bindable)
│   │   └ No → 加 get/set 或走 private func
│   └ No → 继续
└ X 在子 model (e.g. model.grid.X)?
    ├ Yes → Bindable(model.grid).X (不能 $model.grid.X)
    └ No → 走 func 模式 (Button { model.grid.X() })
```

**V6.76-V6.77 删 25 个 private var proxy** (proxy 字段只是把 model.X 包成 @Published, 真相源间接化)。V6.77 推行单一真相源。

## 9. 通知桥接菜单 (V6.x 模式)

`ImageGalleryApp` 12+ `Notification.Name` 桥接菜单到 ContentViewModel:

```swift
// ImageGalleryApp.swift
extension Notification.Name {
    static let importPhotos = Notification.Name("imagegallery.importPhotos")
    static let deleteSelected = Notification.Name("imagegallery.deleteSelected")
    ...
}

// ContentView.swift .onReceive
.onReceive(NotificationCenter.default.publisher(for: .importPhotos)) { _ in
    model.importVM.startImport()
}
```

12+ 个 Notification 集中管理, 避免 menu 跟 model 紧耦合。

## 10. 性能 cache key 设计 (V6.38 模式)

```swift
/// V6.38.0: 算 visiblePhotos 缓存 key — 复合 hash of all filter inputs
private func computeVisibleCacheKey() -> Int {
    var hasher = Hasher()
    hasher.combine(searchText)
    hasher.combine(sortOption)
    hasher.combine(filterState.activeFiltersHash)
    hasher.combine(allPhotos.count)  // 长度变了, 必 recompute
    hasher.combine(currentFolder?.id)
    hasher.combine(currentTag?.id)
    hasher.combine(currentSmartFolder?.id)
    return hasher.finalize()
}
```

**Hash 设计原则**:
- 14 关键 inputs (V6.38.0 实际)
- 变化才 invalidate (filter/sort 切换)
- 长度变化 invalid (新增/删除 photo)
- SidebarSelection 切换 invalid

## 11. 关键约束清单

- [x] `@MainActor` + `@Observable` + `final class` (项目标准)
- [x] View 不持业务 @State (ContentView 仅 2 transient)
- [x] 业务状态全在 model, @ObservationIgnored 缓存
- [x] 子模型 weak back-ref 避免循环
- [x] shared resources (settings/undoManager) 显式注入
- [x] `@Query` 在 View, 推到 model 缓存
- [x] `@AppStorage` 在 View, 推到 settings 字段
- [x] derived data 走 cache (V6.38 体系)
- [x] 撤销/重做自写 (V6.14.10)
- [x] 通知桥接菜单 (12+ Notification.Name)

## 12. 相关文档

- `ARCHITECTURE.md` — 高层架构 + 模块划分
- `VIEW_HIERARCHY.md` — MainSplitView tree + toolbar + immersive + sheets
- `DATA_MODEL.md` — SwiftData entities + UserSettings

## 13. 更新记录

| Date | V | 摘要 |
|---|---|---|
| 2026-06-25 | V6.117 | 初版, V6.28 大拆分 + V6.38 perf cache 体系, V6.76-V6.77 binding 模式, V6.14.10 自写 UndoManager |
