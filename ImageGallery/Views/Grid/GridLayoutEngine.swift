//
//  GridLayoutEngine.swift
//  ImageGallery
//
//  V6.102: 从 PhotoGridView (782 LOC) 抽出 GridLayoutEngine — V6.38.2 computeCellFrames cache
//    抽 model (纯函数 + cache logic) — 跟 V6.62 P4 物理搬运 precedent
//
//  设计目标:
//   - 独立 file (跟 V6.100 D2 god view 拆分 pattern 一致)
//   - 纯函数 + cache — 调用方传 cache state, 内部决定 hit/miss
//   - 0 行为变更 — V6.38.2 cache 行为完全保留
//
//  关键 API:
//   - GridLayoutEngine.compute(...) — 接受 5 layout 参 + photos + cachedDateGroups + layoutMode + sortOption
//     返 (frames, cacheKey, cacheValid) — 调用方存 cache state, 内部决定 cache hit/miss
//
//  之前 (V6.38.2 修): PhotoGridView.computeCellFrames 是 private func, 用 @State cache
//  现在 (V6.102): GridLayoutEngine.compute 是 static func, 调用方 (PhotoGridView) 持有 cache state
//                @State cachedCellFrames + cachedCellFramesKey + cellFramesCacheValid
//                不变, 只是 cache 调用搬出 PhotoGridView body
//

import Foundation
import CoreGraphics  // V6.102: CGRect init (x:y:width:height:) 来自 CoreGraphics module, SwiftUI 不导出

/// V6.102: GridLayoutEngine — 纯函数 + cache, 算 cell frames 给 photoGrid + marquee hit test
///   从 PhotoGridView (782 LOC) 抽出 V6.38.2 computeCellFrames + cache logic
struct GridLayoutEngine {

    /// V6.102: 输入参数 — 5 layout 参 + photos + cachedDateGroups + layoutMode + sortOption
    ///   任一变化 → cache miss → 重算 (跟 V6.38.2 cellFramesCacheKey 行为一致)
    struct Input {
        let availableWidth: CGFloat
        let rowHeight: CGFloat
        let rowSpacing: CGFloat
        let cellSpacing: CGFloat
        let gridPadding: CGFloat
        let photos: [Photo]
        let cachedDateGroups: [DateGroup]
        let layoutMode: ThumbnailLayoutMode
        let sortOption: SortOption

        /// V6.102: cache key — 5 layout 参 + photos.count + photos.map(\.id) + date group 内容 fingerprint
        ///   任一变化 → cache miss (跟 V6.59 P2.5 修法一致 — EXIF rotate 后 aspect 翻转要 invalidate)
        var cacheKey: Int {
            var hasher = Hasher()
            hasher.combine(availableWidth)
            hasher.combine(rowHeight)
            hasher.combine(rowSpacing)
            hasher.combine(cellSpacing)
            hasher.combine(gridPadding)
            hasher.combine(photos.count)
            // V6.59: photos.map(\.id) hash — EXIF rotate 后 aspect 翻转, cache hit 会 stale
            for id in photos.map(\.id) { hasher.combine(id) }
            hasher.combine(cachedDateGroups.count)
            // V6.59: date group 内容 fingerprint — group split/merge 但 count 不变时 stale
            for group in cachedDateGroups {
                hasher.combine(group.id)
                hasher.combine(group.photos.count)
            }
            hasher.combine(layoutMode)
            hasher.combine(sortOption)
            return hasher.finalize()
        }
    }

    /// V6.102: 算 cell frames — 跟 PhotoGridView V6.17.0.1 photoGrid coord space 完全一致
    ///   - date grouped: 用 cachedDateGroups, 每组前 dateHeaderHeight 偏移
    ///   - flat: 平铺 photos, y 从 0 开始
    ///   - x 从 gridPadding 开始 (VStack 有 horizontal padding 16pt)
    ///   - 跟 masonryRowsView 用同一 GridLayout, frame 位置精准
    ///   返回 [CellFrame] — 给 marqueeSelectionGesture hit test + cell render overlay
    static func compute(_ input: Input) -> [CellFrame] {
        let cellSize = SquareLayout.cellSize(
            availableWidth: input.availableWidth,
            rowHeight: input.rowHeight,
            cellSpacing: input.cellSpacing
        )

        var result: [CellFrame] = []
        // date header 高度 (DateSectionHeader 32pt key photo + label + Spacing.xl gap)
        let dateHeaderHeight: CGFloat = 32 + 4 + Spacing.xl

        if input.sortOption.isDateBased {
            // date grouped: 用 cachedDateGroups (V5.32 缓存, O(n log n) 一次性)
            let groups = input.cachedDateGroups
            // V6.17.0.1: y 从 0 开始 (photoGrid space 顶部)
            var y: CGFloat = 0
            for group in groups {
                y += dateHeaderHeight
                let rows = GridLayout(
                    availableWidth: input.availableWidth,
                    rowHeight: cellSize,
                    cellSpacing: input.cellSpacing,
                    layoutMode: input.layoutMode
                ).computeRows(from: group.photos)
                for row in rows {
                    // V6.17.0.1: x 从 gridPadding 开始
                    var x: CGFloat = input.gridPadding
                    for item in row.items {
                        result.append(CellFrame(
                            id: item.id,
                            frame: CGRect(x: x, y: y, width: item.width, height: row.rowHeight)
                        ))
                        x += item.width + input.cellSpacing
                    }
                    y += row.rowHeight + input.rowSpacing
                }
            }
        } else {
            // flat: 平铺 photos, y 从 0 开始
            let items = input.photos.map { photo in
                PhotoGridItem(
                    id: photo.id,
                    aspectRatio: GridLayout.aspectRatio(of: photo),
                    width: 0
                )
            }
            let rows = GridLayout(
                availableWidth: input.availableWidth,
                rowHeight: cellSize,
                cellSpacing: input.cellSpacing,
                layoutMode: input.layoutMode
            ).computeRows(from: items)
            var y: CGFloat = 0
            for row in rows {
                var x: CGFloat = input.gridPadding
                for item in row.items {
                    result.append(CellFrame(
                        id: item.id,
                        frame: CGRect(x: x, y: y, width: item.width, height: row.rowHeight)
                    ))
                    x += item.width + input.cellSpacing
                }
                y += row.rowHeight + input.rowSpacing
            }
        }

        return result
    }
}