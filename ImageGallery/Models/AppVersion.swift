//
//  AppVersion.swift
//  ImageGallery
//
//  V5.57-1: Bundle 版本访问工具——SettingsView 关于页用
//  之前没人读 Bundle.main.infoDictionary——本工具是 codebase 第一处
//  缺字段 fallback "1.0" / "1"——CI build 时 Info.plist 字段不存在时优雅降级
//
//  pbxproj 已设 MARKETING_VERSION=1.0, CURRENT_PROJECT_VERSION=1
//  (ImageGallery.xcodeproj/project.pbxproj:329, 359)
//

import Foundation

/// V5.57-1: Bundle 版本号只读快照
struct AppVersion: Equatable {
    /// "1.0" 之类 (CFBundleShortVersionString)
    let marketing: String
    /// "1" 之类 (CFBundleVersion)
    let build: String

    /// 当前 app 版本——从 Bundle.main.infoDictionary 读
    /// 缺字段 fallback "1.0" / "1"——CI build 时 Info.plist 字段不存在时优雅降级
    static let current: AppVersion = {
        let info = Bundle.main.infoDictionary
        return AppVersion(
            marketing: info?["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info?["CFBundleVersion"] as? String ?? "1"
        )
    }()

    /// "v1.0 (build 1)" 之类——AboutSettingsView 直接显示
    var displayString: String { "v\(marketing) (build \(build))" }
}
