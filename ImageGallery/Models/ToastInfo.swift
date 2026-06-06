//
//  ToastInfo.swift
//  ImageGallery
//
//  Toast 通知的数据模型。
//  V3.5.17：从 ContentView 的 nested struct 提到 top-level。
//

import Foundation

struct ToastInfo: Equatable {
    let message: String
    let type: ToastView.ToastType
}
