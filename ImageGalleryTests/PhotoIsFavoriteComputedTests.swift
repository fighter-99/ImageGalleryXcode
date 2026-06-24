//
//  PhotoIsFavoriteComputedTests.swift
//  ImageGalleryTests
//
//  V6.75: Photo.isFavoriteComputed 验证 (rating >= 5, computed property)
//    V5.8 注释 "改 computed 需要 VersionedSchema migration" — 这次通过
//      stored isFavorite (V2 schema 兼容性保留) + computed isFavoriteComputed (rating >= 5)
//    V6.68 + V6.75 试过真删 stored 字段 (V3 schema lightweight + custom stage), 都触发
//      production init crash. V6.75 决策: 保留 stored 字段, 加 isFavoriteComputed,
//      启动幂等 migrateFavoriteToRating 改为 no-op
//
//  验证:
//    - Photo.isFavoriteComputed 是 computed (rating >= 5), 不是 stored
//    - 边界: rating 0..5 行为正确
//    - Photo.isFavorite 仍 stored (V2 schema 兼容, 业务代码不应用)
//    - V2 schema 描述 4 models (Photo / Folder / Tag / SmartFolder)
//    - migrateFavoriteToRating 等幂等 no-op
//

import Testing
import Foundation
import SwiftData
@testable import ImageGallery

@MainActor
@Suite(.serialized)
struct PhotoIsFavoriteComputedTests {

    // MARK: - Photo.isFavoriteComputed 是 computed (rating >= 5)

