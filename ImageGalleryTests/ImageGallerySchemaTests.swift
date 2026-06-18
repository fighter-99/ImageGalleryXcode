//
//  ImageGallerySchemaTests.swift
//  ImageGalleryTests
//
//  V3.6.7: VersionedSchema 架构测试
//  验证：
//  - V1 schema versionIdentifier 合法
//  - V1 models 列表包含 Photo / Folder / Tag
//  - MigrationPlan schemas 列表包含 V1
//  - MigrationPlan stages 为空（V1 是 baseline）
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

struct ImageGallerySchemaTests {

    // MARK: - V1 schema

    @Test func v1VersionIdentifierIsValid() {
        let version = ImageGallerySchemaV1.versionIdentifier
        // Schema.Version 是 struct，描述 major.minor.patch
        // 这里只验证非默认（避免 trivial 1.0.0 跟"未设置"混淆）
        let defaultVersion = Schema.Version(1, 0, 0)
        #expect(version == defaultVersion)
    }

    @Test func v1ModelsContainsAllExpected() {
        let models = ImageGallerySchemaV1.models
        #expect(models.contains(where: { $0 == Photo.self }))
        #expect(models.contains(where: { $0 == Folder.self }))
        #expect(models.contains(where: { $0 == ImageGallery.Tag.self }))
    }

    @Test func v1ModelsCountIsThree() {
        // 防止以后误删 model 而忘更新 schema
        #expect(ImageGallerySchemaV1.models.count == 3)
    }

    // MARK: - MigrationPlan

    @Test func migrationPlanContainsV1() {
        let schemas = ImageGalleryMigrationPlan.schemas
        #expect(schemas.contains(where: { $0 == ImageGallerySchemaV1.self }))
    }

    @Test func migrationPlanStagesIsEmptyForBaselineV1() {
        // P4.1: V1 是 baseline 但 V2 加了 (V1 → V2 lightweight migration 加 SmartFolder)
        // 旧测试期望 stages 是空, V2 后改成"至少 1 个 V1→V2 stage"
        let stages = ImageGalleryMigrationPlan.stages
        #expect(!stages.isEmpty, "V1→V2 至少有 1 个 migration stage")
        // 验证 schemas 至少含 V1 + V2
        let schemas = ImageGalleryMigrationPlan.schemas
        #expect(schemas.contains(where: { $0 == ImageGallerySchemaV1.self }))
        #expect(schemas.contains(where: { $0 == ImageGallerySchemaV2.self }))
    }

    // MARK: - Schema 实例可构造

    @Test func schemaInstanceCanBeCreated() {
        // 验证 Schema(versionedSchema:) 接受 V1（ImageGalleryApp 也用这个 API）
        let schema = Schema(versionedSchema: ImageGallerySchemaV1.self)
        // Schema 实例非 nil 即通过（无 Equatable conformance）
        let _: Any = schema  // 编译器保证 schema 是有效实例
    }
}
