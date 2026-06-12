//
//  BatchSetRatingMath.swift
//  ImageGallery
//
//  V5.13：ContentView.batchSetRating 的批量评分循环 seam。
//  抽到此处是为 Milestone 2A 的 BatchSetRatingMathTests 可不依赖 SwiftData 测。
//
//  注意：`selection.selectedPhotos(in:)` 这层过滤留在 ContentView 直接调
//  SelectionState 方法（SelectionStateTests 已覆盖），不做冗余包装。
//

import Foundation

enum BatchSetRatingMath {
    /// 批量设置评分——对每个 photo 调 apply closure
    ///   抽 closure-based 是为测试能用 stub 替代 Photo 实例（无需 SwiftData in-memory）
    /// - Parameter rating: 要设置的 rating（0 = 清除，1-5 = 设置）
    /// - Parameter count: photos 数量
    /// - Parameter apply: (index, rating) -> Void  对每个 photo 调用一次
    static func applyRating(_ rating: Int, count: Int, apply: (Int, Int) -> Void) {
        for index in 0..<count {
            apply(index, rating)
        }
    }
}
