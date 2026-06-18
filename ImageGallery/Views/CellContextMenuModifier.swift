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
import UniformTypeIdentifiers  // V6.20.3: UTType for pasteboard UTI detection

struct CellContextMenuModifier: ViewModifier {
    let photo: Photo
    let folders: [Folder]
    let allTags: [Tag]
    let modelContext: ModelContext
    let toggleTag: (Tag, Photo) -> Void
    @Binding var showingDeleteConfirm: Bool
    let onDelete: () -> Void
    // V6.22.1 (P2 #2): rotate closures — ContentView 传 { model.rotateSelected(clockwise: ...) }
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void

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
                // V4.16.0: 复制单张图片到剪贴板（photo.fileURL promise）
                //   V6.20.3 (code audit fix #8): 用 NSPasteboardItem 多 type 替 writeObjects([URL as NSURL])
                //   之前 \`setData(data, forType: .png)\` 错误标 .png 类型 (jpg/heic 不一定是 png)
                //   同步读 file Data 阻塞主线程 (50MB RAW 卡 UI)
                //   修: 只声明 fileURL promise + image UTI, 不读 file bytes
                //   接受方 (Finder/Photoshop/Preview) 自己 lazy load
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let item = NSPasteboardItem()
                item.setString(photo.fileURL.absoluteString, forType: NSPasteboard.PasteboardType.fileURL)
                if let uti = UTType(filenameExtension: photo.fileURL.pathExtension.lowercased()),
                   uti.conforms(to: .image) {
                    item.setString(photo.fileURL.absoluteString, forType: NSPasteboard.PasteboardType(uti.identifier))
                }
                pasteboard.writeObjects([item])
            } label: {
                Label(Copy.copyAction, systemImage: "doc.on.doc")
            }

            Button {
                // V4.16.0: 在 Finder 中显示（NSWorkspace 桥接 macOS Finder）
                NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL])
            } label: {
                Label(Copy.revealInFinder, systemImage: "folder")
            }

            // V6.19.0 (P0 #1): 单图分享 — ShareLink (macOS 13+ SwiftUI 原生)
            //   自动出 AirDrop / Messages / Mail / Save / Add to Photos 等 services
            //   preview 用 Image(systemName: "photo") 占位 (SharePreview 必须有 icon,
            //   加载真实 thumbnail 在 menu 构造时阻塞主线程)
            ShareLink(
                item: photo.fileURL,
                preview: SharePreview(
                    photo.filename,
                    image: Image(systemName: "photo")
                )
            ) {
                Label("分享", systemImage: "square.and.arrow.up")
            }

            // V6.22.1 (P2 #2): 旋转子菜单 — 左旋 / 右旋 90° (Photos.app 范式)
            //   写 EXIF orientation 到原文件 + 失效 ThumbnailCache
            //   单图 + 多选都支持 (onRotateLeft/Right 由 caller 决定 batch 操作)
            Menu {
                Button {
                    onRotateLeft()
                } label: {
                    Label("向左旋转", systemImage: "rotate.left")
                }
                Button {
                    onRotateRight()
                } label: {
                    Label("向右旋转", systemImage: "rotate.right")
                }
            } label: {
                Label("旋转", systemImage: "rotate.right")
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
