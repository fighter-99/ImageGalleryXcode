//
//  DragPayload.swift
//  ImageGallery
//
//  V3.6.29：把 V3.6.27 的 .onDrag NSItemProvider 构造抽成可测试的纯函数 seam。
//  V3.6.31：DORMANT——撤销 refactor 回 V3.6.27 inline .onDrag 实现
//
//  ⚠️ dormant 模块原因：
//  V3.6.29 refactor 后用户在 macOS 26.5 GUI session 下报告 drag 全坏（4 种都坏）。
//  V3.6.31 把所有调用方（PhotoGridView / ViewMode）回滚到 V3.6.27 inline 实现，
//  DragPayload 结构 / makeNSItemProvider 不再被任何生产代码调用。
//  推测根因：extension 中的 instance method 调用时机在某些边缘场景下，
//  SwiftData @Model 的 capture 顺序导致 NSItemProvider 注册时序异常。
//  DragPayloadTests 5 个仍 pass（只测结构字段，不测 NSItemProvider 实际行为）。
//
//  ─── 设计要点（保留供未来参考）───
//  - 纯数据结构：uuidData / fileURL / suggestedName 三个字段，Equatable 可单测
//  - 关键不变量（从 V3.6.27 抽出来，必须保持）：
//    1. 提前捕获所有 photo 字段到 let（SwiftData @Model deferred 访问安全）
//    2. NSItemProvider.registerFileRepresentation 第二个参数 (url, isInPlace: false, error)：
//       isInPlace: false 让系统读完整文件给 drop target，不走 in-place 模式
//       （V3.5.20 修复：openInPlace 模式会崩）
//  - makeNSItemProvider() 在 extension 里（不污染 Equatable）
//

import Foundation
import AppKit

/// V3.6.29：拖动出去一个 photo 时，NSItemProvider 携带的 payload。
///
/// 用途：
/// - `uuidData`：拖到侧栏文件夹 / 回收站时，SidebarView 的 .onDrop 接收 UUID 决定移动到哪个文件夹
/// - `fileURL`：拖到 Finder / 其他 app 时，把原图拷贝出去
/// - `suggestedName`：Finder drop 时显示的文件名（去掉 UUID 前缀）
///
/// Equatable：用于单元测试——验证 build() 抽出的字段和 photo 一致。
struct DragPayload: Equatable {
    let uuidData: Data
    let fileURL: URL
    let suggestedName: String

    /// V3.6.29: 抽自 PhotoGridView.swift:629-669 (V3.6.27)
    /// 行为完全等价——只是把 inline closure 变成了 static 纯函数。
    /// 调用方不再需要手写 registerDataRepresentation / registerFileRepresentation 那一坨。
    static func build(for photo: Photo) -> DragPayload {
        // uuidString.data 用 utf8 是稳定的——侧栏 drop 时按 utf8 解码回 UUID
        let uuidData = photo.id.uuidString.data(using: .utf8) ?? Data()
        return DragPayload(
            uuidData: uuidData,
            fileURL: photo.fileURL,
            suggestedName: photo.filename
        )
    }
}

// MARK: - NSItemProvider 构造

extension DragPayload {
    /// V3.6.29: 把 payload 包成 NSItemProvider 交给 SwiftUI 的 .onDrag
    ///
    /// NSItemProvider 是 NSObject，不能 Equatable——所以 makeNSItemProvider() 不在 struct 本体里。
    ///
    /// 关键不变量（来自 V3.5.19 / V3.5.20 / V3.6.27 三个 bug fix）：
    /// 1. 提前 capture uuidData / fileURL / suggestedName 到 let 再传进 closure
    ///    （SwiftData @Model 在 closure 里 deferred 访问会崩——V3.5.19 修）
    /// 2. registerFileRepresentation 第二参数 isInPlace: false
    ///    （V3.5.20 删了 registerFileRepresentation，V3.6.27 重新加用 isInPlace: false 避开 openInPlace 模式崩溃）
    /// 3. registerDataRepresentation 替代 registerObject
    ///    （V3.5.19 修：registerObject 提供对象，loadDataRepresentation 要数据，两者不兼容抛 NSException）
    func makeNSItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        // 提前 capture 到 let——避免 closure 捕获 self
        let uuidData = self.uuidData
        let photoFileURL = self.fileURL
        let suggestedName = self.suggestedName

        // 1. UUID 数据（Sidebar 文件夹接收 → 移动到文件夹）
        provider.registerDataRepresentation(
            forTypeIdentifier: "public.text",
            visibility: .all
        ) { completion in
            completion(uuidData, nil)
            return Progress()
        }

        // 2. 原图文件 URL（拖到 Finder / 其他 app 时拷贝原图）
        // isInPlace: false = 系统读完整文件传给 drop target（不走 in-place 模式）
        provider.registerFileRepresentation(
            forTypeIdentifier: "public.file-url",
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(photoFileURL, false, nil)  // (url, isInPlace: false, error)
            return nil  // SwiftData @Model 没用 Progress
        }

        // 改默认文件名（去掉 UUID 前缀，让 Finder 显示真实文件名）
        provider.suggestedName = suggestedName

        return provider
    }
}
