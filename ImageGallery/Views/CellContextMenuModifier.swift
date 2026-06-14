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
                    Label(Copy.removeFromFolder, systemImage: "tray")
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
                Label(Copy.moveToFolder, systemImage: "folder")
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
                Label(Copy.manageTags, systemImage: "tag")
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
                Label(Copy.copyAction, systemImage: "doc.on.doc")
            }

            Button {
                // V4.16.0: 在 Finder 中显示（NSWorkspace 桥接 macOS Finder）
                NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL])
            } label: {
                Label(Copy.revealInFinder, systemImage: "folder")
            }

            Divider()

            // V5.7: 砍"收藏"按钮——合并到评分（5 星 = 收藏）
            //   新增"评分"子菜单：1-5 星 + 清除评分
            //   子菜单项：1-4 星用 `star` 空心，5 星用 `star.fill` 实心——视觉与筛选 popover 对齐
            //   当前选中评分行用 checkmark 标记
            Menu {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        photo.rating = n
                        modelContext.saveWithLog()
                    } label: {
                        if photo.rating == n {
                            Label(Copy.ratingStars(n), systemImage: "star.fill")
                        } else {
                            Label(Copy.ratingStars(n), systemImage: n == 5 ? "star.fill" : "star")
                        }
                    }
                }
                Divider()
                Button {
                    photo.rating = 0
                    modelContext.saveWithLog()
                } label: {
                    if photo.rating == 0 {
                        Label(Copy.clearRating, systemImage: "checkmark")
                    } else {
                        Text(Copy.clearRating)
                    }
                }
            } label: {
                Label(Copy.ratingCategory, systemImage: photo.rating > 0 ? "star.fill" : "star")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label(Copy.delete, systemImage: "trash")
            }
        }
    }
}
