//
//  SmartFolderCreateSheet.swift
//  ImageGallery
//
//  P4.1.1 智能文件夹创建 sheet — Photos.app "Save as Smart Album" 范式
//
//  UX:
//  - Title: "新建智能文件夹"
//  - Name TextField (placeholder + 32pt SF Symbol icon preview)
//  - 图标 LazyVGrid 5 列 × 13 SF Symbol (single-select 高亮)
//  - 筛选条件 preview (来自 sheet 打开时快照的 model.filterState)
//  - Save / Cancel
//
//  V1 简化: 不在 sheet 内独立编辑 filter (edit UI 留 V4.x)
//    拿当前 model.filterState 作 snapshot, sheet 打开后改 toolbar filter 不影响
//
//

import SwiftUI

struct SmartFolderCreateSheet: View {
    let initialFilter: FilterState
    /// closure: caller 负责 create + dismiss
    let onSave: (String, String, FilterState) -> Void  // name, iconName (raw SF Symbol), filterState

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedIcon: SmartFolderIcon = .star

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 5
    )

    // MARK: - 派生

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !trimmed.isEmpty
    }

    /// 4 维 filter 摘要 — 跟 P4.2 live preview 同风格
    private var filterSummaryParts: [String] {
        let f = initialFilter
        // V6.37.4: 走 Copy — printf %lld 而非 Swift 字符串插值, zh-Hant 可重排语序
        return [
            f.folders.isEmpty ? nil : Copy.smartFolderFolderCount(f.folders.count),
            f.tags.isEmpty ? nil : Copy.smartFolderTagCount(f.tags.count),
            f.shapes.isEmpty ? nil : Copy.smartFolderShapeCount(f.shapes.count),
            f.minRating > 0 ? Copy.smartFolderMinRating(f.minRating) : nil
        ].compactMap { $0 }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: icon 预览 + Name
            HStack(spacing: 12) {
                Image(systemName: selectedIcon.rawValue)
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                TextField(Copy.smartFolderNamePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveIfValid() }
            }

            // 图标选择
            VStack(alignment: .leading, spacing: 6) {
                Text(Copy.smartFolderIconSection)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SmartFolderIcon.allCases) { icon in
                        IconCell(icon: icon, isSelected: icon == selectedIcon)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIcon = icon
                            }
                    }
                }
            }

            Divider()

            // 筛选条件 preview
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.smartFolderFilterSection)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if initialFilter.isActive {
                    Text(filterSummaryParts.joined(separator: " · "))
                        .font(.callout)
                } else {
                    Text(Copy.smartFolderEmptyFilterHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 操作栏
            HStack {
                Button(Copy.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(Copy.create) { saveIfValid() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }

    private func saveIfValid() {
        guard isValid else { return }
        onSave(trimmed, selectedIcon.rawValue, initialFilter)
        dismiss()
    }
}

// MARK: - Icon cell (private subview)

private struct IconCell: View {
    let icon: SmartFolderIcon
    let isSelected: Bool

    var body: some View {
        Image(systemName: icon.rawValue)
            .font(.system(size: 20))
            .frame(width: 40, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .help(icon.displayName)
            .accessibilityLabel(icon.displayName)
    }
}
