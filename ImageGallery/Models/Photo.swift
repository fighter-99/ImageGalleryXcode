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
    var filename: String
    var fileURL: URL
    var importedAt: Date

    // ─── 图片属性 ───
    var fileSize: Int64
    var width: Int
    var height: Int

    // ─── 用户标记 ───
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
}
