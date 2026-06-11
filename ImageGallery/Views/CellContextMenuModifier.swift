//
//  CellContextMenuModifier.swift
//  ImageGallery
//
//  V3.6.37: cell contextMenu 抽出独立 ViewModifier（V3.6.17/6.23 type-check timeout 教训）
//  V4.39.0: 从 PhotoGridView.swift 拆出独立文件
//    PhotoGridView 1180 → 580 行（V4.10.0 ContentView 拆分模式延续）
//    PBXFileSystemSynchronizedRootGroup 自动同步——无需改 pbxproj
//
//  cell 右键菜单：移动到文件夹 / 管理标签 / 复制 / 在 Finder 中显示 / 收藏 / 删除
//

import SwiftUI
import SwiftData
import AppKit

struct CellContextMenuModifier: ViewModifier {
    let photo: Photo
    let folders: [Folder]
    let allTags: [Tag]
    let modelContext: ModelContext
    let toggleTag: (Tag, Photo) -> Void
    @Binding var showingDeleteConfirm: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Menu {
                Button {
                    photo.folder = nil
                    modelContext.saveWithLog()
                } label: {
                    Label("移出文件夹", systemImage: "tray")
                }
                if !folders.isEmpty {
                    Divider()
                }
                ForEach(folders) { folder in
                    Button {
                        photo.folder = folder
                        modelContext.saveWithLog()
                    } label: {
                        if photo.folder?.id == folder.id {
                            Label(folder.name, systemImage: "checkmark")
                        } else {
                            Text(folder.name)
                        }
                    }
                }
            } label: {
                Label("移动到文件夹", systemImage: "folder")
            }

            Menu {
                ForEach(allTags) { tag in
                    Button {
                        toggleTag(tag, photo)
                    } label: {
                        if photo.tags.contains(where: { $0.id == tag.id }) {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
            } label: {
                Label("管理标签", systemImage: "tag")
            }

            Divider()

            // V4.16.0: 复制 + 在 Finder 中显示（macOS Photos 标配）
            //   之前 cell 缺这 2 个 macOS 标准 actions，用户多选到 detail panel
            //   才能找到这些——直接右键 cell 更快
            Button {
                // V4.16.0: 复制单张图片到剪贴板（photo.fileURL -> Data -> NSPasteboard）
                //   ContentView 已有 batch 路径 copyToPasteboard()，单张走相同 NSPasteboard API
                if let data = try? Data(contentsOf: photo.fileURL) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setData(data, forType: .png)
                    // 实际图片类型由 extension 决定——jpg/heic 不一定 .png
                    // V4.16.0: 简化只设 fileURL promise，让接受方读原文件
                    pasteboard.writeObjects([photo.fileURL as NSURL])
                }
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button {
                // V4.16.0: 在 Finder 中显示（NSWorkspace 桥接 macOS Finder）
                NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL])
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }

            Divider()

            Button {
                photo.isFavorite.toggle()
                modelContext.saveWithLog()
            } label: {
                Label(
                    photo.isFavorite ? "取消收藏" : "收藏",
                    systemImage: photo.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
