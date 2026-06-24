import SwiftUI

/// V6.62: SwiftUI 筛选面板 — 替代 AppKit NSPopover 筛选器
struct FilterPanelView: View {
    @Binding var filterState: FilterState
    let folders: [Folder]
    let tags: [Tag]
    let onClose: () -> Void

    private var panelHeight: CGFloat {
        min(CGFloat(60 + folders.count * 26 + tags.count * 26 + 180), 400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            titleBar
            Divider()
            ScrollView(.vertical) {
                // spacing 14 = Spacing.md+2 (filter section 间距, 介于 md 和 lg 之间)
                VStack(alignment: .leading, spacing: Spacing.md + 2) {
                    foldersSection
                    tagsSection
                    shapesSection
                    ratingSection
                }
            }
            .frame(width: 260, height: panelHeight)
        }
        .padding()
        .frame(width: 290)
    }

    private var titleBar: some View {
        HStack {
            Text("筛选").font(.headline)
            Spacer()
            if filterState.isActive {
                Button("清除") { filterState.removeAll() }
                    .buttonStyle(.link).controlSize(.small)
            }
            Button("完成", action: onClose)
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.bottom, 4)
    }

    private var foldersSection: some View {
        Group {
            if !folders.isEmpty {
                sectionHeader("文件夹")
                ForEach(folders) { folder in
                    filterRow(folder.name, isSelected: filterState.folders.contains(folder.id)) { on in
                        if on { filterState.folders.insert(folder.id) }
                        else { filterState.folders.remove(folder.id) }
                    }
                }
                Divider()
            }
        }
    }

    private var tagsSection: some View {
        Group {
            if !tags.isEmpty {
                sectionHeader("标签")
                ForEach(tags) { tag in
                    filterRow(tag.name, isSelected: filterState.tags.contains(tag.id)) { on in
                        if on { filterState.tags.insert(tag.id) }
                        else { filterState.tags.remove(tag.id) }
                    }
                }
                Divider()
            }
        }
    }

    private var shapesSection: some View {
        Group {
            sectionHeader("形状")
            ForEach(PhotoShape.allCases) { shape in
                filterRow(photoShapeName(shape), isSelected: filterState.shapes.contains(shape)) { on in
                    if on { filterState.shapes.insert(shape) }
                    else { filterState.shapes.remove(shape) }
                }
            }
            Divider()
        }
    }

    private var ratingSection: some View {
        Group {
            sectionHeader("最低评分")
            HStack(spacing: Spacing.xs) {
                ForEach(0..<6, id: \.self) { rating in
                    Button {
                        filterState.minRating = filterState.minRating == rating ? 0 : rating
                    } label: {
                        Image(systemName: rating == 0 ? "circle" : rating <= filterState.minRating ? "star.fill" : "star")
                            .foregroundStyle(rating <= filterState.minRating ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func photoShapeName(_ shape: PhotoShape) -> String {
        switch shape {
        case .landscape: return "横向"
        case .portrait: return "竖向"
        case .square: return "方形"
        }
    }

    private func filterRow(_ title: String, isSelected: Bool, onToggle: @escaping (Bool) -> Void) -> some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title).font(.body)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
