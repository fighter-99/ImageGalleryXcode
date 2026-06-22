//
//  ImageGallerySchema.swift
//  ImageGallery
//
//  V3.6.7 NEW: 显式 SwiftData VersionedSchema。
//
//  设计：
//  - V1 = baseline (Photo / Folder / Tag)
//  - V2 (P4.1): 加 SmartFolder — 用户自定义智能文件夹
//
//  V6.75 设计变更: Photo.isFavorite 改 computed (rating >= 5), 不开 V3 schema
//    V6.68 试过 V3 + EXIF 字段 (lightweight), 触发 test runner crash
//    V6.75 试过 custom stage V2 → V3, 同样触发 production init crash (custom migration
//      闭包在 SQLite store 跑有 abort 风险, 跟 V6.68 同源)
//    决策: 保留 V2 schema, runtime Photo 改 computed — SwiftData 容忍 runtime Photo 字段集
//      ≠ V2 schema 字段集 (多余列忽略, 缺字段自动迁移). 老 V2 store 多余 isFavorite 列
//      永久保留 (无副作用, 只占存储), runtime 不写不读
//
//

import Foundation
import SwiftData

/// V1 schema: baseline (V3.6.7)
enum ImageGallerySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Photo.self, Folder.self, Tag.self]
    }
}

/// P4.1 NEW: V2 schema 加 SmartFolder
/// - 跟 V1 区别: 新增 SmartFolder @Model 表
/// - lightweight 自动迁移: SwiftData 检测新表, 自动建表
enum ImageGallerySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Photo.self, Folder.self, Tag.self, SmartFolder.self]
    }
}