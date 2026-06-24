//
//  ImageGalleryIntents.swift
//  ImageGallery
//
//  V6.97.2: 4 个 AppIntent — Siri / Spotlight / 快捷指令 app 入口
//
//  设计: URL scheme 模式 (跟 Photos.app Sonoma+ Siri 范式)
//   - 之前 plan: AppIntent 直接 write SwiftData (App Group 共享)
//   - 实际: ad-hoc signing 不支持 App Group container, 改走 URL scheme
//   - Intent perform() 只调 NSWorkspace.openURL("imagegallery://...")
//   - 主 app onOpenURL → handleShortcutsURL → NotificationCenter → ContentView+Lifecycle.onReceive
//   - 走现有 @MainActor GridViewModel operations (走 undo + toast + registerUndo)
//
//  4 个 Intent:
//   1. OpenLastPhotoIntent  → imagegallery://show-last
//   2. SearchPhotosIntent   → imagegallery://search?q=<query>
//   3. CropSelectedPhotoIntent → imagegallery://crop?aspect=<aspectRawValue>
//   4. FavoritePhotoIntent  → imagegallery://favorite
//
//  AppEnum: CropAspect — 6 case Photos Sonoma+ 真版 1:1
//

import AppIntents
import AppKit

// MARK: - Intent 1: OpenLastPhoto

struct OpenLastPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Last Photo"
    static var description = IntentDescription(
        "Open the most recently imported photo",
        categoryName: "Photos",
        searchKeywords: ["last", "recent", "open", "show", "latest"]
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // 调主 app onOpenURL handler (ContentView.onOpenURL)
        let url = URL(string: "imagegallery://show-last")!
        NSWorkspace.shared.open(url)
        return .result()
    }
}

// MARK: - Intent 2: SearchPhotos

struct SearchPhotosIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Photos"
    static var description = IntentDescription(
        "Search photos by filename, tag, or folder",
        categoryName: "Photos",
        searchKeywords: ["search", "find", "filter", "query"]
    )
    static var openAppWhenRun: Bool = true
    static var parameterSummary: some ParameterSummary {
        Summary("Search photos for \(\.$query)")
    }

    @Parameter(title: "Query", description: "Search keyword")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        // URL-encode query, 避免空格 / 中文 / 特殊字符破坏 URL
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "imagegallery://search?q=\(encoded)")!
        NSWorkspace.shared.open(url)
        return .result()
    }
}

// MARK: - Intent 3: CropSelectedPhoto

/// CropAspect 作为 AppEnum — 6 case 跟 V6.97.1 CropAspect enum 完全平行
/// 用 extension 而不是改 CropAspect.swift — 不破坏现有代码
/// V6.97.2: nonisolated 让 conformance 不受 MainActor 限制 (AppEnum 要求 Sendable)
extension CropAspect: @preconcurrency AppEnum {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Aspect Ratio"
    public static let caseDisplayRepresentations: [CropAspect: DisplayRepresentation] = [
        .freeform:   "Freeform",
        .ratio_1_1:  "1:1",
        .ratio_4_3:  "4:3",
        .ratio_16_9: "16:9",
        .ratio_3_2:  "3:2",
        .ratio_2_3:  "2:3"
    ]
}

struct CropSelectedPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Crop Photo"
    static var description = IntentDescription(
        "Crop the currently selected photo to a specific aspect ratio",
        categoryName: "Photos",
        searchKeywords: ["crop", "aspect", "ratio", "resize"]
    )
    static var openAppWhenRun: Bool = true  // 跟主 app selection 状态交互, 需要主 app 在前台
    static var parameterSummary: some ParameterSummary {
        Summary("Crop selected photo to \(\.$aspect)")
    }

    @Parameter(title: "Aspect", default: .ratio_16_9)
    var aspect: CropAspect

    @MainActor
    func perform() async throws -> some IntentResult {
        // aspect.rawValue 是 String (e.g. "ratio_16_9"), URL 透传到主 app
        let url = URL(string: "imagegallery://crop?aspect=\(aspect.rawValue)")!
        NSWorkspace.shared.open(url)
        return .result()
    }
}

// MARK: - Intent 4: FavoritePhoto

struct FavoritePhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Favorite Photo"
    static var description = IntentDescription(
        "Toggle favorite status of the currently selected photo",
        categoryName: "Photos",
        searchKeywords: ["favorite", "star", "like", "love", "bookmark"]
    )
    static var openAppWhenRun: Bool = true  // 跟主 app selection 状态交互, 需要主 app 在前台

    @MainActor
    func perform() async throws -> some IntentResult {
        // Toggle 逻辑: 主 app onOpenURL → batchSetRating(isFavorite ? 0 : 5)
        let url = URL(string: "imagegallery://favorite")!
        NSWorkspace.shared.open(url)
        return .result()
    }
}