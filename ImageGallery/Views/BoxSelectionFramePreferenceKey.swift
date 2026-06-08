//
//  BoxSelectionFramePreferenceKey.swift
//  ImageGallery
//
//  V3.6.28：框选 V2 用的 cell frame 上报通道。
//
//  SwiftUI 标准做法：每个 cell 在自己的 .background(GeometryReader) 里
//  调用 Color.clear.preference(key:path:value:) 上报自己的 frame，
//  父视图用 .onPreferenceChange 一次性收齐。
//
//  reduce 函数：后到的 frame 覆盖旧的（cell layout 变了用最新值）。
//

import SwiftUI

/// V3.6.28：cell frame 上报 preference。
///
/// 约定坐标系：所有 cell 上报的 frame 必须在 `.named("boxSelectSpace")` 坐标系下，
/// 与 `boxSelectionGesture` 用的 DragGesture 一致。命名坐标系由 MainSplitView 设置。
struct BoxSelectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    /// 合并子视图的上报：后到的覆盖旧的（cell layout 变了用最新值）
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
