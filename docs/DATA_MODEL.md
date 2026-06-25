# ImageGallery — Data Model

> SwiftData 实体 + UserSettings + schema 演进策略。
> 最后更新: V6.117 (V6.75 isFavorite 决策 + V6.94.1 markup + V6.97.1 crop)

## 1. SwiftData 实体总览

```
Photo (V1, V2 兼容, V2.5 lightweight 加字段)
├ Folder? (V1, to-one)
├ [Tag] (V1, to-many, @Relationship deleteRule: .nullify)
├ SmartFolder (V2, 无直接关系, 通过 FilterState 过滤)
└ 各种 stored 字段 (V1 基础 + V2.5 加 markup/crop + V2 留 isFavorite)

Folder (V1, to-many inverse)
Tag (V1, to-many inverse)
SmartFolder (V2, filterData: Data)

ImageGallerySchemaV1: [Photo, Folder, Tag]
ImageGallerySchemaV2: [Photo, Folder, Tag, SmartFolder]
```

**Schema 策略** (V6.75 决策):
- **V1** = Photo / Folder / Tag (基础)
- **V2** = + SmartFolder (P4.1)
- **不开 V3** — 新字段走 V2 → V2.5 lightweight migration
- 理由: lightweight migration 够用, 改 schema V3 成本高 (V6.68 教训: custom-stage migration 启动崩溃过)

## 2. Photo 实体 (V1 + V2.5 累积字段)

### 2.1 字段清单 (V6.117 当前)

