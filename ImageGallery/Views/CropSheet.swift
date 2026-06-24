//
//  CropSheet.swift
//  ImageGallery
//
//  V6.97.1: Crop / Aspect Sheet (P0 #5)
//
//  复用 V6.94.1 Markup 完整 pattern:
//   - NSView CropCanvasView (替代 PencilKit — macOS 无 PKCanvasView, V6.94.1 教训)
//   - 9 handles gesture model: 4 corner + 4 edge + 1 center (Photos.app Sonoma+ 范式)
//   - 4-段 toolbar: [Presets] | [Reset] | [Rotate] | [Cancel · Apply]
//   - 持久化: Photo.cropRect (JSON-encoded CropRect, normalized 0-1)
//   - undo: ImageGalleryUndoManager.registerUndoOnly + coalesceId="crop" (跟 markup/rotate 模式一致)
//
//  CropRect 是 normalized 0-1 坐标, 跟原图分辨率无关 (rotation-safe)
//

import SwiftUI
import AppKit
import SwiftData

// MARK: - V6.97.1: 自定义 NSView — 9 handles 拖拽裁剪 (macOS 无 PKCanvasView 替代)
class CropCanvasView: NSView {
    /// normalized 0-1 crop rect (相对原图)
    var cropRect: CGRect = .zero
    /// 当前选中的 aspect preset (跟 SwiftUI selectedAspect 同步)
    var aspect: CropAspect = .freeform
    /// 背景原图 (用户能拖拽看裁剪区)
    var backgroundImage: NSImage?
    /// 任意变化时触发 (mouseUp) — 给 SwiftUI 同步用
    var onChange: (() -> Void)?

    private enum DragMode {
        case none
        case cornerNW, cornerNE, cornerSE, cornerSW
        case edgeN, edgeE, edgeS, edgeW
        case center
    }

    private var dragMode: DragMode = .none
    private var dragStartNormalized: NSPoint = .zero
    private var dragStartCropRect: CGRect = .zero

    private var aspectRatio: CGFloat? { aspect.ratio }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Public API (给 SwiftUI 调用)

    /// Photos.app "Reset" 行为 — crop 回到整个图
    func reset() {
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        aspect = .freeform
        needsDisplay = true
        onChange?()
    }

