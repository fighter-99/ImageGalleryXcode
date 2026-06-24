//
//  CropAspect.swift
//  ImageGallery
//
//  V6.97.1: Crop / Aspect (P0 #5) — 6 个 Photos.app Sonoma+ 标准 preset
//   Photos 真版 toolbar = 6 preset (Freeform / 1:1 / 4:3 / 16:9 / 3:2 / 2:3)
//   P0 #5 spec 最低 4 个, 我们给 6 个跟 macOS 真版 1:1 对齐
//
//  复用 V6.94.1 Markup pattern:
//   - Codable enum (rawValue String, 跟 markupData 同样的 JSON 持久化)
//   - ratio property 给 CropCanvasView 约束计算
//

import Foundation

enum CropAspect: String, Codable, Equatable, CaseIterable {
    case freeform    // 自由比例 — 不约束
    case ratio_1_1   // 1:1 方形 (Instagram 真版)
    case ratio_4_3   // 4:3 经典相机
    case ratio_16_9  // 16:9 widescreen / video
    case ratio_3_2   // 3:2 35mm 相机 (Photos.app default)
    case ratio_2_3   // 2:3 35mm portrait

    /// 比例值 — 用于裁剪时 width/height 约束计算
    ///   freeform = nil 表示不约束
    var ratio: CGFloat? {
        switch self {
        case .freeform:   return nil
        case .ratio_1_1:  return 1
        case .ratio_4_3:  return 4.0 / 3.0
        case .ratio_16_9: return 16.0 / 9.0
        case .ratio_3_2:  return 3.0 / 2.0
        case .ratio_2_3:  return 2.0 / 3.0
        }
    }

    /// Photos 真版 toolbar 显示文本 (e.g. "Freeform", "1:1", "4:3")
    ///   本地化走 Copy.cropPresetXxx
    var labelKey: String {
        switch self {
        case .freeform:   return "freeform"
        case .ratio_1_1:  return "1:1"
        case .ratio_4_3:  return "4:3"
        case .ratio_16_9: return "16:9"
        case .ratio_3_2:  return "3:2"
        case .ratio_2_3:  return "2:3"
        }
    }
}
