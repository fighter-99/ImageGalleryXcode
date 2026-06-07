//
//  ImageGalleryMigrationPlan.swift
//  ImageGallery
//
//  V3.6.7 NEW: SwiftData 显式 SchemaMigrationPlan。
//
//  V1 是 baseline，没有迁移阶段。未来加 V2 时：
//  1. 新建 ImageGallerySchemaV2: VersionedSchema
//  2. 在 schemas 里加 [V1, V2]
//  3. 在 stages 里加 .migration(from: V1.self, to: V2.self)
//
//  当前 stages 为空（仅 V1，不需要迁移）。
//

import Foundation
import SwiftData

enum ImageGalleryMigrationPlan: SchemaMigrationPlan {
    /// 所有 schema 版本（按版本顺序）
    static var schemas: [any VersionedSchema.Type] {
        [ImageGallerySchemaV1.self]
    }

    /// 迁移阶段列表
    /// - V1 是 baseline，无迁移阶段
    /// - 未来 V2 在这里加 .migration(from: V1.self, to: V2.self)
    static var stages: [MigrationStage] {
        // V1 是 baseline，没有迁移阶段。空数组是合法的（SwiftData 接受空 stages）。
        return []
    }
}
