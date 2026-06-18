//
//  BatchRenameTemplateTests.swift
//  ImageGalleryTests
//
//  P4.2 批量重命名 — parser 纯函数测试
//
//  测试范围 (13 test):
//  - render n / n:N 零填充 / overflow 自然
//  - render originalName
//  - render mixed tokens
//  - render unknown token 透传
//  - render empty / whitespace throws
//  - uniquify no collision / within-batch / on-disk / both
//  - uniquify 无扩展名
//
//  跟 SwiftData / SwiftUI 解耦, 不需要 isolatedDefaults, 不需要 ModelContainer
//

import Testing
import Foundation
@testable import ImageGallery

@MainActor
struct BatchRenameTemplateTests {
    // MARK: - render {n}

    @Test func render_n_basic() throws {
        #expect(try BatchRenameTemplate.render(
            template: "{n}", index: 1, totalCount: 5, originalFilename: "foo"
        ) == "1")
        #expect(try BatchRenameTemplate.render(
            template: "{n}", index: 5, totalCount: 5, originalFilename: "foo"
        ) == "5")
    }

    @Test func render_n_withPrefixSuffix() throws {
        #expect(try BatchRenameTemplate.render(
            template: "photo_{n}", index: 3, totalCount: 5, originalFilename: "foo"
        ) == "photo_3")
        #expect(try BatchRenameTemplate.render(
            template: "{n}_copy", index: 2, totalCount: 5, originalFilename: "foo"
        ) == "2_copy")
    }

    // MARK: - render {n:N} padding

    @Test func render_n_padsTo3Digits() throws {
        #expect(try BatchRenameTemplate.render(
            template: "{n:3}", index: 5, totalCount: 5, originalFilename: "foo"
        ) == "005")
        #expect(try BatchRenameTemplate.render(
            template: "{n:3}", index: 1, totalCount: 5, originalFilename: "foo"
        ) == "001")
    }

    @Test func render_n_paddingWiderThanNumber() throws {
        #expect(try BatchRenameTemplate.render(
            template: "{n:5}", index: 3, totalCount: 5, originalFilename: "foo"
        ) == "00003")
    }

    @Test func render_n_overflowNatural() throws {
        // 1000 photos, {n:3} → 前 999 是 3 位, 1000+ 自然 4 位
        #expect(try BatchRenameTemplate.render(
            template: "{n:3}", index: 999, totalCount: 2000, originalFilename: "foo"
        ) == "999")
        #expect(try BatchRenameTemplate.render(
            template: "{n:3}", index: 1000, totalCount: 2000, originalFilename: "foo"
        ) == "1000")
    }

    // MARK: - render {originalName}

    @Test func render_originalName() throws {
        #expect(try BatchRenameTemplate.render(
            template: "{originalName}", index: 1, totalCount: 1, originalFilename: "foo"
        ) == "foo")
        #expect(try BatchRenameTemplate.render(
            template: "{originalName}_edited", index: 1, totalCount: 1, originalFilename: "bar"
        ) == "bar_edited")
    }

    // MARK: - render mixed

    @Test func render_mixedTokens() throws {
        #expect(try BatchRenameTemplate.render(
            template: "IMG_{n:3}_{originalName}", index: 2, totalCount: 5, originalFilename: "bar"
        ) == "IMG_002_bar")
    }

    @Test func render_multipleSequenceTokens() throws {
        // {n}{n} → "11" (index 1 两次都是 "1")
        #expect(try BatchRenameTemplate.render(
            template: "{n}{n}", index: 1, totalCount: 5, originalFilename: "foo"
        ) == "11")
        #expect(try BatchRenameTemplate.render(
            template: "{n}-{n:3}", index: 5, totalCount: 5, originalFilename: "foo"
        ) == "5-005")
    }

    // MARK: - render unknown / edge

    @Test func render_unknownToken_passesThrough() throws {
        // {unknown} 不在 grammar 内 → 透传为字面 "{unknown}"
        #expect(try BatchRenameTemplate.render(
            template: "{unknown}", index: 1, totalCount: 1, originalFilename: "foo"
        ) == "{unknown}")
        #expect(try BatchRenameTemplate.render(
            template: "prefix-{foo}-suffix", index: 1, totalCount: 1, originalFilename: "bar"
        ) == "prefix-{foo}-suffix")
    }

    @Test func render_noTokens_isLiteral() throws {
        #expect(try BatchRenameTemplate.render(
            template: "static_name", index: 1, totalCount: 1, originalFilename: "foo"
        ) == "static_name")
    }

    @Test func render_emptyTemplate_throws() {
        #expect(throws: BatchRenameTemplate.BatchRenameError.emptyTemplate) {
            _ = try BatchRenameTemplate.render(
                template: "", index: 1, totalCount: 1, originalFilename: "foo"
            )
        }
    }

    @Test func render_whitespaceOnly_throws() {
        #expect(throws: BatchRenameTemplate.BatchRenameError.emptyTemplate) {
            _ = try BatchRenameTemplate.render(
                template: "   ", index: 1, totalCount: 1, originalFilename: "foo"
            )
        }
    }

    @Test func render_trimsWhitespace() throws {
        // 模板外层 whitespace 被 trim, 内部 token 周围保留
        #expect(try BatchRenameTemplate.render(
            template: "  photo_{n}  ", index: 1, totalCount: 1, originalFilename: "foo"
        ) == "photo_1")
    }

    // MARK: - uniquify

    @Test func uniquify_noCollision_returnsAsIs() {
        let result = BatchRenameTemplate.uniquify(
            baseName: "photo_1", ext: "jpg",
            existingReserved: [],
            onDiskCheck: { _ in false }
        )
        #expect(result.baseName == "photo_1")
        #expect(result.ext == "jpg")
    }

    @Test func uniquify_withinBatchCollision_appendsCounter() {
        var reserved: Set<String> = ["photo_1.jpg"]
        let result = BatchRenameTemplate.uniquify(
            baseName: "photo_1", ext: "jpg",
            existingReserved: reserved,
            onDiskCheck: { _ in false }
        )
        #expect(result.baseName == "photo_1_1")
        #expect(result.ext == "jpg")
        reserved.insert("\(result.baseName).\(result.ext)")
        let result2 = BatchRenameTemplate.uniquify(
            baseName: "photo_1", ext: "jpg",
            existingReserved: reserved,
            onDiskCheck: { _ in false }
        )
        #expect(result2.baseName == "photo_1_2")
    }

    @Test func uniquify_onDiskCollision_appendsCounter() {
        let result = BatchRenameTemplate.uniquify(
            baseName: "photo_1", ext: "jpg",
            existingReserved: [],
            onDiskCheck: { name in name == "photo_1.jpg" }
        )
        #expect(result.baseName == "photo_1_1")
        #expect(result.ext == "jpg")
    }

    @Test func uniquify_bothLayersCollision() {
        var reserved: Set<String> = ["photo_1.jpg", "photo_1_1.jpg"]
        // on-disk 也有 photo_1_2.jpg
        let result = BatchRenameTemplate.uniquify(
            baseName: "photo_1", ext: "jpg",
            existingReserved: reserved,
            onDiskCheck: { name in name == "photo_1_2.jpg" }
        )
        #expect(result.baseName == "photo_1_3")
    }

    @Test func uniquify_noExtension() {
        let result = BatchRenameTemplate.uniquify(
            baseName: "raw_photo", ext: "",
            existingReserved: [],
            onDiskCheck: { _ in false }
        )
        #expect(result.baseName == "raw_photo")
        #expect(result.ext == "")

        // collision 时也不带点
        let result2 = BatchRenameTemplate.uniquify(
            baseName: "raw_photo", ext: "",
            existingReserved: ["raw_photo"],
            onDiskCheck: { _ in false }
        )
        #expect(result2.baseName == "raw_photo_1")
        #expect(result2.ext == "")
    }

    @Test func uniquify_mixedCaseExtension() {
        // .JPG 跟 .jpg 在 macOS 默认是同一个文件 (case-insensitive HFS+)
        // V1 不做 case-folding 优化 — caller 决定
        let result = BatchRenameTemplate.uniquify(
            baseName: "photo_1", ext: "JPG",
            existingReserved: ["photo_1.jpg"],
            onDiskCheck: { _ in false }
        )
        // reserved 用 caller 提供的 key (ext 区分大小写) — V1 透传
        // 这里 reserved 有 "photo_1.jpg", candidate "photo_1.JPG" 不同
        // V1 行为: 不冲突, 返回原名
        #expect(result.baseName == "photo_1")
        #expect(result.ext == "JPG")
    }
}
