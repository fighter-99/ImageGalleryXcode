//
//  BatchRenameTemplate.swift
//  ImageGallery
//
//  P4.2 批量重命名 — 模板 parser + 冲突去重
//
//  设计:
//  - 纯函数, 无 SwiftUI / SwiftData 依赖 → 独立可测
//  - 单个 NSRegularExpression 单 pass 解析, O(n) 性能
//  - 模板 token: {n} {n:N} (零填充) {originalName}
//  - 未知 token (如 {foo}) 透传, 不抛错
//  - 冲突去重: within-batch (reserved set) + on-disk (closure probe) 双层
//  - 冲突时追加 _1 _2 _3 ... (Photos.app 范式)
//
//  不带进 V1 (留 V4.x):
//  - {date} {exifDate} {year} {month} {day} {camera} {lens} {iso} 等 Date/EXIF token
//  - 文件名非法字符 sanitize (/ : 等) — V1 透传, 让 FileManager 失败报 toast
//  - Case-only rename (case-insensitive FS) 优化
//

import Foundation

enum BatchRenameTemplate {
    // MARK: - Error

    enum BatchRenameError: Error, Equatable {
        case emptyTemplate
        // V6.58 (audit P1.4): 9999 个 _N 后缀还不 unique → caller 弹 toast 而非返回 unchecked name
        //   之前 _10000 fallback 没验证 onDisk, 极端 case (例如已有 9999 个 _1.._9999 文件)
        //   会返回撞盘名字, 后续 FileManager.moveItem 静默覆盖
        case tooManyCollisions
    }

    // MARK: - Render

    /// 渲染模板, 替换 token, 返回新 basename (无扩展名)
    /// - Parameters:
    ///   - template: 用户模板字符串
    ///   - index: 1-based 序列号
    ///   - totalCount: 总照片数 (留 V4.x 给 {total} token 用, V1 不用)
    ///   - originalFilename: 原始 basename (无扩展名, 由 caller pre-strip)
    /// - Throws: `BatchRenameError.emptyTemplate` 当 trim 后为空
    static func render(
        template: String,
        index: Int,
        totalCount: Int,
        originalFilename: String
    ) throws -> String {
        let trimmed = template.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw BatchRenameError.emptyTemplate }

        let nsTemplate = trimmed as NSString
        let matches = tokenRegex.matches(
            in: trimmed,
            range: NSRange(location: 0, length: nsTemplate.length)
        )

        var result = ""
        var cursor = trimmed.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: trimmed) else { continue }
            // 匹配前的字面文本
            result += trimmed[cursor..<matchRange.lowerBound]
            cursor = matchRange.upperBound

            // Capture group 1: token 名 ("n" / "originalName")
            // Capture group 2: padding 宽度 (only for "n")
            let tokenName: String
            if match.range(at: 1).location != NSNotFound {
                tokenName = nsTemplate.substring(with: match.range(at: 1))
            } else {
                tokenName = ""
            }

            switch tokenName {
            case "n":
                // Capture group 2: 零填充宽度 (optional)
                let width: Int
                if match.range(at: 2).location != NSNotFound {
                    width = Int(nsTemplate.substring(with: match.range(at: 2))) ?? 0
                } else {
                    width = 0
                }
                result += padded(index, width: width)
            case "originalName":
                result += originalFilename
            default:
                // 未知 sub-token (regex 应已限定 n/originalName, 但兜底透传整段)
                result += nsTemplate.substring(with: match.range)
            }
        }

        // 尾部
        result += trimmed[cursor..<trimmed.endIndex]
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Uniquify

    /// 解决冲突, 追加 _1 _2 ... 直到 unique
    /// - Parameters:
    ///   - baseName: 原始 basename (无扩展名)
    ///   - ext: 扩展名 (可空)
    ///   - existingReserved: 已被本批其他 photo 占据的 finalName 集合 (含扩展名)
    ///   - onDiskCheck: 给定 fullName (含扩展名) 返回磁盘上是否已存在
    /// - Returns: (最终 baseName, 最终 ext)
    /// - Throws: `BatchRenameError.tooManyCollisions` 当 9999 个 _N 后缀都不 unique 时
    ///   V6.58 (audit P1.4): 之前 fallback 返回 `_10000` 未验证 onDisk, 极端 case 静默覆盖
    ///   现在 throw 让 caller (BatchRenameSheet) 弹 toast 通知用户
    static func uniquify(
        baseName: String,
        ext: String,
        existingReserved: Set<String>,
        onDiskCheck: (String) -> Bool
    ) throws -> (baseName: String, ext: String) {
        let fullName = composeName(baseName: baseName, ext: ext)
        if !existingReserved.contains(fullName) && !onDiskCheck(fullName) {
            return (baseName, ext)
        }

        var counter = 1
        // 安全上限: 9999, 实际不会到
        while counter < 10_000 {
            let candidateBase = "\(baseName)_\(counter)"
            let candidateFull = composeName(baseName: candidateBase, ext: ext)
            if !existingReserved.contains(candidateFull) && !onDiskCheck(candidateFull) {
                return (candidateBase, ext)
            }
            counter += 1
        }
        // V6.58: 抛 .tooManyCollisions 而非 fallback 返回 unchecked name
        //   - 极端 adversarial state (existingReserved 已有 _1.._9999) 触发
        //   - 之前 fallback _10000 未验证 onDisk → 静默覆盖风险
        throw BatchRenameError.tooManyCollisions
    }

    // MARK: - Helpers

    private static func composeName(baseName: String, ext: String) -> String {
        ext.isEmpty ? baseName : "\(baseName).\(ext)"
    }

    private static func padded(_ n: Int, width: Int) -> String {
        if width <= 0 { return String(n) }
        let s = String(n)
        if s.count >= width { return s }
        return String(repeating: "0", count: width - s.count) + s
    }

    // Token regex: {n} | {n:N} | {originalName}
    //   capture 1: token name (n / originalName) — 同一 group
    //   capture 2: optional padding width digits
    //   未知 token (如 {foo}) 不匹配 → 透传为字面
    private static let tokenRegex: NSRegularExpression = {
        // pattern: \{ (n|originalName) (?::(\d+))? \}
        //   group 1 永远是 token name (n / originalName)
        //   group 2 是可选 padding (只有 n:N 才有)
        return try! NSRegularExpression(pattern: #"\{(n|originalName)(?::(\d+))?\}"#)
    }()
}
