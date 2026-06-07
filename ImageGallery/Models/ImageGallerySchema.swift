//
//  ImageGallerySchema.swift
//  ImageGallery
//
//  V3.6.7 NEW: 显式 SwiftData VersionedSchema。
//
//  设计：
//  - V1 = 当前 baseline schema（Photo 含 trashedAt / Folder / Tag）
//  - 未来 V2+ 在 V1 基础上加字段/关系，每个版本号对应一个 schema enum
//  - 列出所有 model 是 V1 的"快照"，防止某天 model 改名/删除时 schema 漂移
//
//  跟轻量级自动迁移的关系：
//  - 之前 V3.6 加 trashedAt 用了"轻量级自动迁移"（SwiftData 自动检测新增 Optional 字段）
//  - VersionedSchema 提供显式版本管理 + 显式 MigrationPlan，是更严谨的路径
//  - V1 是 baseline，stages 为空。未来 V2 stages = v1→v2 显式迁移
//

import Foundation
import SwiftData

/// V1 schema：当前 baseline
/// 包含：Photo / Folder / Tag 三个 @Model
enum ImageGallerySchemaV1: VersionedSchema {
    /// Schema 版本号（major.minor.patch）
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Photo.self, Folder.self, Tag.self]
    }
}