    /// 切换 aspect 时调整 cropRect (保持中心点, 调整 width/height 比例, 不超界)
    func setAspect(_ newAspect: CropAspect) {
        aspect = newAspect
        guard let ratio = newAspect.ratio, ratio > 0 else { return }
        // 以中心点为锚, 按新 ratio 调整 width/height
        let centerX = cropRect.midX
        let centerY = cropRect.midY
        // 用当前 height 算新 width
        let newHeight = cropRect.height
        var newWidth = newHeight * ratio
        // 越界 (新 width > 1): 用 width 反算 height
        if newWidth > 1 {
            newWidth = 1
        }
        // 重新计算 (保持中心 + 不超界)
        var newX = centerX - newWidth / 2
        var newY = centerY - newHeight / 2
        newX = max(0, min(newX, 1 - newWidth))
        newY = max(0, min(newY, 1 - newHeight))
        cropRect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight).integral
        needsDisplay = true
        onChange?()
    }

    /// 序列化当前 cropRect 为 Data?
    func serializeCrop() -> Data? {
        let crop = CropRect(
            x: Double(cropRect.origin.x),
            y: Double(cropRect.origin.y),
            width: Double(cropRect.size.width),
            height: Double(cropRect.size.height),
            aspect: aspect
        )
        return crop.toData()
    }

    /// 从 Photo.cropRect 恢复
    func loadFromData(_ data: Data?) {
        guard let data, let crop = CropRect.fromData(data) else { return }
        cropRect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        aspect = crop.aspect
        needsDisplay = true
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let normalized = NSPoint(x: max(0, min(1, p.x / bounds.width)), y: max(0, min(1, p.y / bounds.height)))
        if let mode = hitTest(normalized: normalized) {
            dragMode = mode
            dragStartNormalized = normalized
            dragStartCropRect = cropRect
        } else {
            // outside crop = reset (Photos.app 范式)
            reset()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragMode != .none else { return }
        let p = convert(event.locationInWindow, from: nil)
        let normalized = NSPoint(x: max(0, min(1, p.x / bounds.width)), y: max(0, min(1, p.y / bounds.height)))
        let dx = normalized.x - dragStartNormalized.x
        let dy = normalized.y - dragStartNormalized.y
        applyDrag(mode: dragMode, dx: dx, dy: dy)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
        onChange?()
    }

    private func hitTest(normalized p: NSPoint) -> DragMode? {
        // 把 normalized cropRect 转 view coord
        let cropInView = CGRect(
            x: cropRect.origin.x * bounds.width,
            y: cropRect.origin.y * bounds.height,
            width: cropRect.width * bounds.width,
            height: cropRect.height * bounds.height
        )
        let halfH = SheetMetrics.cropHandleSize / 2
        let cornerSize: CGFloat = SheetMetrics.cropHandleSize * 3
        // 4 corners
        if NSPointInRect(p, NSRect(x: cropInView.minX - halfH, y: cropInView.maxY - halfH, width: cornerSize, height: cornerSize)) { return .cornerNW }
        if NSPointInRect(p, NSRect(x: cropInView.maxX - halfH, y: cropInView.maxY - halfH, width: cornerSize, height: cornerSize)) { return .cornerNE }
        if NSPointInRect(p, NSRect(x: cropInView.maxX - halfH, y: cropInView.minY - halfH, width: cornerSize, height: cornerSize)) { return .cornerSE }
        if NSPointInRect(p, NSRect(x: cropInView.minX - halfH, y: cropInView.minY - halfH, width: cornerSize, height: cornerSize)) { return .cornerSW }
        // 4 edges (narrower hit area)
        if abs(p.x - cropInView.minX) < halfH && p.y >= cropInView.minY && p.y <= cropInView.maxY { return .edgeW }
        if abs(p.x - cropInView.maxX) < halfH && p.y >= cropInView.minY && p.y <= cropInView.maxY { return .edgeE }
        if abs(p.y - cropInView.minY) < halfH && p.x >= cropInView.minX && p.x <= cropInView.maxX { return .edgeS }
        if abs(p.y - cropInView.maxY) < halfH && p.x >= cropInView.minX && p.x <= cropInView.maxX { return .edgeN }
        // center
        if NSPointInRect(p, cropInView) { return .center }
        return nil
    }

    private func applyDrag(mode: DragMode, dx: CGFloat, dy: CGFloat) {
        var r = dragStartCropRect
        switch mode {
        case .none: return
        case .center:
            r.origin.x = (dragStartCropRect.origin.x + dx).clamped(to: 0...(1 - r.width))
            r.origin.y = (dragStartCropRect.origin.y + dy).clamped(to: 0...(1 - r.height))
        case .cornerNW:
            let newX = min(dragStartCropRect.maxX, dragStartCropRect.origin.x + dx)
            let newY = min(dragStartCropRect.maxY, dragStartCropRect.origin.y + dy)
            r = CGRect(x: newX, y: newY, width: dragStartCropRect.maxX - newX, height: dragStartCropRect.maxY - newY)
            constrainCornerAspect(mode: mode, rect: &r)
        case .cornerNE:
            let newY = min(dragStartCropRect.maxY, dragStartCropRect.origin.y + dy)
            let newMaxX = max(dragStartCropRect.minX, dragStartCropRect.maxX + dx)
            r = CGRect(x: dragStartCropRect.minX, y: newY, width: newMaxX - dragStartCropRect.minX, height: dragStartCropRect.maxY - newY)
            constrainCornerAspect(mode: mode, rect: &r)
        case .cornerSE:
            let newMaxX = max(dragStartCropRect.minX, dragStartCropRect.maxX + dx)
            let newMaxY = max(dragStartCropRect.minY, dragStartCropRect.maxY + dy)
            r = CGRect(x: dragStartCropRect.minX, y: dragStartCropRect.minY, width: newMaxX - dragStartCropRect.minX, height: newMaxY - dragStartCropRect.minY)
            constrainCornerAspect(mode: mode, rect: &r)
        case .cornerSW:
            let newX = min(dragStartCropRect.maxX, dragStartCropRect.origin.x + dx)
            let newMaxY = max(dragStartCropRect.minY, dragStartCropRect.maxY + dy)
            r = CGRect(x: newX, y: dragStartCropRect.minY, width: dragStartCropRect.maxX - newX, height: newMaxY - dragStartCropRect.minY)
            constrainCornerAspect(mode: mode, rect: &r)
        case .edgeN:
            let newY = min(dragStartCropRect.maxY, dragStartCropRect.origin.y + dy)
            r = CGRect(x: dragStartCropRect.origin.x, y: newY, width: dragStartCropRect.width, height: dragStartCropRect.maxY - newY)
        case .edgeS:
            let newMaxY = max(dragStartCropRect.minY, dragStartCropRect.maxY + dy)
            r = CGRect(x: dragStartCropRect.origin.x, y: dragStartCropRect.origin.y, width: dragStartCropRect.width, height: newMaxY - dragStartCropRect.origin.y)
        case .edgeE:
            let newMaxX = max(dragStartCropRect.minX, dragStartCropRect.maxX + dx)
            r = CGRect(x: dragStartCropRect.origin.x, y: dragStartCropRect.origin.y, width: newMaxX - dragStartCropRect.origin.x, height: dragStartCropRect.height)
        case .edgeW:
            let newX = min(dragStartCropRect.maxX, dragStartCropRect.origin.x + dx)
            r = CGRect(x: newX, y: dragStartCropRect.origin.y, width: dragStartCropRect.maxX - newX, height: dragStartCropRect.height)
        }
        cropRect = r.clampedToUnit()
    }

    /// Corner 拖拽时如果 aspect locked, 按 ratio 调整 (anchor 对角 — drag corner, 锚定 opposite corner)
    private func constrainCornerAspect(mode: DragMode, rect: inout CGRect) {
        guard let ratio = aspectRatio, ratio > 0 else { return }
        switch mode {
        case .cornerNW:
            // anchor: SE (maxX, maxY) — 改 width 同步 height
            let h = rect.width / ratio
            rect.size.height = h
            rect.origin.y = rect.maxY - h
        case .cornerNE:
            let h = rect.width / ratio
            rect.size.height = h
            rect.origin.y = rect.maxY - h
        case .cornerSE:
            // anchor: NW (minX, minY) — 改 width 同步 height
            let h = rect.width / ratio
            rect.size.height = h
        case .cornerSW:
            let h = rect.width / ratio
            rect.size.height = h
        default: break
        }
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        // 1. 背景 dim (原图 + 0.4 alpha 灰色蒙版)
        if let image = backgroundImage {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.6)
        }
        NSColor.black.withAlphaComponent(0.5).setFill()
        bounds.fill()

        // 2. 亮 crop 区域 (从原图 extract)
        let cropInView = CGRect(
            x: cropRect.origin.x * bounds.width,
            y: cropRect.origin.y * bounds.height,
            width: cropRect.width * bounds.width,
            height: cropRect.height * bounds.height
        )
        if let image = backgroundImage {
            image.draw(
                in: cropInView,
                from: CGRect(
                    x: cropRect.origin.x * image.size.width,
                    y: cropRect.origin.y * image.size.height,
                    width: cropRect.width * image.size.width,
                    height: cropRect.height * image.size.height
                ),
                operation: .copy,
                fraction: 1.0
            )
        }

        // 3. Crop border (2pt white + 2pt black outline)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropInView)
        border.lineWidth = 2
        border.stroke()

        // 4. Rule-of-thirds grid (dim white lines)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for i in 1...2 {
            let xPos = cropInView.minX + cropInView.width * CGFloat(i) / 3
            grid.move(to: NSPoint(x: xPos, y: cropInView.minY))
            grid.line(to: NSPoint(x: xPos, y: cropInView.maxY))
            let yPos = cropInView.minY + cropInView.height * CGFloat(i) / 3
            grid.move(to: NSPoint(x: cropInView.minX, y: yPos))
            grid.line(to: NSPoint(x: cropInView.maxX, y: yPos))
        }
        grid.stroke()

        // 5. 8 handles (4 corner + 4 edge) — 8pt 白色方形 + 1pt 黑色 outline
        let h = SheetMetrics.cropHandleSize
        let handlePositions: [NSPoint] = [
            NSPoint(x: cropInView.minX, y: cropInView.maxY),  // NW
            NSPoint(x: cropInView.maxX, y: cropInView.maxY),  // NE
            NSPoint(x: cropInView.maxX, y: cropInView.minY),  // SE
            NSPoint(x: cropInView.minX, y: cropInView.minY),  // SW
            NSPoint(x: cropInView.midX, y: cropInView.maxY),  // N (edge)
            NSPoint(x: cropInView.maxX, y: cropInView.midY),  // E (edge)
            NSPoint(x: cropInView.midX, y: cropInView.minY),  // S (edge)
            NSPoint(x: cropInView.minX, y: cropInView.midY),  // W (edge)
        ]
        for pos in handlePositions {
            let handleRect = NSRect(x: pos.x - h/2, y: pos.y - h/2, width: h, height: h)
            NSColor.white.setFill()
            NSBezierPath(rect: handleRect).fill()
            NSColor.black.setStroke()
            let outline = NSBezierPath(rect: handleRect)
            outline.lineWidth = 1
            outline.stroke()
        }
    }
}

