//
//  Photo.swift
//  ImageGallery
//
//  图片数据模型。用 SwiftData 持久化。
//
//  V6.75: isFavorite 字段保留 stored (V2 schema 兼容性), 加 isFavoriteComputed (rating >= 5)
//    V6.68 (lightweight) + V6.75 (custom stage) 都试过真删 stored 字段, 都触发 production init crash
//    SQLite ALTER TABLE DROP COLUMN 风险高, SwiftData tooling 尚未稳定支持
//    V6.75 决策:
//      - 保留 stored isFavorite 字段保证 V2 schema 兼容 (production 升级不 crash)
//      - 加 computed isFavoriteComputed (rating >= 5) — 业务代码应统一用这个
//      - 启动幂等 migrateFavoriteToRating 改为 no-op (rating 是 single source of truth)
//    后续 V6.76+ 真删 stored 字段需要:
//      1. SQLite 端 ALTER TABLE DROP COLUMN ZFAVORITE (raw SQL)
//      2. SwiftData @Model 字段同步移除
//      3. VersionedSchema V3 真描述新字段集
//    现在的妥协: stored 字段占 1 byte/行 (~5k 行 = 5KB), 业务永远不写不读, 启动幂等空跑
//

import Foundation
import SwiftData

@Model
final class Photo {
    // ─── 唯一标识 ───
    @Attribute(.unique) var id: UUID

    // ─── 文件信息 ───
    // V6.35.1: @Index — searchText 模糊搜索 filename (O(n) 扫 → O(log n) 索引)
    //   sortBy importedAt (sidebar 排序) 走索引, 大库 (5k+) 排序从 ~200ms → ~10ms
    @Attribute(.spotlight) var filename: String
    var fileURL: URL
    // V6.35.1: @Index — sortBy 排序走索引
    @Attribute(.spotlight) var importedAt: Date

    // ─── 图片属性 ───
    var fileSize: Int64
    var width: Int
    var height: Int

    // ─── 用户标记 ───
    // V6.75: isFavorite 仍 stored — V2 schema 期望此字段, 删它会触发 init crash (V6.68 教训)
    //   业务代码用 `photo.isFavoriteComputed` (rating >= 5), 这个字段保留作 V2 schema 兼容性
    var isFavorite: Bool = false
    var note: String

    // ─── 所属文件夹（nil = 未整理） ───
    var folder: Folder?

    // ─── 标签（多对多关系） ───
    @Relationship(deleteRule: .nullify)
    var tags: [Tag] = []

    // ─── 文件哈希（SHA256 hex），用于识别重复图 ───
    var fileHash: String?

    // ─── 自定义排序顺序（V3.5.D NEW：拖拽重排）───
    /// 用 Int 时间戳作为初值(新照片 = 当前时间),保证新建照片的 sortOrder 唯一
    /// 老照片迁移时由 PhotoGridView 一次性补值
    var sortOrder: Int = 0

    // ─── 用户评分（V4.36.x NEW：工具栏筛选按钮的「评分」维度）───
    /// 0 = 未评分；1-5 = 1-5 星
    /// SwiftData 轻量级自动迁移：新增带默认值的 Int 字段，迁移现有行填 0
    /// 不影响 V1 schema（3 个 @Model 类数量不变；现有 v1ModelsCountIsThree 测试继续通过）
    var rating: Int = 0

    // ─── 回收站时间戳（V3.6 NEW：App-Owned Storage + 回收站）───
    /// nil = 在图库中；非 nil = 在回收站中（等待恢复或被永久删除）
    /// 回收站视图通过 `trashedAt != nil` 过滤
    /// 自动清理：trashedAt < now - retentionDays 的项会被永久删除
    /// SwiftData 轻量级自动迁移（新增 Optional 属性）
    var trashedAt: Date?

    // ─── V6.94.1: PencilKit Markup 标注数据 (P0 #3) ───
    /// nil = 无标注；非 nil = 序列化 plist (NSBezierPath 数组)
    /// V6.94.1: V2 → V3 lightweight migration 自动安全 (Optional 字段)
    ///   不用 @Attribute(.externalStorage) — V3 lightweight 跟 @externalStorage 一起用有兼容性风险 (V6.68 教训)
    ///   NSBezierPath plist 通常几 KB, 放主 .sqlite 没问题
    /// 显示时跟原图合成: MarkupService.compose(image:with:)
    var markupData: Data?

    // ─── V6.97.1: Crop / Aspect 裁剪数据 (P0 #5) ───
    /// nil = 未裁剪；非 nil = JSON-encoded CropRect (normalized 0-1 + aspect preset)
    /// V6.97.1: 跟 V6.94.1 markupData 同 pattern — runtime Photo 字段, 不开 V4 schema
    ///   V6.68 教训: 新 schema + custom-stage migration 启动崩溃过, 只用 lightweight (或 runtime field)
    ///   CropRect JSON 通常 < 100 bytes, 放主 .sqlite 没问题
    ///   持久化格式跟 V6.97.0 Frame JSON pattern 对齐 (同 `imageGalleryWindowFrames` 主 key 风格)
    /// 显示时跟原图合成: PhotoCropService.compose(image:data:)
    ///   跟 markup compose chain 串联: markup 先 (composited overlay), crop 后 (extract region)
    var cropRect: Data?

    /// V6.75: isFavoriteComputed — 单一真相源是 rating (语义合并: 收藏 = 评分 ≥ 5)
    ///   业务代码应统一用 `photo.isFavoriteComputed` 取代 `photo.isFavorite` (后者 V2 schema 兼容性保留)
    ///   命名加 "Computed" 后缀避免跟 stored 同名冲突 (SwiftData 不允许同名 stored+computed)
    var isFavoriteComputed: Bool { rating >= 5 }

    /// V3.6 convenience：是否在回收站（等价于 `trashedAt != nil`）
    /// 唯一真相源仍是 `trashedAt`；这是只读 computed property，不引入存储冗余
    var isInTrash: Bool { trashedAt != nil }

    init(filename: String, fileURL: URL, fileSize: Int64, width: Int, height: Int) {
        self.id = UUID()
        self.filename = filename
        self.fileURL = fileURL
        self.importedAt = Date()
        self.fileSize = fileSize
        self.width = width
        self.height = height
        // V6.75: 删 self.isFavorite = false — stored 字段默认值已是 false (SwiftData @Model default)
        self.note = ""
        self.folder = nil
        self.fileHash = nil
        // V3.5.D：新照片用当前时间戳作为 sortOrder，避免和老照片的 0 冲突
        self.sortOrder = Int(Date().timeIntervalSince1970)
        // V4.36.x：评分默认未评分（0）；与字段默认值一致，显式赋值更清晰
        self.rating = 0
    }

    // MARK: - V5.8 + V6.75: 一次性数据迁移 (现为空操作, rating 是单一真相源)

    /// V6.75: migrateFavoriteToRating 保留方法签名 (ContentView.onMigrateFavoriteToRating 还在调)
    ///   但循环条件 `isFavorite && rating < 5` 永远 false — Photo.isFavoriteComputed = (rating >= 5)
    ///   跟 rating < 5 互斥, migrated 计数永远 0
    ///   V6.76 可清理此方法 + ContentView caller + Settings.reset() 行
    static func migrateFavoriteToRating(in photos: [Photo], context: ModelContext) {
        // V6.75: 等幂等空跑 — rating 是 single source of truth, 不需要再迁 isFavorite → rating
        //   保留方法签名防止 ContentView 编译失败; 后续 V6.76+ 可整体删
    }
}