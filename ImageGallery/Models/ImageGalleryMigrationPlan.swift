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
    static var schemas: [any VersionedSchema.Type] {
        [ImageGallerySchemaV1.self, ImageGallerySchemaV2.self]
    }

    /// 迁移阶段列表
    /// - V1 → V2: lightweight (新增 SmartFolder 表, SwiftData 自动建表)
    static var stages: [MigrationStage] {
        [
            // V1 → V2: lightweight
            .lightweight(fromVersion: ImageGallerySchemaV1.self, toVersion: ImageGallerySchemaV2.self)
        ]
    }
}