// MARK: - V6.97.1: 辅助 — CGRect 限幅到 [0,1] unit square
private extension CGRect {
    func clampedToUnit() -> CGRect {
        let x = origin.x.clamped(to: 0...(1 - width))
        let y = origin.y.clamped(to: 0...(1 - height))
        let w = Swift.min(swift_width, 1)
        let h = Swift.min(swift_height, 1)
        return CGRect(x: x, y: y, width: w, height: h).integral
    }
    var swift_width: CGFloat { size.width }
    var swift_height: CGFloat { size.height }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - V6.97.1: NSViewController 容器 (跟 V6.94.1 MarkupCanvasViewController 模式一致)
class CropCanvasViewController: NSViewController {
    var canvas: CropCanvasView
    var backgroundImage: NSImage?

    init(canvas: CropCanvasView) {
        self.canvas = canvas
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: SheetMetrics.cropWidth, height: SheetMetrics.cropHeight))
        canvas.frame = container.bounds
        canvas.autoresizingMask = [.width, .height]
        container.addSubview(canvas)
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        canvas.backgroundImage = backgroundImage
        view.window?.makeFirstResponder(canvas)
    }
}

// MARK: - V6.97.1: SwiftUI bridge (跟 CanvasViewRepresentable 同 pattern)
struct CropCanvasViewRepresentable: NSViewControllerRepresentable {
    let canvas: CropCanvasView
    let backgroundImage: NSImage?

