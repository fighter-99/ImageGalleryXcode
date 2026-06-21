//
//  PhotoStatsFilterTests.swift
//  ImageGalleryTests
//
//  V4.36.x: 4 个纯函数 helper 的单元测试
//  - folderFilter (OR 语义；folder=nil 排除)
//  - tagFilter (OR 语义；无 tag 排除)
//  - shapeFilter (OR 语义；从 width/height 派生)
//  - ratingFilter (≥N 星；等于也算过)
//
//  设计：纯函数 + 直接构造 Photo，零 SwiftData 依赖
//  测 20 个 case × 4 helper
//

import Testing
import Foundation
@testable import ImageGallery

struct PhotoStatsFilterTests {

    // MARK: - folderFilter (5)

    @Test func folderFilterEmptyIDsReturnsEmpty() {
        // 短路在 PhotoStats.filtered() 层级（!ids.isEmpty 才调 helper）
        // helper 本身：ids=[] 时 `ids.contains(fid)` 永远 false → 返回空
        // 这是正确的"无 id 命中任何 photo"行为
        let photos = [makePhoto()]
        #expect(PhotoStats.folderFilter(photos, ids: []).isEmpty)
    }

    @Test func folderFilterKeepsMatchingID() {
        let folder = makeFolder()
        let p1 = makePhoto()
        p1.folder = folder
        let p2 = makePhoto()
        let result = PhotoStats.folderFilter([p1, p2], ids: [folder.id])
        #expect(result.count == 1)
        #expect(result[0].id == p1.id)
    }

    @Test func folderFilterORSemantics() {
        let f1 = makeFolder()
        let f2 = makeFolder()
        let p1 = makePhoto(); p1.folder = f1
        let p2 = makePhoto(); p2.folder = f2
        let p3 = makePhoto()  // 无 folder
        let result = PhotoStats.folderFilter([p1, p2, p3], ids: [f1.id, f2.id])
        #expect(result.count == 2)
    }

    @Test func folderFilterDropsUnfiled() {
        // folder == nil 的照片不在任何 folder id 集合内 → 排除
        let folder = makeFolder()
        let unfiled = makePhoto()  // folder=nil
        let filed = makePhoto()
        filed.folder = folder
        let result = PhotoStats.folderFilter([unfiled, filed], ids: [folder.id])
        #expect(result.count == 1)
        #expect(result[0].id == filed.id)
    }

    @Test func folderFilterEmptySetOfIDsDropsUnfiled() {
        // ids=[某个 folder] 但 photo 全无 folder → 空
        let folder = makeFolder()
        let unfiled1 = makePhoto()
        let unfiled2 = makePhoto()
        let result = PhotoStats.folderFilter([unfiled1, unfiled2], ids: [folder.id])
        #expect(result.isEmpty)
    }

    // MARK: - tagFilter (5)

    @Test func tagFilterEmptyIDsReturnsEmpty() {
        // helper 本身：ids=[] 时 `ids.contains(anyTag.id)` 永远 false → 返回空
        let photos = [makePhoto()]
        #expect(PhotoStats.tagFilter(photos, ids: []).isEmpty)
    }

    @Test func tagFilterKeepsPhotosWithAnyMatchingTag() {
        let tag = makeTag()
        let p1 = makePhoto()
        p1.tags.append(tag)
        let p2 = makePhoto()
        let result = PhotoStats.tagFilter([p1, p2], ids: [tag.id])
        #expect(result.count == 1)
        #expect(result[0].id == p1.id)
    }

    @Test func tagFilterDropsPhotosWithNoTags() {
        // 无 tag 的照片不命中任何 tag id → 排除
        let tag = makeTag()
        let untagged = makePhoto()  // tags=[]
        let tagged = makePhoto()
        tagged.tags.append(tag)
        let result = PhotoStats.tagFilter([untagged, tagged], ids: [tag.id])
        #expect(result.count == 1)
    }

    @Test func tagFilterMultipleTagsPerPhoto() {
        // photo 有 [A, B]，ids=[A] → 命中（A 是 ids 之一）
        let tagA = makeTag()
        let tagB = makeTag()
        let p = makePhoto()
        p.tags.append(tagA)
        p.tags.append(tagB)
        let result = PhotoStats.tagFilter([p], ids: [tagA.id])
        #expect(result.count == 1)
    }

    @Test func tagFilterIsOrNotAnd() {
        // OR 验证：photo 有 [A]，ids=[A, B] → 命中（A 在 ids 内即过）
        let tagA = makeTag()
        let tagB = makeTag()
        let p = makePhoto()
        p.tags.append(tagA)  // 只加 A
        let result = PhotoStats.tagFilter([p], ids: [tagA.id, tagB.id])
        #expect(result.count == 1)  // OR 语义：A 命中即过
    }

    // MARK: - shapeFilter (5)

    @Test func shapeFilterEmptyShapesReturnsEmpty() {
        // helper 本身：shapes=[] 时 `shapes.contains(anyShape)` 永远 false → 返回空
        let p1 = makePhoto(width: 1920, height: 1080)
        let p2 = makePhoto(width: 1080, height: 1920)
        #expect(PhotoStats.shapeFilter([p1, p2], shapes: []).isEmpty)
    }

    @Test func shapeFilterKeepsLandscape() {
        let p = makePhoto(width: 1920, height: 1080)
        let result = PhotoStats.shapeFilter([p], shapes: [.landscape])
        #expect(result.count == 1)
    }

