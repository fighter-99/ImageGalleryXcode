//
//  DoubleClickAction.swift
//  ImageGallery
//
//  V6.39.0 (Settings Refactor): 双击照片行为选项
//    .immersive: 现有行为 (双击进 ImmersivePhotoView 全屏查看)
//    .quickLook: macOS Photos 真版 (双击进系统 Quick Look panel)
//
//  默认 .immersive — 跟 V6.39.0 之前行为完全兼容
//

import Foundation

enum DoubleClickAction: String, CaseIterable, Identifiable, Hashable {
    case immersive
    case quickLook

    var id: String { rawValue }

    static let defaultValue: DoubleClickAction = .immersive

    var displayName: String {
        switch self {
        case .immersive: return Copy.settingsDoubleClickImmersiveLabel
        case .quickLook: return Copy.settingsDoubleClickQuickLookLabel
        }
    }

    var icon: String {
        switch self {
        case .immersive: return "rectangle.expand.vertical"
        case .quickLook: return "eye"
        }
    }
}