    @Test func newPhotoIsFavoriteComputedIsFalse() {
        // 新构造 Photo 默认 rating=0 → isFavoriteComputed=false
        let photo = Photo(
            filename: "new.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/new.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        #expect(photo.rating == 0)
        #expect(photo.isFavoriteComputed == false)
    }

    @Test func rating5MakesIsFavoriteComputedTrue() {
        let photo = Photo(
            filename: "5star.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/5star.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        photo.rating = 5
        #expect(photo.isFavoriteComputed == true)
    }

    @Test func rating4KeepsIsFavoriteComputedFalse() {
        let photo = Photo(
            filename: "4star.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/4star.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        photo.rating = 4
        #expect(photo.isFavoriteComputed == false)
    }

    @Test func ratingTransitionUpdatesIsFavoriteComputed() {
        // rating 变化时 isFavoriteComputed 实时反映 (computed getter 每次 re-evaluate)
        let photo = Photo(
            filename: "trans.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/trans.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        photo.rating = 3
        #expect(photo.isFavoriteComputed == false)
        photo.rating = 5
        #expect(photo.isFavoriteComputed == true)
        photo.rating = 4
        #expect(photo.isFavoriteComputed == false)
        photo.rating = 5
        #expect(photo.isFavoriteComputed == true)
    }

    @Test func ratingAllBoundaries() {
        // 0..5 边界全覆盖
        let photo = Photo(
            filename: "boundary.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/boundary.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        for r in 0..<5 {
            photo.rating = r
            #expect(photo.isFavoriteComputed == false, "rating \(r) 不应 isFavoriteComputed")
        }
        photo.rating = 5
        #expect(photo.isFavoriteComputed == true, "rating 5 应 isFavoriteComputed")
    }

    // MARK: - Photo.isFavorite 仍 stored (V2 schema 兼容性)

    @Test func photoIsFavoriteStoredDefaultsFalse() {
        // V6.75: isFavorite 仍是 stored 字段, 默认值 false
        //   保留因为 V2 schema 期望此字段, 真删会触发 init crash
        //   业务代码应统一用 isFavoriteComputed, 不写 isFavorite
        let photo = Photo(
            filename: "stored.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/stored.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        #expect(photo.isFavorite == false)  // stored 默认值
    }

    @Test func photoIsFavoriteStoredDoesNotAutoTrackRating() {
        // isFavorite (stored) 不会自动跟 rating 同步 — 业务代码不应用这个字段
        //   真版语义是 isFavoriteComputed (rating >= 5)
        let photo = Photo(
            filename: "manual.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/manual.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        photo.rating = 5
        // isFavorite (stored) 仍是默认 false (没人写它)
        #expect(photo.isFavorite == false)
        // isFavoriteComputed 反映 rating
        #expect(photo.isFavoriteComputed == true)
    }

    // MARK: - migrateFavoriteToRating 现在等幂等空跑

    /// V6.75: 模拟 V5.8 migrateFavoriteToRating 内部循环
    ///   业务代码现在 isFavoriteComputed = (rating >= 5), 跟 rating < 5 互斥
    ///   循环条件用 isFavorite (stored) 仍然可能 true (V5.8 老的脏数据)
    ///   所以这循环仍能处理老数据, 但迁移到 isFavorite (stored) 无意义 (反正不写)
    ///   V6.75: 实际生产中 stored isFavorite 永远是默认 false (V5.8 启动迁移已把所有脏数据 rating 升 5)
    private func simulateMigrate(_ photos: [Photo]) -> Int {
        var migrated = 0
        for photo in photos where photo.isFavorite && photo.rating < 5 {
            photo.rating = 5
            migrated += 1
        }
        return migrated
    }

    @Test func migrateFavoriteToRatingIsNoOpForFreshPhotos() {
        // 新照片 isFavorite 默认 false → migrate 跳过
        let photos: [Photo] = (0..<3).map { i in
            let p = Photo(
                filename: "fresh-\(i).jpg",
                fileURL: URL(fileURLWithPath: "/tmp/fresh-\(i).jpg"),
                fileSize: 0,
                width: 100,
                height: 100
            )
            p.rating = [3, 5, 2][i]
            return p
        }
        let migrated = simulateMigrate(photos)
        #expect(migrated == 0)  // stored isFavorite 默认 false, 全部跳过
    }

    @Test func migrateFavoriteToRatingAlignsDirtyStoredData() {
        // 模拟 V5.8 之前的脏数据 (stored isFavorite=true, rating=3)
        //   老 store 升级 V6.75 时, V5.8 启动迁移仍会跑 (Photo.migrateFavoriteToRating)
        //   把 stored isFavorite=true 的脏数据 rating 升到 5
        let photo = Photo(
            filename: "dirty.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/dirty.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        photo.isFavorite = true  // 模拟老 store 脏数据
        photo.rating = 3
        let migrated = simulateMigrate([photo])
        #expect(migrated == 1)
        #expect(photo.rating == 5)
        // 业务应统一用 isFavoriteComputed — 现在也是 true
        #expect(photo.isFavoriteComputed == true)
    }

    // MARK: - V2 schema 描述 (保留 V2, 不开 V3)

    @Test func v2VersionIdentifierIsValid() {
        let version = ImageGallerySchemaV2.versionIdentifier
        let expected = Schema.Version(2, 0, 0)
        #expect(version == expected)
    }

    @Test func v2ModelsCountIsFour() {
        // V2 = Photo / Folder / Tag / SmartFolder
        #expect(ImageGallerySchemaV2.models.count == 4)
    }

    @Test func migrationPlanSchemaOrderAscending() {
        // V6.94.1: V1 → V2 → V3 (P0 #3 Markup 加 Photo.markupData 字段)
        let schemas = ImageGalleryMigrationPlan.schemas
        #expect(schemas.count == 3)
        #expect(schemas[0] == ImageGallerySchemaV1.self)
        #expect(schemas[1] == ImageGallerySchemaV2.self)
        #expect(schemas[2] == ImageGallerySchemaV3.self)
    }

    @Test func migrationPlanStagesLightweightOnly() {
        // V6.94.1: V1 → V2 lightweight + V2 → V3 lightweight (P0 #3 Markup)
        //   都是 lightweight — 只加 Optional 字段, SwiftData 自动迁移 (V6.68/V6.75 教训)
        let stages = ImageGalleryMigrationPlan.stages
        #expect(stages.count == 2)
    }

    // MARK: - V2 schema 兼容性 (Photo.isFavorite stored 字段存在)

    @Test func photoIsFavoriteStoredFieldAccessible() {
        // V6.75: stored isFavorite 字段可读写 (V2 schema 兼容, 业务不应用但保留访问)
        let photo = Photo(
            filename: "access.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/access.jpg"),
            fileSize: 0,
            width: 100,
            height: 100
        )
        photo.isFavorite = true  // 可写 (stored 字段)
        #expect(photo.isFavorite == true)
        photo.isFavorite = false  // 可改回
        #expect(photo.isFavorite == false)
    }
}