    @Test func shapeFilterKeepsPortrait() {
        let p = makePhoto(width: 1080, height: 1920)
        let result = PhotoStats.shapeFilter([p], shapes: [.portrait])
        #expect(result.count == 1)
    }

    @Test func shapeFilterKeepsSquare() {
        // 1000×1000 + .square → 命中
        let p = makePhoto(width: 1000, height: 1000)
        let result = PhotoStats.shapeFilter([p], shapes: [.square])
        #expect(result.count == 1)
    }

    @Test func shapeFilterMultiShape() {
        // OR 验证：[.landscape, .square] → 两种都过
        let landscape = makePhoto(width: 1920, height: 1080)
        let portrait = makePhoto(width: 1080, height: 1920)
        let square = makePhoto(width: 1000, height: 1000)
        let result = PhotoStats.shapeFilter(
            [landscape, portrait, square],
            shapes: [.landscape, .square]
        )
        #expect(result.count == 2)  // portrait 排除
    }

    // MARK: - ratingFilter (5)

    @Test func ratingFilterZeroIsNoOp() {
        // minRating=0 → 全部保留（不过滤）
        let p1 = makePhoto(rating: 0)
        let p2 = makePhoto(rating: 5)
        #expect(PhotoStats.ratingFilter([p1, p2], minRating: 0).count == 2)
    }

    @Test func ratingFilterKeepsAboveOrEqual() {
        // ≥N 含 N
        let p1 = makePhoto(rating: 3)
        let p2 = makePhoto(rating: 4)
        let p3 = makePhoto(rating: 5)
        let result = PhotoStats.ratingFilter([p1, p2, p3], minRating: 4)
        #expect(result.count == 2)  // p1=3 排除
    }

    @Test func ratingFilterDropsBelow() {
        // photo.rating=2, min=3 → 排除
        let low = makePhoto(rating: 2)
        let high = makePhoto(rating: 4)
        let result = PhotoStats.ratingFilter([low, high], minRating: 3)
        #expect(result.count == 1)
        #expect(result[0].id == high.id)
    }

    @Test func ratingFilterBoundary() {
        // 边界：photo.rating=3, min=3 → 命中（≥ 含 =）
        let p = makePhoto(rating: 3)
        let result = PhotoStats.ratingFilter([p], minRating: 3)
        #expect(result.count == 1)
    }

    @Test func ratingFilterTopScore() {
        // 5 颗 + min=5 → 命中
        let five = makePhoto(rating: 5)
        let four = makePhoto(rating: 4)
        let result = PhotoStats.ratingFilter([five, four], minRating: 5)
        #expect(result.count == 1)
        #expect(result[0].id == five.id)
    }

    // MARK: - helpers

    private func makePhoto(width: Int = 1000, height: Int = 1000, rating: Int = 0) -> Photo {
        let p = Photo(
            filename: "t.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/PhotoStatsFilterTest_\(UUID().uuidString).jpg"),
            fileSize: 0,
            width: width,
            height: height
        )
        p.rating = rating
        return p
    }

    private func makeFolder() -> Folder {
        Folder(name: "test_folder_\(UUID().uuidString)")
    }

    private func makeTag() -> ImageGallery.Tag {
        ImageGallery.Tag(name: "test_tag_\(UUID().uuidString)", colorHex: "#5B8FF9")
    }

    // MARK: - V6.59 (audit P2.1): smartFolderCount lazy

    @Test func smartFolderCount_emptyFilter_returnsAll() {
        // V6.59: smartFolderFilter.isActive=false → count == photos.count (短路)
        let photos = (0..<100).map { _ in makePhoto() }
        let count = PhotoStats.smartFolderCount(photos, smartFolderFilter: .empty)
        #expect(count == 100)
    }

    @Test func smartFolderCount_activeFilter_excludesTrashed() {
        // V6.59: matchesSmartFolderFilter 默认排除 isInTrash
        // 5 photos: photos[0] trashed + rating=5, others rating=5
        // filter: rating>=4 (让 isActive=true) — 4 non-trashed 命中, 1 trashed 排除
        var photos = (0..<5).map { _ in makePhoto(rating: 5) }
        photos[0].trashedAt = Date()  // trashed
        let filter = FilterState(folders: [], tags: [], shapes: [], minRating: 4)
        let count = PhotoStats.smartFolderCount(photos, smartFolderFilter: filter)
        #expect(count == 4, "5 photos 总, 1 trashed, filter rating>=4 → 4 命中")
    }

    @Test func smartFolderCount_shapeFilter_appliesOnlyShape() {
        // V6.59: 4 维 AND, 但 shapes 过滤独立工作
        let p1 = makePhoto(width: 4000, height: 3000)  // landscape
        let p2 = makePhoto(width: 3000, height: 4000)  // portrait
        let p3 = makePhoto(width: 1000, height: 1000)  // square
        let filter = FilterState(folders: [], tags: [], shapes: [.landscape], minRating: 0)
        let count = PhotoStats.smartFolderCount([p1, p2, p3], smartFolderFilter: filter)
        #expect(count == 1)
    }

    @Test func smartFolderCount_ratingFilter_appliesOnlyMinRating() {
        let p1 = makePhoto(rating: 3)
        let p2 = makePhoto(rating: 5)
        let p3 = makePhoto(rating: 0)
        let filter = FilterState(folders: [], tags: [], shapes: [], minRating: 4)
        let count = PhotoStats.smartFolderCount([p1, p2, p3], smartFolderFilter: filter)
        #expect(count == 1, "rating >= 4 应该是 p2")
    }
}
