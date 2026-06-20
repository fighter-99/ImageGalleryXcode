//
//  CellContextMenuModifier.swift
//  ImageGallery
//
//  V3.6.37: cell contextMenu 抽出独立 ViewModifier（V3.6.17/6.23 type-check timeout 教训）
//  V4.39.0: 从 PhotoGridView.swift 拆出独立文件
//    PhotoGridView 1180 → 580 行（V4.10.0 ContentView 拆分模式延续）
//    PBXFileSystemSynchronizedRootGroup 自动同步——无需改 pbxproj
//
//  V6.29.3: 3-tier grouping (视图 / 编辑 / 分享 / 删除)
//    之前: 8 个 flat items + 3 dividers (Move/Tags/Copy/Finder/Share/Rotate/Rating/Delete)
//    现在: 3 submenu groups + 2 standalone (Share + Delete) — 视觉层级更清晰
//
//  分组逻辑 (跟 Photos.app 行为对齐):
//  - 视图 (View): 视觉变换 — 旋转 + 评分 (submenu)
//  - 编辑 (Edit): 数据操作 — 移动到 + 标签 + 复制 + Finder (submenu + items)
//  - 分享 (Share): ShareLink (standalone, macOS pattern)
//  - 删除 (Delete): destructive button (standalone, macOS pattern, role: .destructive 红色)
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
            // MARK: - V6.29.3: 视图组 — 视觉变换 (旋转 + 评分)
            Menu {
                // V6.22.1 (P2 #2): 旋转子菜单 — 左旋 / 右旋 90° (Photos.app 范式)
                Menu {
                    Button {
                        onRotateLeft()
                    } label: {
                        Label(Copy.contextMenuRotateLeft, systemImage: "rotate.left")
                    }
                    Button {
                        onRotateRight()
                    } label: {
                        Label(Copy.contextMenuRotateRight, systemImage: "rotate.right")
                    }
                } label: {
                    Label(Copy.contextMenuRotateSubmenu, systemImage: "rotate.right")
                }

                // V5.7: 砍"收藏"按钮——合并到评分（5 星 = 收藏）
                //   评分子菜单: 1-5 星 + 清除评分
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
            } label: {
                Label(Copy.contextMenuViewSubmenu, systemImage: "eye")
            }

            // MARK: - V6.29.3: 编辑组 — 数据操作 (移动 + 标签 + 复制 + Finder)
            Menu {
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
                Button {
                    // V4.16.0: 复制单张图片到剪贴板（photo.fileURL promise）
                    //   V6.20.3 (code audit fix #8): 用 NSPasteboardItem 多 type 替 writeObjects([URL as NSURL])
                    //   之前 `setData(data, forType: .png)` 错误标 .png 类型 (jpg/heic 不一定是 png)
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
                    NSWorkspace.shared.activateFileViewerSelecting([photo.fileURL])
                } label: {
                    Label(Copy.revealInFinder, systemImage: "folder")
                }
            } label: {
                Label(Copy.contextMenuEdit, systemImage: "square.and.pencil")
            }

            // MARK: - V6.29.3: 分享 (standalone — macOS ShareLink 范式)
            //   ShareLink 不放进 submenu — macOS 习惯: 分享按钮始终是独立 item
            //   (放 submenu 反而让用户多一层点击)
            ShareLink(
                item: photo.fileURL,
                preview: SharePreview(
                    photo.filename,
                    image: Image(systemName: "photo")
                )
            ) {
                Label(Copy.contextMenuShare, systemImage: "square.and.arrow.up")
            }

            Divider()

            // MARK: - V6.29.3: 删除 (standalone — destructive, macOS pattern)
            //   role: .destructive 自动 macOS 红色样式
            //   独立不分组: 误删风险高, 视觉距离其他 op 越远越安全
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label(Copy.delete, systemImage: "trash")
            }
        }
    }
}
