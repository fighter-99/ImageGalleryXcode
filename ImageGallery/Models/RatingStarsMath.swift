//
//  RatingStarsMath.swift
//  ImageGallery
//
//  V5.13：RatingStarsView 的纯函数 seam——displayedRating + click-toggle 规则。
//  抽到此处是为 Milestone 2A 的 RatingStarsMathTests 可不依赖 SwiftUI 测。
//

import Foundation

enum RatingStarsMath {
    /// 显示的填充范围——max(rating, hoverRating)
    /// hover 时 hoverRating > rating，星星被"推"过去，预览效果
    static func displayedRating(current: Int, hover: Int) -> Int {
        max(current, hover)
    }

    /// 点 N 颗星：已是 N 则清 0，否则设为 N（V5.8 行为不变）
    /// - Parameter click: 用户点击的星数（1-5）
    /// - Parameter current: 当前 rating（0-5）
    /// - Returns: 新 rating（0 = 清除，1-5 = 设置）
    static func nextRating(after click: Int, current: Int) -> Int {
        click == current ? 0 : click
    }
}
