//
//  ImageGalleryMigrationPlan.swift
//  ImageGallery
//
//  V3.6.7 NEW: SwiftData 显式 SchemaMigrationPlan。
//  P4.1: V1 → V2 加 SmartFolder 表 (lightweight).
//
//  V6.75 设计变更: 不开 V3 schema. Photo.isFavorite 改 computed, 但 V2 schema 仍描述老字段集.
//    决策: SwiftData 容忍 runtime Photo 字段集与 V2 schema 不同, 多余 isFavorite 列忽略
//

import Foundation
import SwiftData

enum ImageGalleryMigrationPlan: SchemaMigrationPlan {
    /// 所有 schema 版本（按版本顺序）
    ///   V6.94.1: 加 ImageGallerySchemaV3 (P0 #3 Markup PencilKit — Photo.markupData)
    static var schemas: [any VersionedSchema.Type] {
        [ImageGallerySchemaV1.self, ImageGallerySchemaV2.self, ImageGallerySchemaV3.self]
    }

    /// 迁移阶段列表
    /// - V1 → V2: lightweight (新增 SmartFolder 表, SwiftData 自动建表)
    /// - V2 → V3: lightweight (新增 Photo.markupData Optional 字段, SwiftData 自动加列)
    ///   V6.68/V6.75 教训: 只用 lightweight migration, 不要 custom stage (闭包在 SQLite store 跑有 abort 风险)
    static var stages: [MigrationStage] {
        [
            // V1 → V2: lightweight
            .lightweight(fromVersion: ImageGallerySchemaV1.self, toVersion: ImageGallerySchemaV2.self),
            // V6.94.1: V2 → V3: lightweight (新增 Photo.markupData: Data?)
            .lightweight(fromVersion: ImageGallerySchemaV2.self, toVersion: ImageGallerySchemaV3.self)
        ]
    }
}