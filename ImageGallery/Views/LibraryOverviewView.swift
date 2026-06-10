//
//  LibraryOverviewView.swift
//  ImageGallery
//
//  V4.1.0 k NEW: 详情面板"图库概览"——无选中时显示有用内容（替代空白占位）
//
//  设计动机：
//  - 详情面板永远显示（V4.1.0 D 用户要求），但"选择一张图片"空状态是浪费 320pt
//  - 改方案 B：空状态显示"图库概览"——让用户随时看到图库状态
//  - Photos.app / Music.app 都有类似"library 概览"模式
//
//  内容结构：
//  1. 顶部：图库标题 + 统计（count + size）
//  2. 最近导入：3 张最新导入的缩略图
//  3. 文件夹 top 3：按照片数排序
//  4. 底部：导入按钮（primary action）
//
//  交互：
//  - 点击最近缩略图 → 选中该照片
//  - 点击文件夹行 → 切换侧栏 section
//  - 点击导入按钮 → 触发导入
//

import SwiftUI

struct LibraryOverviewView: View {
    let allPhotos: [Photo]
    let folders: [Folder]
    let totalCount: Int
    let totalSize: Int64
    let onSelectPhoto: (Photo) -> Void
    let onSelectFolder: (Folder) -> Void
    let onImport: () -> Void

    /// V4.1.0 k: 最近 3 张导入（按 importedAt 降序）
    private var recentPhotos: [Photo] {
        Array(
            allPhotos
                .filter { !$0.isInTrash }
                .sorted { $0.importedAt > $1.importedAt }
                .prefix(3)
        )
    }

    /// V4.1.0 k: 最大的 3 个文件夹（按照片数排序）
    private var topFolders: [Folder] {
        Array(
            folders
                .sorted { lhs, rhs in
                    let lc = lhs.photos.filter { !$0.isInTrash }.count
                    let rc = rhs.photos.filter { !$0.isInTrash }.count
                    return lc > rc
                }
                .prefix(3)
        )
    }

    /// V4.1.0 k: 格式化总大小
    private var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection
                Divider()
                recentSection
                if !topFolders.isEmpty {
                    Divider()
                    foldersSection
                }
                Divider()
                importButton
            }
            .padding(Spacing.lg)
        }
    }

    /// V4.1.0 k: 顶部标题 + 统计
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("图库")
                    .font(Typography.title)
            }
            Text("\(totalCount) 张照片 · \(totalSizeFormatted)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// V4.1.0 k: 最近导入（3 张缩略图）
    @ViewBuilder
    private var recentSection: some View {
        if !recentPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(icon: "clock.arrow.circlepath", title: "最近导入")
                HStack(spacing: 8) {
                    ForEach(recentPhotos) { photo in
                        recentThumbnailButton(photo: photo)
                    }
                }
            }
        }
    }

    /// V4.1.0 k: 单个最近导入缩略图（点击 → 选中）
    private func recentThumbnailButton(photo: Photo) -> some View {
        Button {
            onSelectPhoto(photo)
        } label: {
            Group {
                if let nsImage = ImageLoader.loadImage(at: photo.fileURL, maxPixelSize: 200) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Palette.cellEmpty)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(photo.filename)
    }

    /// V4.1.0 k: 文件夹 top 3
    @ViewBuilder
    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "folder", title: "文件夹")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(topFolders) { folder in
                    folderRowButton(folder: folder)
                }
            }
        }
    }

    /// V4.1.0 k: 单个文件夹行（点击 → 切换侧栏 section）
    private func folderRowButton(folder: Folder) -> some View {
        let count = folder.photos.filter { !$0.isInTrash }.count
        return Button {
            onSelectFolder(folder)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: folder.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(folder.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    /// V4.1.0 k: 底部导入按钮
    private var importButton: some View {
        Button {
            onImport()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                Text("导入照片")
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
        .help("从 Finder 拖入图片或点击导入 (⌘O)")
    }

    /// V4.1.0 k: 段标题（icon + small caps）
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }
}
