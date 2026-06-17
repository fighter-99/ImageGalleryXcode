//
//  PhotoDragItem.swift
//  ImageGallery
//
//  V5.39.7 NEW: 拖拽 payload——同时支持 Finder 导出 (URL) + in-app 重排 (photoID)
//
//  ProxyRepresentation 妙处:
//  - .draggable(PhotoDragItem) 注册整个 item 为 transferable
//  - 当 drop target 期望 URL (Finder 或 in-app .dropDestination(for: URL.self)):
//    → SwiftUI 自动用 ProxyRepresentation 把 PhotoDragItem 转成 URL
//  - 当 drop target 期望 PhotoDragItem (in-app .dropDestination(for: PhotoDragItem.self)):
//    → SwiftUI 用原始 Transferable, drop 收完整 PhotoDragItem (含 photoID)
//
//  V3.6.33 用 .draggable(URL) 时, in-app drop 收 URL, 反查 photo 才能拿 ID
//  V5.39.7 用 .draggable(PhotoDragItem), in-app drop 直接拿 ID, 省 1 次 modelContext 查询
//
//  Finder 导出行为不变 (V3.6.33 验证 OK)——ProxyRepresentation(exporting: \.fileURL) 保兼容
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// V5.39.7: 拖拽 payload——同时支持 Finder 导出 (URL) + in-app 重排 (photoID)
/// V3.7.2 (P3.1.2): 扩 multi-drag——多选时拖整组
///   - 加 count + fileURLs 字段, 单选时 fileURLs = [fileURL], count = 1
///   - 多选时 fileURLs = selectedURLs, count = selectedIDs.count
///   - preview 用 count 显示 "N 张" 标签
///   - **NSDockTile badge 跳过** (SwiftUI 13+ 缺 onDragStart/End hook, V6.16 polish 跟进)
///   - 多选拖到 Finder 仍走单 fileURL (ProxyRepresentation 只暴露 fileURL)
///     — 完整 multi-file drag 走 NSItemProvider, V6.16 polish
struct PhotoDragItem: Transferable {
    let photoID: UUID           // in-app reorder 用, 拿 ID 查 modelContext
    let fileURL: URL            // ProxyRepresentation 暴露给 Finder
    let count: Int              // V3.7.2: 多选时为整组大小, preview 显示 "N 张"
    let fileURLs: [URL]         // V3.7.2: 多选时为整组 URL, 备未来 NSItemProvider multi-file

    /// 单图构造 (V5.39.7 兼容)
    init(photoID: UUID, fileURL: URL) {
        self.photoID = photoID
        self.fileURL = fileURL
        self.count = 1
        self.fileURLs = [fileURL]
    }

    /// V3.7.2: 多图构造 (多选时拖整组)
    init(photoID: UUID, fileURL: URL, count: Int, fileURLs: [URL]) {
        self.photoID = photoID
        self.fileURL = fileURL
        self.count = count
        self.fileURLs = fileURLs
    }

    /// ProxyRepresentation(exporting: \.fileURL):
    ///   drop target 期望 URL 时 (Finder / .dropDestination(for: URL.self))
    ///   SwiftUI 自动用 fileURL 作 payload
    ///   Finder 接 fileURL → 拷原图 (同 V3.6.33 行为)
    /// in-app .dropDestination(for: PhotoDragItem.self):
    ///   SwiftUI 用原始 Transferable, drop 收 PhotoDragItem 自身
    ///   drop handler 取 photoID 找 photo → 更新 sortOrder
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.fileURL)
    }
}
