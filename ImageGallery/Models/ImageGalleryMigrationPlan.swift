//
//  ImageGalleryMigrationPlan.swift
//  ImageGallery
//
//  V3.6.7 NEW: SwiftData 显式 SchemaMigrationPlan。
//  P4.1: V1 → V2 加 SmartFolder 表
//

import Foundation
import SwiftData

enum ImageGalleryMigrationPlan: SchemaMigrationPlan {
    /// 所有 schema 版本（按版本顺序）
    static var schemas: [any VersionedSchema.Type] {
        [ImageGallerySchemaV1.self, ImageGallerySchemaV2.self]
    }

    /// 迁移阶段列表
    /// - V1 → V2: lightweight (新增 SmartFolder 表, SwiftData 自动建表, 不需 custom migration)
    static var stages: [MigrationStage] {
        [
            // V1 → V2: 仅新增 @Model 表, SwiftData 自带 .lightweight 推断
            // (不需要 MigrationPlan.customMigration, 告诉 SwiftData "加表就 OK")
            .lightweight(fromVersion: ImageGallerySchemaV1.self, toVersion: ImageGallerySchemaV2.self)
        ]
    }
}
