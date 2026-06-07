//
//  PhotoSearch.swift
//  ImageGallery
//
//  V3.6.3：照片搜索匹配逻辑。
//  设计：enum + static func，跟 PhotoStats 同样模式（无状态/无依赖 → 易于测试）。
//
//  V3.6.3 修复：之前搜索只匹配 filename/note/tag.name，
//  没匹配 folder.name，导致"搜文件夹名"搜不到该文件夹下的图。
//

import Foundation

/// V3.6.3：照片搜索匹配逻辑。
enum PhotoSearch {

    /// 判断 photo 是否匹配搜索词（大小写不敏感）
    /// - 空 / 纯空白 query 返回 true（不应用 filter，等价于"全部显示"）
    /// - 匹配字段：filename / note / tag.name / folder.name
    static func matches(_ photo: Photo, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if photo.filename.localizedCaseInsensitiveContains(trimmed) { return true }
        if photo.note.localizedCaseInsensitiveContains(trimmed) { return true }
        if let folder = photo.folder, folder.name.localizedCaseInsensitiveContains(trimmed) {
            return true
        }
        if photo.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(trimmed) }) {
            return true
        }
        return false
    }

    /// 在 photos 集合中筛出匹配 query 的子集
    static func filter(_ photos: [Photo], query: String) -> [Photo] {
        photos.filter { matches($0, query: query) }
    }
}
