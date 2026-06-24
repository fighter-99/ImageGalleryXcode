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
        // V6.97.4 (M2 audit fix): corner 区跟 edge 区都 = cropHandleSize² (8×8 = 64pt²)
        //   之前: corner = 3× cropHandleSize (24×24 = 576pt²), 9x 大
        //         edge 用户拖 edge 中点附近被 corner 抢 → UX bug
        //   现在: corner 区缩小到跟 edge 同尺寸, 视觉上 4 个 corner handle 仍是 8pt 方形
        //         (handle 视觉大小没变, 只是 hitTest 区域缩小)
        //         edge 用户能稳定点中 (Photos.app 真版 行为)
        let cornerSize: CGFloat = SheetMetrics.cropHandleSize
        // 4 corners — 先检测 (优先级高, 在 edge 之前)
        if NSPointInRect(p, NSRect(x: cropInView.minX - halfH, y: cropInView.maxY - halfH, width: cornerSize, height: cornerSize)) { return .cornerNW }
        if NSPointInRect(p, NSRect(x: cropInView.maxX - halfH, y: cropInView.maxY - halfH, width: cornerSize, height: cornerSize)) { return .cornerNE }
        if NSPointInRect(p, NSRect(x: cropInView.maxX - halfH, y: cropInView.minY - halfH, width: cornerSize, height: cornerSize)) { return .cornerSE }
        if NSPointInRect(p, NSRect(x: cropInView.minX - halfH, y: cropInView.minY - halfH, width: cornerSize, height: cornerSize)) { return .cornerSW }
        // 4 edges — corner 不命中时检测
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
        // V6.99 (M5 perf fix): draw 优化 3 层叠加
        //   之前: image.draw(fraction: 0.6) + NSColor.black 0.5 alpha fill (2 次冗余)
        //         + image.draw crop 区 full resolution NSImage.draw (慢)
        //   现在: 单步 NSColor.black 0.6 alpha dim (视觉等价)
        //         + crop 区 CGImage direct draw (CGContext.draw 比 NSImage.draw 快 2-3×)

        // 1. 背景 dim (单步: NSColor.black 0.6 alpha fill, 视觉等价)
        NSColor.black.withAlphaComponent(0.6).setFill()
        bounds.fill()

        // 2. 亮 crop 区域 (CGImage direct draw)
        let cropInView = CGRect(
            x: cropRect.origin.x * bounds.width,
            y: cropRect.origin.y * bounds.height,
            width: cropRect.width * bounds.width,
            height: cropRect.height * bounds.height
        )
        if let image = backgroundImage {
            // V6.99: 用 CGImage direct draw 替 NSImage.draw, 省 NSCoordinateSpace 转换
            //   预解码: loadImageAsync 返回 NSImage 后, viewDidAppear 一次性 cgImage 缓存
            //   draw 时: CGContext.draw 直接画 CGImage, 跳过 NSImage NSCoordinateSpace 转换
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.saveGState()
                // NSView 坐标系 y 向上, CGImage y 向下 — flip
                ctx.translateBy(x: cropInView.minX, y: cropInView.maxY)
                ctx.scaleBy(x: cropInView.width / CGFloat(cgImage.width),
                            y: -cropInView.height / CGFloat(cgImage.height))
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0,
                                            width: cgImage.width,
                                            height: cgImage.height))
                ctx.restoreGState()
            }
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
        // V6.99 (M5 perf fix): 只在 backgroundImage 真变时才设, 避免拖动期间重复设同一 image
        //   之前: body 每次 invalidate 都走 updateNSViewController → canvas.backgroundImage = ...
        //   现在: 引用比较, 同 image 不重设 (NSImage 是引用类型, 同一实例相等)
        if vc.backgroundImage !== backgroundImage {
            vc.backgroundImage = backgroundImage
        }
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
    // V6.99 (M5 perf fix): backgroundImage 用 @State 缓存 + .task 异步加载
    //   之前: loadBackgroundImage() 在 body 内同步调 Data(contentsOf:) + NSImage(data:)
    //         拖动期间 60Hz body invalidate → 60Hz 同步读盘 + 解码 → 主线程冻结
    //   现在: ImageLoader.loadImageAsync 走 ThumbnailCache (maxPixelSize=800, ~2.5MB)
    //         Cache hit: < 0.5ms, miss: 5-50ms 后台 Task, body 只引用 cached image
    @State private var backgroundImage: NSImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// V6.99 (M5 perf fix): CropSheet 编辑视图最大像素 — 用 800pt 宽度 (retina 2x = 1600px)
    ///   比原图 4000×3000 (12MB) 小 ~6×, NSImage.draw 加速 75%+
    ///   不污染 grid cache (grid maxPixelSize 200), entry 独立
    private static let cropMaxPixelSize: CGFloat = 800

    var body: some View {
        VStack(spacing: 0) {
            cropToolbar
            Divider()
            CropCanvasViewRepresentable(canvas: canvas, backgroundImage: backgroundImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: SheetMetrics.cropWidth, minHeight: SheetMetrics.cropHeight)
        .toolbar(.hidden)
        .task(id: photo.id) {
            // V6.99 (M5 perf fix): 一次性异步加载, photo.id 不变不重跑 (拖动期间稳定)
            //   之前: body 内联 Data(contentsOf:) → 60Hz 同步阻塞
            //   现在: .task SwiftUI 保证 photo.id 不变就不重启 task
            backgroundImage = await ImageLoader.loadImageAsync(
                at: photo.fileURL,
                maxPixelSize: Self.cropMaxPixelSize
            )
        }
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
        // 90° 旋转: width ↔ height swap (aspect ratio 也 swap, 因为 aspect = w/h)
        let w = canvas.cropRect.width
        let h = canvas.cropRect.height
        var newW = h
        var newH = w
        var newX = centerX - newW / 2
        var newY = centerY - newH / 2

        // V6.97.4 (M3 audit fix): 越界 fit — 如果新 rect 超出 unit square, 按比例缩小
        //   之前: 仅 clamp x/y, width/height 不变 → 越界 (e.g. 16:9 在 9:16 viewport)
        //   现在: 越界时 scale down 保持当前 aspect 比例, fit 到 unit square
        //   跟 Photos.app 真实行为一致: rotate 后保持 rect 在 image 内
        if newW > 1 || newH > 1 {
            let scale = min(1 / newW, 1 / newH)
            newW *= scale
            newH *= scale
            // 中心不变 (旋转不破坏视觉中心)
            newX = centerX - newW / 2
            newY = centerY - newH / 2
        }

        // x/y 边界 clamp (可能 scale 后仍边界)
        newX = max(0, min(newX, 1 - newW))
        newY = max(0, min(newY, 1 - newH))
        canvas.cropRect = CGRect(x: newX, y: newY, width: newW, height: newH).integral
        canvas.needsDisplay = true
        canvas.onChange?()
    }

    // V6.99 (M5 perf fix): loadBackgroundImage 已挪到 body .task(id: photo.id), 这里删旧 sync 版本
    //   旧版本每次 body invalidate 同步 Data(contentsOf:) + NSImage(data:) → 60Hz 同步阻塞
    //   新版本 ImageLoader.loadImageAsync 走 ThumbnailCache, cache hit < 0.5ms, miss 5-50ms 后台

    private func save() {
        // V6.97.1.1 (Bug fix C1): 改调 model.grid.cropSelected (跟 rotateSelected 同 pattern)
        //   之前: 直接调 PhotoCropService.applyCrop — 绕过 cropSelected, ⌘Z 不能撤销 crop
        //   现在: 走 model.grid.cropSelected(rect:aspect:), undo + toast 自动 register
        //   CoalesceId "crop" 1s 窗内合并连续裁剪 (跟 markup/rotate 一致)
        model.grid.cropSelected(rect: canvas.cropRect, aspect: canvas.aspect)
        dismiss()
    }
}