    func makeNSViewController(context: Context) -> CropCanvasViewController {
        let vc = CropCanvasViewController(canvas: canvas)
        vc.backgroundImage = backgroundImage
        return vc
    }
    func updateNSViewController(_ vc: CropCanvasViewController, context: Context) {
        vc.backgroundImage = backgroundImage
        vc.canvas = canvas
    }
}

// MARK: - V6.97.1: CropSheet (跟 V6.94.1 MarkupSheet 模式 — 4-段 toolbar)
struct CropSheet: View {
    let photo: Photo
    // V6.97.1.1 (Bug fix C1): model 注入 — save() 走 model.grid.cropSelected (跟 rotateSelected 同样)
    //   CropSheet 必须能拿到 ContentViewModel 才能调 cropSelected (undo + toast register)
    @Bindable var model: ContentViewModel
    @State private var canvas = CropCanvasView(frame: .zero)
    @State private var selectedAspect: CropAspect = .freeform
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            cropToolbar
            Divider()
            CropCanvasViewRepresentable(canvas: canvas, backgroundImage: loadBackgroundImage())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: SheetMetrics.cropWidth, minHeight: SheetMetrics.cropHeight)
        .toolbar(.hidden)
        .onAppear {
            if let data = photo.cropRect {
                canvas.loadFromData(data)
                selectedAspect = CropRect.fromData(data)?.aspect ?? .freeform
            } else {
                canvas.reset()
            }
        }
    }

    // 4-段 toolbar: [Presets] | [Reset] | [Rotate] | [Cancel · Apply]
    private var cropToolbar: some View {
        HStack(spacing: Spacing.lg) {
            // 段 1: 6 preset pills (Photos.app Sonoma+ 范式)
            HStack(spacing: 0) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    cropPresetButton(aspect)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Surface.panel)
            )

            // 段 2: Reset (独立按钮, Divider 跟段 1 隔开)
            Divider().frame(height: 22)
            Button {
                canvas.reset()
                selectedAspect = .freeform
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: SheetMetrics.cropPresetButtonHeight, height: SheetMetrics.cropPresetButtonHeight)
            .help(Copy.cropReset)

            // 段 3: Rotate 90° (独立按钮 — 旋转 crop rect 坐标, 不动原图)
            Divider().frame(height: 22)
            Button {
                rotateCrop()
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: SheetMetrics.cropPresetButtonHeight, height: SheetMetrics.cropPresetButtonHeight)
            .help(Copy.cropRotate90)

            Spacer(minLength: Spacing.lg)

            // 段 4: Cancel + Apply (右侧 CTA 组, Apply 用 borderedProminent)
            Button(Copy.cropSheetCancel, role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
            Button(Copy.cropSheetApply) { save() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(.bar)
    }

    // V6.97.1: preset pill 按钮 — 选中态用 accentColor 圆角背景 (跟 markup tool button 同 pattern)
    @ViewBuilder
    private func cropPresetButton(_ aspect: CropAspect) -> some View {
        let isSelected = selectedAspect == aspect
        Button {
            selectedAspect = aspect
            canvas.setAspect(aspect)
        } label: {
            Text(Copy.cropPreset(aspect))
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(
                    width: aspect == .freeform ? 64 : 44,
                    height: SheetMetrics.cropPresetButtonHeight
                )
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // V6.97.1: Rotate 90° — 旋转 crop rect 90° (跟原图旋转独立)
    //   Photos.app 范式: 旋转 crop 不影响原图方向, 重新规划裁剪区
    private func rotateCrop() {
        let centerX = canvas.cropRect.midX
        let centerY = canvas.cropRect.midY
        // 90° 旋转: (x, y, w, h) → (1-y-h, x, h, w) (基于中心)
        let w = canvas.cropRect.width
        let h = canvas.cropRect.height
        let newW = h
        let newH = w
        var newX = centerX - newW / 2
        var newY = centerY - newH / 2
        newX = max(0, min(newX, 1 - newW))
        newY = max(0, min(newY, 1 - newH))
        canvas.cropRect = CGRect(x: newX, y: newY, width: newW, height: newH).integral
        canvas.needsDisplay = true
        canvas.onChange?()
    }

    private func loadBackgroundImage() -> NSImage? {
        guard let data = try? Data(contentsOf: photo.fileURL),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private func save() {
        // V6.97.1.1 (Bug fix C1): 改调 model.grid.cropSelected (跟 rotateSelected 同 pattern)
        //   之前: 直接调 PhotoCropService.applyCrop — 绕过 cropSelected, ⌘Z 不能撤销 crop
        //   现在: 走 model.grid.cropSelected(rect:aspect:), undo + toast 自动 register
        //   CoalesceId "crop" 1s 窗内合并连续裁剪 (跟 markup/rotate 一致)
        model.grid.cropSelected(rect: canvas.cropRect, aspect: canvas.aspect)
        dismiss()
    }
}