| 字段 | 类型 | V | @Attribute | 索引 | 默认 | 说明 |
|---|---|---|---|---|---|---|
| `id` | UUID | V1 | `.unique` | PK | UUID() | 唯一标识 |
| `filename` | String | V1 | `.spotlight` | 是 (V6.35.1) | — | 文件名, Spotlight 搜索 |
| `fileURL` | URL | V1 | — | — | — | 文件路径 (Application Support/ImageGallery/Photos/) |
| `importedAt` | Date | V1 | `.spotlight` | 是 (V6.35.1) | Date() | 导入时间, Spotlight + sortBy 走索引 |
| `fileSize` | Int64 | V1 | — | — | — | 文件大小 (字节) |
| `width` | Int | V1 | — | — | — | 像素宽 |
| `height` | Int | V1 | — | — | — | 像素高 |
| `isFavorite` | Bool | V1 | — | — | false | **V6.75 保留 stored, 业务不读不写** (rating >= 5 替代) |
| `note` | String | V1 | — | — | "" | 笔记 |
| `folder` | Folder? | V1 | — | — | nil | 所属文件夹 (nil = 待整理) |
| `tags` | [Tag] | V1 | @Relationship(deleteRule: .nullify) | — | [] | 多对多标签 |
| `fileHash` | String? | V1 | — | — | nil | SHA256 hex, 重复图检测 |
| `sortOrder` | Int | V1 | — | — | 0 (init: timeIntervalSince1970) | 自定义排序顺序 |
| `rating` | Int | V1 → V2.5 | — | — | 0 | 0=未评分, 1-5 评分 (V4.36.x 加) |
| `trashedAt` | Date? | V1 → V2.5 | — | — | nil | nil=在图库, 非 nil=在回收站 (V3.6) |
| `markupData` | Data? | V2.5 (V6.94.1) | — | — | nil | PencilKit NSBezierPath plist (P0 #3) |
| `cropRect` | Data? | V2.5 (V6.97.1) | — | — | nil | JSON-encoded CropRect normalized 0-1 (P0 #5) |

**V6.117 共 17 字段 (含 2 stored-保留)**。

### 2.2 Computed 字段

```swift
/// V6.75: isFavoriteComputed — 单一真相源是 rating (收藏 = 评分 ≥ 5)
///   业务代码应统一用这个, 取代 `photo.isFavorite`
var isFavoriteComputed: Bool { rating >= 5 }

/// V3.6 convenience：是否在回收站（等价于 `trashedAt != nil`）
var isInTrash: Bool { trashedAt != nil }
```

### 2.3 isFavorite 字段演化 (V6.75 关键决策)

**问题**:
- V5.8: stored `isFavorite: Bool`, 跟 rating 是两套独立的用户偏好
- V6.68 决策: 合并为 rating (rating >= 5 = 收藏)
- V6.68 试真删 stored `isFavorite` 字段 → production init crash (SQLite ALTER TABLE DROP COLUMN 风险)
- V6.75 二次试 custom-stage migration → 仍 crash
- SwiftData tooling 不稳定

**V6.75 妥协方案** (memory):
- 保留 stored `isFavorite` 字段 (V2 schema 兼容, production 升级不 crash)
- 加 computed `isFavoriteComputed = (rating >= 5)` 单一真相源
- 业务代码统一用 `isFavoriteComputed`
- 启动幂等 `migrateFavoriteToRating` 改为 no-op
- stored 字段占 1 byte/行 (~5k 行 = 5KB), 业务永远不写不读, 启动幂等空跑

**后续清理 (V6.76+ 计划)**:
1. SQLite 端 ALTER TABLE DROP COLUMN ZFAVORITE (raw SQL)
2. SwiftData @Model 字段同步移除
3. VersionedSchema V3 真描述新字段集

### 2.4 索引 (V6.35.1)

```swift
@Attribute(.spotlight) var filename: String
@Attribute(.spotlight) var importedAt: Date
```

- `filename` + `importedAt` 走 Spotlight 索引
- searchText 模糊搜索 filename (O(n) 扫 → O(log n) 索引)
- sortBy importedAt (sidebar 排序) 走索引
- 大库 (5k+) 排序从 ~200ms → ~10ms

### 2.5 init (V6.117)

```swift
init(filename: String, fileURL: URL, fileSize: Int64, width: Int, height: Int) {
    self.id = UUID()
    self.filename = filename
    self.fileURL = fileURL
    self.importedAt = Date()
    self.fileSize = fileSize
    self.width = width
    self.height = height
    self.note = ""
    self.folder = nil
    self.fileHash = nil
    self.sortOrder = Int(Date().timeIntervalSince1970)  // 新照片避免跟老照片 0 冲突
    self.rating = 0
    // V6.75: 删 self.isFavorite = false — stored 字段默认值已是 false
}
```

## 3. Folder 实体 (V1)

```swift
@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Photo.folder)
    var photos: [Photo] = []
    ...
}
```

**关系**:
- `Folder.photos` ↔ `Photo.folder` (to-one inverse)
- 删除 folder: photos.folder = nil (nullify)
- 不能 cascade delete (照片保留在图库, folder = nil)

## 4. Tag 实体 (V1)

```swift
@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Photo.tags)
    var photos: [Photo] = []
    ...
}
```

**关系**:
- `Tag.photos` ↔ `Photo.tags` (to-many)
- 删除 tag: photos 中该 tag 被移除 (nullify)
- 多对多

## 5. SmartFolder 实体 (V2, P4.1)

```swift
@Model
final class SmartFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String
    var order: Int
    var createdAt: Date

    /// V4.36.6 改: filterData: Data (FilterState JSON 序列化)
    /// 不用单独的多个字段, 灵活 + 跟 FilterState 双向同步
    var filterData: Data
    ...
}
```

**特点**:
- 无 @Relationship (V2 不开 photo 关系, 过滤走 FilterState)
- `filterData: Data` 是 FilterState JSON 序列化
- 跟 FilterState 双向同步 (创建时序列化, 加载时反序列化)
- `order` 字段决定 sidebar 显示顺序

## 6. ImageGallerySchema (V1 + V2)

```swift
// Models/ImageGallerySchema.swift
enum ImageGallerySchemaV1: VersionedSchema {
    static var versionIdentifier: String? = "v1"
    static var models: [any PersistentModel.Type] {
        [Photo.self, Folder.self, Tag.self]
    }
}

enum ImageGallerySchemaV2: VersionedSchema {
    static var versionIdentifier: String? = "v2"
    static var models: [any PersistentModel.Type] {
        [Photo.self, Folder.self, Tag.self, SmartFolder.self]
    }
}

typealias ImageGalleryLatestSchema = ImageGallerySchemaV2

// Models/ImageGalleryMigrationPlan.swift
enum ImageGalleryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ImageGallerySchemaV1.self, ImageGallerySchemaV2.self]
    }
    static var stages: [MigrationStage] {
        []  // V1 → V2 lightweight migration (新增 SmartFolder @Model)
    }
}
```

**V6.75 决策不开 V3**:
- 后续字段 (rating, trashedAt, markupData, cropRect) 都走 V1 → V2.5 lightweight
- 走 V3 schema 的成本太高 (custom-stage migration 启动崩溃过, V6.68 教训)

## 7. UserSettings (@Observable, UserDefaults 双写)

### 7.1 字段清单 (V6.117 共 22 字段 + 3 typed wrapper)

| 字段 | 类型 | 默认 | 用途 | V |
|---|---|---|---|---|
| `viewModeRaw` | String | `ViewMode.grid.rawValue` | 视图模式 (grid/list/timeline) | V3.6.x |
| `appViewMode` | ViewMode (typed) | — | computed wrapper, V6.39 加 | V6.39 |
| `showSidebar` | Bool | `true` | 侧栏显隐 (⌘\ 切) | V3.6.13 |
| `accentColorID` | String | `AccentColor.system` | 强调色 (9 色 swatch, V6.44) | V3.6.13 |
| `trashRetentionDays` | Int | `TrashRetentionDays.defaultValue.rawValue` | 回收站保留天数 (3/7/30/永久) | V3.6.13 |
| `appTrashRetentionDays` | TrashRetentionDays | — | typed wrapper, V6.43 加 | V6.43 |
| `appearanceMode` | Int | `AppearanceMode.defaultValue.rawValue` | 外观 (light/dark/auto) | V3.6.22 |
| `thumbnailSize` | Double | `200` | 缩略图尺寸 slider (100...250) | V5.30 (240→200) |
| `sidebarSelection` | String | `"all"` | 侧栏选中 raw value (V5.59-2 init 反序列化) | V3.6.13 |
| `sortOption` | String | `SortOption.filenameAsc.rawValue` | 排序方式 (V5.31 默认改) | V3.6.13 |
| `thumbnailLayoutMode` | Int | `ThumbnailLayoutMode.defaultValue` | 缩略图布局 (方格/按比例) | V5.17 |
| `sidebarColumnWidth` | Double | `220` | 侧栏宽度 (V6.117 NS 2-col 自动用) | V3.6.13 |
| `autoDeduplicate` | Bool | `true` | 导入时自动去重 | V5.90 |
| `autoGenerateThumbnails` | Bool | `true` | 导入时生成缩略图 | V5.90 |
| `defaultExportFormat` | String | `ExportFormat.defaultValue.rawValue` | 默认导出格式 (jpg/png/heic) | V5.90 |
| `appExportFormat` | ExportFormat | — | typed wrapper, V6.43 加 | V6.43 |
| `defaultExportQuality` | Double | `0.9` | 默认导出质量 (0-1) | V5.90 |
| `scrollAnchorPhotoID` | String? | `nil` | 滚动锚点 (重启恢复位置, V5.55-2 P0) | V5.55-2 |
| `language` | String | `Language.zhHans.rawValue` | 语言 (V6.37 en + zh-Hans) | V6.15 |
| `appLanguage` | Language | — | typed wrapper, V6.39 加 | V6.39 |
| `fontScale` | String | `FontScale.defaultValue.rawValue` | 字体缩放 (4 档, V6.33.1) | V6.33.1 |
| `appFontScale` | FontScale | — | typed wrapper, V6.33.1 加 | V6.33.1 |
| `lastSettingsCategory` | String | `SettingsCategory.general.rawValue` | 设置面板上次类别 (V6.45.3 跨 restart) | V6.45.3 |
| `defaultImportLocation` | String? | `nil` | 默认导入位置 (bookmark, V6.39) | V6.39 |
| `doubleClickAction` | String | `DoubleClickAction.defaultValue.rawValue` | 双击行为 (.immersive/.quickLook) | V6.39 |
| `appDoubleClickAction` | DoubleClickAction | — | typed wrapper, V6.39 加 | V6.39 |

**V6.113 已删** (主页面详情面板移除):
- ~~`showDetail`~~ (Bool)
- ~~`detailColumnWidth`~~ (Double)

### 7.2 模式: didSet 写 UserDefaults

```swift
@MainActor @Observable
final class UserSettings {
    var showSidebar: Bool = true {
        didSet { defaults.set(showSidebar, forKey: "showSidebar") }
    }
    var accentColorID: String = AccentColor.system.rawValue {
        didSet { defaults.set(accentColorID, forKey: "accentColorID") }
    }
    ...
}
```

**关键**:
- `@Observable` 触发 View 重渲
- `didSet` 同步写 UserDefaults 持久化
- ContentViewModel + GridViewModel **共持同一 UserSettings 实例** (ImageGalleryApp.sharedSettings 注入)

### 7.3 init 反序列化 (V5.59-2)

```swift
init() {
    if defaults.object(forKey: "showSidebar") != nil {
        self.showSidebar = defaults.bool(forKey: "showSidebar")
    }
    if let stored = defaults.string(forKey: "accentColorID") {
        self.accentColorID = stored
    }
    ...
}
```

**重要**:
- `object(forKey:) != nil` 判定, 而不是直接用 bool — 区分 "没存过" vs "存了 false"
- 没存过的 key 用字段默认值

### 7.4 typed wrapper 模式 (V6.39 / V6.43)

**问题**: 持久化要 String/Int (UserDefaults 只支持这些), 业务代码想要 enum 类型安全。

**解法**: 双层 wrapper

```swift
// Stored 层 (UserDefaults 持久化)
var trashRetentionDays: Int = TrashRetentionDays.defaultValue.rawValue {
    didSet { defaults.set(trashRetentionDays, forKey: "trashRetentionDays") }
}

// Typed wrapper (V6.43 加, 给 SettingsView PhotosSettingRadios 直接绑)
var appTrashRetentionDays: TrashRetentionDays {
    get { TrashRetentionDays(rawValue: trashRetentionDays) ?? .defaultValue }
    set { trashRetentionDays = newValue.rawValue }
}
```

**适用枚举**: ViewMode / TrashRetentionDays / ExportFormat / Language / FontScale / DoubleClickAction

**关键约束**:
- Identifiable 不蕴含 Hashable — String/Int enum 即使 Identifiable 不自动 Hashable, 必须显式
- PhotosSettingRadios<T: Hashable> 接受 `Binding<T>`, 所以 typed wrapper 必须返回 enum 而非 RawValue

### 7.5 SettingsCategory (V6.45.3)

```swift
enum SettingsCategory: String, Hashable, CaseIterable, Identifiable {
    case general, appearance, library, trash, language, shortcuts, about
}
```

**V6.45.3 决策**:
- 之前用 `@SceneStorage` (per-scene, 关 app 丢失)
- 改 `@State + State(initialValue:)` + `lastSettingsCategory` in UserSettings (跨 restart 记忆)

## 8. SwiftData 持久化策略

### 8.1 照片文件

- 路径: `Application Support/ImageGallery/Photos/` (fallback `~/Pictures`)
- 命名: UUID 目录 + filename
- 照片本体不存 SwiftData, SwiftData 只存 metadata + 引用 (fileURL)
- 缩略图: NSCache in-memory (不持久化, 启动重生成)

### 8.2 SwiftData store

- 路径: `~/Library/Application Support/ImageGallery/default.store` (推断)
- Type: SQLite (SwiftData default)
- Migration: V1 → V2 lightweight
- V2.5 累积新字段 (rating/trashedAt/markupData/cropRect) 走 lightweight

### 8.3 UndoManager

- 不持久化 (in-memory stack)
- 关 app 丢失
- 50 步栈
- 1s coalescing (V6.35.3 rotate/rate, V6.36.3 扩到 batchMove/batchRename)

### 8.4 Window frame

- V6.97.0 改 per-window JSON 持久化
- 路径: `~/Library/Application Support/ImageGallery/WindowFrames/<UUID>.json`
- Key: `imageGalleryWindowFrames` (主 key)

### 8.5 Crash log

- `~/Library/Logs/ImageGallery/crash-<timestamp>.log`
- CrashReporter.swift NSSetUncaughtExceptionHandler + 5 POSIX signals

## 9. 关键决策 (V6.117 当前)

| 决策 | V | 理由 |
|---|---|---|
| 不开 V3 schema | V6.75 | V6.68 教训: custom-stage migration 启动崩溃过, lightweight 够用 |
| 保留 stored isFavorite | V6.75 | V2 schema 兼容, production 升级不 crash; 业务用 isFavoriteComputed |
| markup/crop 走 runtime Optional | V6.94.1 / V6.97.1 | 跟 V6.68 教训一致: 新 schema + custom-stage migration 风险高 |
| 字段走 lightweight migration | V6.75 | rating/trashedAt/markupData/cropRect 都是 Optional 或带默认值, 走 lightweight 安全 |
| @Attribute(.spotlight) 加 filename + importedAt | V6.35.1 | searchText 模糊搜索 + sortBy 大库 5k+ 性能优化 |
| typed wrapper (String + enum) | V6.39 / V6.43 | 持久化 vs 类型安全解耦, SettingsView PhotosSettingRadios 接受 enum binding |

## 10. 关键约束清单

- [x] Schema V1+V2, 不开 V3 (V6.75 决策)
- [x] 新字段走 V2.5 lightweight (rating/trashedAt/markupData/cropRect)
- [x] V2.5 加字段不破坏 V1 production 升级
- [x] UserSettings didSet 双写 UserDefaults
- [x] typed wrapper (V6.39/V6.43) 解决 enum 持久化 vs 类型安全
- [x] isFavorite 保留 stored, 业务用 isFavoriteComputed
- [x] markup/crop 用 Optional Data, 不用 @Attribute(.externalStorage) (V6.68 教训)
- [x] @Attribute(.spotlight) 加在搜索/排序字段 (V6.35.1)
- [x] init 反序列化用 `object(forKey:) != nil` 判定, 不直接 bool
- [x] SwiftData @Model + lightweight migration 是 V6.117 当前 pattern

## 11. 相关文档

- `ARCHITECTURE.md` — 高层架构 + 模块划分
- `STATE_MANAGEMENT.md` — ContentViewModel + 3 子 + binding pattern
- `VIEW_HIERARCHY.md` — MainSplitView tree + toolbar + immersive + sheets

## 12. 更新记录

| Date | V | 摘要 |
|---|---|---|
| 2026-06-25 | V6.117 | 初版, SwiftData V1+V2 schema, Photo 17 字段 + isFavoriteComputed, UserSettings 22 字段 + 3 typed wrapper, V6.75 不开 V3 决策, V6.94.1 markup / V6.97.1 crop runtime Optional 策略 |
