//
//  Folder.swift
//  ImageGallery
//
//  文件夹数据模型。用 SwiftData 持久化。
//

import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var id: UUID
    var name: String               // 文件夹名
    var createdAt: Date            // 创建时间
    var icon: String               // SF Symbol 图标

    // 与 Photo 的反向关系：删除文件夹时，图片的 folder 字段设为 nil（不删图片）
    @Relationship(deleteRule: .nullify, inverse: \Photo.folder)
    var photos: [Photo] = []

    init(name: String, icon: String = "folder.fill") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.icon = icon
    }
}
