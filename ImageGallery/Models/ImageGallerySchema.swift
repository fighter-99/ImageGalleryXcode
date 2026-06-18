//
//  ImageGallerySchema.swift
//  ImageGallery
//
//  V3.6.7 NEW: 显式 SwiftData VersionedSchema。
//
//  设计：
//  - V1 = baseline (Photo / Folder / Tag)
//  - V2 (P4.1): 加 SmartFolder — 用户自定义智能文件夹
//  - V3+ 继续在 V2 基础上加字段/关系
//
//  跟轻量级自动迁移的关系：
//  - 之前 V3.6 加 trashedAt 用了"轻量级自动迁移"（SwiftData 自动检测新增 Optional 字段）
//  - VersionedSchema 提供显式版本管理 + 显式 MigrationPlan，是更严谨的路径
//  - V1 → V2 是 lightweight 级别 (新增 @Model 表), V2 stages 用 .lightweight
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
