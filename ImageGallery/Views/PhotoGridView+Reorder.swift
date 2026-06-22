import Foundation

extension PhotoGridView {
    // MARK: - 拖拽重排数学 (V3.5.D P3: 纯函数, 便于单测)

    /// 计算拖拽重排的最终 source 集合和校正后的 destination。
    static func computeDragReorder(
        photoCount: Int,
        source: IndexSet,
        destination: Int,
        isPhotoSelectedAt: (Int) -> Bool
    ) -> (allSources: IndexSet, adjustedDest: Int) {
        // Step 1: 决定实际要拖的 source 集合
        let allSources: IndexSet
        if source.count == 1, let draggedIndex = source.first, isPhotoSelectedAt(draggedIndex) {
            // 拖动的是某个被选中的项——检查是否还有其他选中项
            let allSelectedIndices = (0..<photoCount).filter { isPhotoSelectedAt($0) }
            if allSelectedIndices.count > 1 {
                allSources = IndexSet(allSelectedIndices)
            } else {
                allSources = source
            }
        } else {
            allSources = source
        }

        // Step 2: 校正 destination (左移 sources 中 < dest 的项数)
        let sourcesBeforeDest = allSources.filter { $0 < destination }.count
        var adjustedDest = destination - sourcesBeforeDest

        // Step 3: Clamp 到合法范围 [0, photoCount - allSources.count]
        let maxDest = max(0, photoCount - allSources.count)
        adjustedDest = min(max(0, adjustedDest), maxDest)

        return (allSources, adjustedDest)
    }
}
