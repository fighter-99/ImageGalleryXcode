import SwiftUI
import SwiftData
import AppKit
#Preview {
    PhotoGridView(
        selection: .constant(SelectionState()),
        isMarqueeActive: .constant(false),
        marqueeRect: .constant(nil),
        folder: nil,
        tag: nil,
        searchText: "",
        filterUnfiled: false,
        filterDuplicates: false,
        filterRecent7Days: false,
        filterLargeFiles: false,
        filterInTrash: false,
        selectedFolderIDs: [],
        selectedTagIDs: [],
        selectedShapes: [],
        filterMinRating: 0,
        retentionDays: 30,
        thumbnailSize: .constant(170),
        layoutMode: .squareFit,  // V6.12.12: .square 砍了, Preview 默认 .squareFit
        sortOption: .importedAtDesc,
        scrollAnchorPhotoID: nil,  // V5.60-6: Preview 不需要 anchor
        onScrollAnchorChange: { _ in },  // V5.61-1: Preview no-op
        onVisiblePhotosChange: { _ in },
        onImport: {},
        onBatchDelete: {},
        onClearMultiSelect: {},
        onDoubleTap: { _ in },
        onClearFilters: {},
        onExportComplete: { _ in },
        onReorder: {},
        // V6.22.1: Preview no-op 旋转
        onRotate: { _, _ in },
        // V6.94.1: Preview no-op 标注
        onMarkup: { },
        // V6.97.1: Preview no-op 裁剪
        onCrop: { }
    )
    .frame(width: SheetMetrics.standardWidth, height: SheetMetrics.standardHeight)
}
