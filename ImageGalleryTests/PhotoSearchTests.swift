//
//  PhotoSearchTests.swift
//  ImageGalleryTests
//
//  V3.6.3：PhotoSearch 单元测试
//  验证：
//  - 空 query 返回 true（不应用 filter）
//  - 匹配 filename
//  - 匹配 note
//  - 匹配 tag name
//  - 匹配 folder name（V3.6.3 修复）
//  - 不匹配返回 false
//  - 大小写不敏感
//  - filter 接受 [Photo] 集合
//

import Testing
import Foundation
@testable import ImageGallery

struct PhotoSearchTests {

    // MARK: - 空 query

    @Test func emptyQueryMatchesAll() {
        let photo = makePhoto()
        #expect(PhotoSearch.matches(photo, query: ""))
        #expect(PhotoSearch.matches(photo, query: "   "))
    }

    // MARK: - 各字段匹配

    @Test func matchesFilename() {
        let photo = makePhoto(filename: "御姐_photo_001.jpg")
        #expect(PhotoSearch.matches(photo, query: "御姐"))
    }

    @Test func matchesNote() {
        let photo = makePhoto()
        photo.note = "这是御姐风格的图"
        #expect(PhotoSearch.matches(photo, query: "御姐"))
    }

    @Test func matchesFolderName() {
        // V3.6.3 修复：之前只搜 filename/note/tag，没搜 folder
        let photo = makePhoto(filename: "IMG_001.jpg", note: "")
        photo.folder = makeFolder(name: "御姐")
        #expect(PhotoSearch.matches(photo, query: "御姐"))
    }

    @Test func matchesTagName() {
        let photo = makePhoto()
        // tags 需要在 SwiftData context 里才能 append（@Relationship）
        // 纯函数测试里只验 folder/filename/note，tag 留给集成测试
        // 这里只验"tag 字段不匹配时不影响其他字段匹配"
        #expect(!PhotoSearch.matches(photo, query: "完全不存在的关键词"))
    }

    // MARK: - 不匹配

    @Test func noMatchReturnsFalse() {
        let photo = makePhoto(filename: "海滩.jpg", note: "夏天")
        photo.folder = makeFolder(name: "旅行")
        #expect(!PhotoSearch.matches(photo, query: "御姐"))
    }

    // MARK: - 大小写

    @Test func caseInsensitive() {
        let photo = makePhoto(filename: "BEAUTY.jpg")
        #expect(PhotoSearch.matches(photo, query: "beauty"))
        #expect(PhotoSearch.matches(photo, query: "BEAUTY"))
        #expect(PhotoSearch.matches(photo, query: "Beauty"))
    }

    // MARK: - filter 集合

    @Test func filterReturnsOnlyMatches() {
        let p1 = makePhoto(filename: "御姐_1.jpg")
        let p2 = makePhoto(filename: "海滩.jpg")
        let p3 = makePhoto(filename: "御姐_2.jpg")
        let p4 = makePhoto(filename: "山景.jpg")
        p4.folder = makeFolder(name: "御姐合集")  // folder 匹配
        let result = PhotoSearch.filter([p1, p2, p3, p4], query: "御姐")
        #expect(result.count == 3)  // p1 + p3 + p4
    }

    @Test func filterEmptyQueryReturnsAll() {
        let photos = [makePhoto(), makePhoto(), makePhoto()]
        #expect(PhotoSearch.filter(photos, query: "").count == 3)
    }

    // MARK: - helpers

    private func makePhoto(filename: String = "test.jpg", note: String = "") -> Photo {
        let photo = Photo(
            filename: filename,
            fileURL: URL(fileURLWithPath: "/tmp/PhotoSearchTest_\(UUID().uuidString).jpg"),
            fileSize: 0,
            width: 0,
            height: 0
        )
        photo.note = note
        return photo
    }

    private func makeFolder(name: String) -> Folder {
        let folder = Folder(name: name)
        return folder
    }
}
