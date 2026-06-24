//
//  ImageGalleryShortcuts.swift
//  ImageGallery
//
//  V6.97.2: AppShortcutsProvider — Siri / Spotlight / 快捷指令 app discover 入口
//
//  4 个 AppShortcut:
//   1. OpenLastPhotoIntent — "Hey Siri, open last photo in ImageGallery"
//   2. SearchPhotosIntent — "Hey Siri, search <query> in ImageGallery"
//   3. CropSelectedPhotoIntent — "Hey Siri, crop selected photo to 16:9"
//   4. FavoritePhotoIntent — "Hey Siri, favorite this photo in ImageGallery"
//
//  phrases 用 String literal, Siri 自动本地化 (跟 Apple system app 同 pattern)
//   系统识别 \(.applicationName) → "ImageGallery"
//   其他 phrase 文字用户 Siri 配置界面可改
//

import AppIntents

struct ImageGalleryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Intent 1: Open Last Photo
        AppShortcut(
            intent: OpenLastPhotoIntent(),
            phrases: [
                "Open last photo in \(.applicationName)",
                "Show last photo in \(.applicationName)",
                "Show recent photo in \(.applicationName)"
            ],
            shortTitle: "Open Last Photo",
            systemImageName: "photo.on.rectangle.angled"
        )

        // Intent 2: Search Photos
        // V6.97.2 (revised): phrase 不用 \(\.$query) — Apple AppShortcuts phrase 不支持 query 引用
        //   用户在 Siri 配置界面填 query phrase 模板 (跟 Photos 同 pattern)
        AppShortcut(
            intent: SearchPhotosIntent(),
            phrases: [
                "Search photos in \(.applicationName)",
                "Find photos in \(.applicationName)"
            ],
            shortTitle: "Search Photos",
            systemImageName: "magnifyingglass"
        )

        // Intent 3: Crop Selected Photo
        AppShortcut(
            intent: CropSelectedPhotoIntent(),
            phrases: [
                "Crop selected photo in \(.applicationName)",
                "Crop photo to \(\.$aspect) in \(.applicationName)",
                "Resize selected photo in \(.applicationName)"
            ],
            shortTitle: "Crop Photo",
            systemImageName: "crop"
        )

        // Intent 4: Favorite Photo
        AppShortcut(
            intent: FavoritePhotoIntent(),
            phrases: [
                "Favorite selected photo in \(.applicationName)",
                "Star photo in \(.applicationName)",
                "Mark photo as favorite in \(.applicationName)"
            ],
            shortTitle: "Favorite Photo",
            systemImageName: "star.fill"
        )
    }

    // V6.97.2 (revised): 不用 tintColor — AppShortcutsProvider.tintColor 类型因 SDK 版本而异
    //   Apple 17 SDK 用 Color, 18 SDK 用 ShortcutsTintColor, 26 SDK 又变了 — 跨 SDK 不稳定
    //   跳过 tintColor, 系统默认 tint (跟 macOS Photos 同样)
}