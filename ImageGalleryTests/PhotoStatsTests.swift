//
//  PhotoStatsTests.swift
//  ImageGalleryTests
//
//  V3.6.1：PhotoStats 纯函数单元测试
//

import Testing
import Foundation
@testable import ImageGallery

struct PhotoStatsTests {

    // MARK: - 过滤函数

    @Test func trashedFiltersByTrashedAt() {
        let photos = makePhotos(trashed: [true, false, true])
        #expect(PhotoStats.trashed(photos).count == 2)
    }

    @Test func inLibraryExcludesTrashed() {
        let photos = makePhotos(trashed: [true, false, true])
        #expect(PhotoStats.inLibrary(photos).count == 1)
        #expect(PhotoStats.inLibrary(photos).allSatisfy { !$0.isInTrash })
    }

    @Test func favoritesFiltersByIsFavorite() {
        // PhotoStats.favorites 不过滤 trashed（保持 SidebarView 旧行为：所有 favorite 都计数）
        let p1 = makePhoto(isFavorite: true, inTrash: false)
        let p2 = makePhoto(isFavorite: false, inTrash: false)
        let p3 = makePhoto(isFavorite: true, inTrash: true)
        #expect(PhotoStats.favorites([p1, p2, p3]).count == 2)
    }

    @Test func unfiledExcludesTrashed() {
        // Photo.folder 是 @Model 关系，纯函数测试不能 set；只测 trashed 排除
        // folder != nil 的排除逻辑留给集成测试
        let p1 = makePhoto(inTrash: false)  // 待整理
        let p2 = makePhoto(inTrash: true)   // 回收站（不算待整理）
        #expect(PhotoStats.unfiled([p1, p2]).count == 1)
    }

    // MARK: - 聚合函数

    @Test func totalSizeSumsAll() {
        let photos = [
            makePhoto(fileSize: 1000),
            makePhoto(fileSize: 2000),
            makePhoto(fileSize: 3000),
        ]
        #expect(PhotoStats.totalSize(photos) == 6000)
    }

    @Test func trashedSizeOnlyCountsTrashed() {
        let photos = [
            makePhoto(inTrash: true, fileSize: 1000),
            makePhoto(inTrash: false, fileSize: 2000),
            makePhoto(inTrash: true, fileSize: 3000),
        ]
        #expect(PhotoStats.trashedSize(photos) == 4000)
    }

    @Test func totalSizeHandlesEmpty() {
        #expect(PhotoStats.totalSize([]) == 0)
        #expect(PhotoStats.trashedSize([]) == 0)
    }

    // MARK: - 关系对象 count（V3.6.4 修复 sidebar count 与 grid 显示不一致）

    @Test func folderInLibraryCountExcludesTrashed() {
        let folder = makeFolder()
        folder.photos = [
            makePhoto(inTrash: false),
            makePhoto(inTrash: true),   // 应排除
            makePhoto(inTrash: false),
            makePhoto(inTrash: true),   // 应排除
        ]
        #expect(PhotoStats.inLibraryCount(folder) == 2)
    }

    @Test func tagInLibraryCountExcludesTrashed() {
        let tag = makeTag()
        tag.photos = [
            makePhoto(inTrash: false),
            makePhoto(inTrash: true),   // 应排除
        ]
        #expect(PhotoStats.inLibraryCount(tag) == 1)
    }

    @Test func folderInLibraryCountHandlesEmpty() {
        let folder = makeFolder()
        #expect(PhotoStats.inLibraryCount(folder) == 0)
    }

    // MARK: - helpers

    private func makePhotos(trashed: [Bool]) -> [Photo] {
        trashed.map { makePhoto(inTrash: $0) }
    }

    private func makePhoto(
        isFavorite: Bool = false,
        inTrash: Bool = false,
        fileSize: Int64 = 0
    ) -> Photo {
        let photo = Photo(
            filename: "t.jpg",
            fileURL: URL(fileURLWithPath: "/tmp/PhotoStatsTest_\(UUID().uuidString).jpg"),
            fileSize: fileSize,
            width: 0,
            height: 0
        )
        photo.isFavorite = isFavorite
        photo.trashedAt = inTrash ? Date() : nil
        return photo
    }

    private func makeFolder() -> Folder {
        Folder(name: "test_folder_\(UUID().uuidString)")
    }

    private func makeTag() -> ImageGallery.Tag {
        ImageGallery.Tag(name: "test_tag_\(UUID().uuidString)", colorHex: "#5B8FF9")
    }
}
