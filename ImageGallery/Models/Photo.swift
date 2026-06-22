//
//  Photo.swift
//  ImageGallery
//
//  图片数据模型。用 SwiftData 持久化。
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

    // V6.68 (Q8 Schema V3): ROLLBACK — 加 SwiftData VersionedSchema V3 + Photo 4 个 EXIF optional 字段
    //   触发 test runner crash (Existing V2 store 在 lightweight ALTER TABLE 时 abort, ImageGalleryApp.init() 失败)
    //   V6.20 audit #14 #15 早就预警 schema migration 风险高 — 此风险确实实现
    //   决策: 全部 rollback 到 V6.67 状态, 保留注释记录教训
    //   后续 round: SwiftData tooling 完善 + 自定义 migration stage (而非 lightweight) 才重试

    // ─── 用户标记 ───
    // V5.8: isFavorite 字段保留 stored（SwiftData schema 约束——改 computed 需要 schema migration）
    //   语义上 = (rating >= 5)——V5.7 砍 UI 后本字段是 dead data
    //   V5.8 加 migrateFavoriteToRating() 一次性把历史数据 rating 升到 5
    //   未来 round 9 做 SwiftData VersionedSchema migration 彻底删字段
    var isFavorite: Bool
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
        self.isFavorite = false
        self.note = ""
        self.folder = nil
        self.fileHash = nil
        // V3.5.D：新照片用当前时间戳作为 sortOrder，避免和老照片的 0 冲突
        self.sortOrder = Int(Date().timeIntervalSince1970)
        // V4.36.x：评分默认未评分（0）；与字段默认值一致，显式赋值更清晰
        self.rating = 0
    }

    // MARK: - V5.8: 一次性数据迁移

    /// V5.8: 把历史 isFavorite=true 数据的 rating 升到 5
    ///   语义合并：收藏 = 评分 ≥ 5——isFavorite 字段保留 stored（SwiftData schema 约束）
    ///   改 computed 需要 VersionedSchema migration——下一轮做
    ///   本次先把数据对齐——isFavorite=true 的照片 rating 必须 ≥ 5
    ///   调用：ContentView 启动 .onAppear 跑一次（幂等——重复跑无副作用）
    static func migrateFavoriteToRating(in photos: [Photo], context: ModelContext) {
        var migrated = 0
        for photo in photos where photo.isFavorite && photo.rating < 5 {
            photo.rating = 5
            migrated += 1
        }
        if migrated > 0 {
            // V6.74.3: saveWithLog 替代 try? context.save() — 失败时 Logger.swiftData.error 留诊断线索
            //   跟 SwiftDataLogging.swift:77 同 pattern, 启动幂等迁移不抛错, 但失败需 log
            context.saveWithLog()
        }
    }
}
