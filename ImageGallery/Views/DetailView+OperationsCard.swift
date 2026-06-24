//
//  DetailView+OperationsCard.swift
//  ImageGallery
//
//  V6.97 P3-4: DetailView 拆分 — 操作卡片 + 评分条 + rename/delete/createTag 流程
//    之前 5️⃣ 操作卡 + ratingPickerRow + removeTag + renamePhoto + createAndAddTag
//    + deletePhoto 都在 DetailView.swift
//    拆出: operationsCard, ratingPickerRow, removeTag, renamePhoto, createAndAddTag, deletePhoto
//

import SwiftUI
import SwiftData
import AppKit

extension DetailView {
    /// 5️⃣ 操作卡
    /// V5.8: 加 5 颗 ⭐ 点选条——单张照片视图直接评分
    ///   - 取代 V5.7 砍掉的"收藏"按钮——收藏 = 评分 ≥ 5
    ///   - 点击第 N 颗 → photo.rating = N；再点同一颗 → photo.rating = 0
    ///   - 视觉：实心 N 颗（systemYellow）+ 空心 (5-N) 颗（secondaryLabelColor）
    ///   - 比右键菜单 → 评分 → 1 星 快捷 3 步
    /// V5.7: 砍"收藏"和"在 Finder 中显示"两个按钮
    ///   只保留"删除"——最关键的危险操作必须显眼
    var operationsCard: some View {
        detailCard {
            VStack(spacing: Spacing.md) {
                // V5.8: 5 颗 ⭐ 点选条
                ratingPickerRow
                // V5.7: 3 按钮 → 1 按钮（删除）——单按钮 fullWidth 占满
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(Copy.delete)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// V5.11 升级: 5 颗 ⭐ 点选条 macOS Photos 风格——hover 预览 + 视觉分层
    ///   - 实心 N 颗 (systemYellow) + 空心 (5-N) 颗 (Color.secondary.opacity(0.5))
    ///   - hover 预览: 鼠标悬停 N 颗 → 这 N 颗也显示填充（预览将要设置的评分）
    ///   - 整体高度增加 6pt: padding(.vertical, 4) → padding(.vertical, 8)——更舒展
    ///   - star 字号 22pt medium weight——比 .title2 略重，与按钮视觉一致
    ///   - label 字号 .callout → .caption2——更 subtle
    ///   仿 Photos.app 评分 popover 视觉锤
    var ratingPickerRow: some View {
        HStack(spacing: Spacing.sm) {
            RatingStarsView(
                rating: photo.rating,
                onSet: { newRating in
                    photo.rating = newRating
                    modelContext.saveWithLog()
                }
            )
            Spacer()
            Text(photo.rating > 0 ? Copy.ratingStars(photo.rating) : Copy.detailNoRating)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }


    // ─── 移除标签（V3.5 Phase 2：支持撤销）───
    func removeTag(_ tag: Tag) {
        undoManager?.registerAction(
            description: Copy.undoRemoveTag(tag.name)
        ) {
            photo.tags.removeAll { $0.id == tag.id }
            modelContext.saveWithLog()
        } undo: {
            photo.tags.append(tag)
            modelContext.saveWithLog()
        }
    }

    // ─── 重命名（V3.5 Phase 2：支持撤销 + 同步文件磁盘）───
    // V6.58 (audit P1.3): 用 renameTarget (alert-open 时 capture) 而非当前 photo
    //   修复 ← → 切换 photo 期间 alert 还在 → 改错照片数据丢失 bug
    func renamePhoto() {
        // V6.58: renameTarget 可能为 nil (用户 alert 中 dismiss 但仍点 confirm 边角案例)
        //   防御性 fallback 用 photo (虽然逻辑上不该发生)
        let target = renameTarget ?? photo
        let trimmed = newFileName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != target.filename else { return }

        // 快照：旧文件名 + 旧 URL (基于 renameTarget, 不是 photo)
        let oldFilename = target.filename
        let oldURL = target.fileURL
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(trimmed)

        // 避免重名：若新 URL 已存在，放弃
        if FileManager.default.fileExists(atPath: newURL.path) && newURL != oldURL {
            return
        }

        undoManager?.registerAction(
            description: Copy.undoRename(trimmed)
        ) {
            // V6.08: 文件 rename 失败不能静默——之前 try? + 写 SwiftData → 孤儿文件
            //   失败: 不更新 target.filename/fileURL, 弹 toast 通知用户
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                target.filename = trimmed
                target.fileURL = newURL
                modelContext.saveWithLog()
            } catch {
                onError(Copy.renameFailed(trimmed))
            }
        } undo: {
            // 撤销：磁盘重命名回 + SwiftData 回滚
            do {
                try FileManager.default.moveItem(at: newURL, to: oldURL)
                target.filename = oldFilename
                target.fileURL = oldURL
                modelContext.saveWithLog()
            } catch {
                // 撤销失败: 文件状态跟 SwiftData 不一致——只能提示用户
                onError(Copy.renameFailed(oldFilename))
            }
        }
    }

    // ─── 创建并添加标签（V3.5 Phase 2：支持撤销）───
    func createAndAddTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // 先确定要添加的 tag（已存在的 or 新建的）
        let tagToAdd: Tag
        if let existing = allTags.first(where: { $0.name == trimmed }) {
            if photo.tags.contains(where: { $0.id == existing.id }) {
                return  // 已经加过了
            }
            tagToAdd = existing
        } else {
            let randomColor = TagColors.presets.randomElement() ?? "#5B8FF9"
            let newTag = Tag(name: trimmed, colorHex: randomColor)
            modelContext.insert(newTag)
            tagToAdd = newTag
        }

        // V3.5 Phase 2：注册撤销
        undoManager?.registerAction(
            description: Copy.undoAddTag(tagToAdd.name)
        ) {
            photo.tags.append(tagToAdd)
            modelContext.saveWithLog()
        } undo: {
            photo.tags.removeAll { $0.id == tagToAdd.id }
            modelContext.saveWithLog()
        }
    }

    // ─── 删除图片（V3.6：走 RecycleBinService.recycle，移到回收站）───
    func deletePhoto() {
        RecycleBinService(storage: .shared, modelContext: modelContext).recycle(photo)
        onDelete()
    }
}
