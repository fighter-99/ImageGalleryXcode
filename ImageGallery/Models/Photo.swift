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
    }
}
