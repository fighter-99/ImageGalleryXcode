//
//  MarkupSheet.swift
//  ImageGallery
//
//  V6.94.1: Markup Sheet (P0 #3)
//
//  macOS PencilKit 没有 PKCanvasView (iOS-only). 用 NSView + NSBezierPath 自绘替代.
//  设计：
//  - NSViewController 持 MarkupCanvasView (mouseDown/Draw 收集 bezier path)
//  - 序列化: NSBezierPath → CGPath → Data (CFPropertyList)
//  - 反序列化 + compose: MarkupService.compose 跟原图合成显示
//  - 工具栏: pen / marker / eraser + 颜色选择
//
// 触发: ContentView showingMarkup, ⌘M 走 NotificationCenter.markupRequested
//

import SwiftUI
import AppKit
import SwiftData

// V6.94.1: 自定义 NSView 收集鼠标路径 — macOS PencilKit 无 PKCanvasView
class MarkupCanvasView: NSView {
    var paths: [MarkupPath] = []
    var currentTool: MarkupCanvasTool = .pen
    var currentColor: NSColor = .black
    var onChange: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { startStroke(at: event.locationInWindow) }
    override func mouseDragged(with event: NSEvent) { continueStroke(at: event.locationInWindow) }
    override func mouseUp(with event: NSEvent) { endStroke() }

    private func startStroke(at windowPoint: NSPoint) {
        let p = convert(windowPoint, from: nil)
        paths.append(MarkupPath(tool: currentTool, color: currentColor, points: [p]))
        needsDisplay = true
    }

    private func continueStroke(at windowPoint: NSPoint) {
        let p = convert(windowPoint, from: nil)
        guard !paths.isEmpty else { return }
        paths[paths.count - 1].points.append(p)
        needsDisplay = true
        onChange?()
    }

    private func endStroke() {
        onChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for path in paths {
            // V6.94.1: eraser 画白色 (当作橡皮擦覆盖底层标注) — 之前画用户色 = 没用橡皮擦
            //   跟 MarkupService.compose 同步: 渲染时 eraser 也是 NSColor.white
            let strokeColor = path.tool == .eraser ? NSColor.white : path.color
            strokeColor.setStroke()
            let bezier = NSBezierPath()
            bezier.lineWidth = path.tool == .marker ? 12 : (path.tool == .eraser ? 18 : 5)
            bezier.lineCapStyle = .round
            for (i, pt) in path.points.enumerated() {
                if i == 0 { bezier.move(to: pt) } else { bezier.line(to: pt) }
            }
            bezier.stroke()
        }
    }

    // V6.94.1: 撤销最后一笔 (in-sheet 局部 undo, 跟 SwiftData undo 分开)
    func undoLastStroke() {
        if !paths.isEmpty {
            paths.removeLast()
            needsDisplay = true
            onChange?()
        }
    }

    func strokeCount() -> Int { paths.count }

    func clearAll() {
        paths.removeAll()
        needsDisplay = true
        onChange?()
    }

    func serializeToData() -> Data? {
        // V6.94.1: 序列化为 plist — [{tool, color, points: [[x,y]...]}]
        let dicts = paths.map { path -> [String: Any] in
            [
                "tool": path.tool.rawValue,
                "color": path.color.hexString,
                "points": path.points.map { ["x": Double($0.x), "y": Double($0.y)] }
            ]
        }
        return try? PropertyListSerialization.data(fromPropertyList: dicts, format: .binary, options: 0)
    }

    func loadFromData(_ data: Data) {
        guard let array = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return }
        paths = array.compactMap { dict in
            guard let toolStr = dict["tool"] as? String,
                  let colorStr = dict["color"] as? String,
                  let pointsArr = dict["points"] as? [[String: Double]] else { return nil }
            let tool = MarkupCanvasTool(rawValue: toolStr) ?? .pen
            let color = NSColor.fromHex(colorStr) ?? .black
            let points = pointsArr.compactMap { p -> NSPoint? in
                guard let x = p["x"], let y = p["y"] else { return nil }
                return NSPoint(x: x, y: y)
            }
            return MarkupPath(tool: tool, color: color, points: points)
        }
        needsDisplay = true
    }
}

struct MarkupPath {
    let tool: MarkupCanvasTool
    let color: NSColor
    var points: [NSPoint]
}

enum MarkupCanvasTool: String {
    case pen, marker, eraser
}

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    static func fromHex(_ hex: String) -> NSColor? {
        var hexClean = hex.trimmingCharacters(in: .whitespaces)
        if hexClean.hasPrefix("#") { hexClean.removeFirst() }
        guard hexClean.count == 6, let val = UInt32(hexClean, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

// V6.94.1: NSViewController 持 MarkupCanvasView + background NSImageView
class MarkupCanvasViewController: NSViewController {
    var canvas: MarkupCanvasView
    private let imageView = NSImageView()

    init(canvas: MarkupCanvasView) {
        self.canvas = canvas
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    var backgroundImage: NSImage? {
        didSet { imageView.image = backgroundImage }
    }

    override func loadView() {
        // V6.97 P2-1: 容器尺寸走 SheetMetrics.markupWidth/markupHeight — 之前 hardcoded 800x600
        //   跟 SwiftUI 主体 .frame 一致, 改尺寸只改一处
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: SheetMetrics.markupWidth,
            height: SheetMetrics.markupHeight
        ))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        canvas.autoresizingMask = [.width, .height]
        canvas.frame = container.bounds
        container.addSubview(canvas)

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(canvas)
    }
}

// V6.94.1: NSViewControllerRepresentable — macOS 14+ SwiftUI 集成
struct CanvasViewRepresentable: NSViewControllerRepresentable {
    let canvas: MarkupCanvasView
    let backgroundImage: NSImage?

    func makeNSViewController(context: Context) -> MarkupCanvasViewController {
        let vc = MarkupCanvasViewController(canvas: canvas)
        vc.backgroundImage = backgroundImage
        return vc
    }

    func updateNSViewController(_ vc: MarkupCanvasViewController, context: Context) {
        vc.backgroundImage = backgroundImage
        vc.canvas = canvas
    }
}

struct MarkupSheet: View {
    let photo: Photo
    @State private var canvas = MarkupCanvasView(frame: .zero)
    @State private var selectedTool: MarkupCanvasTool = .pen
    @State private var selectedColor: NSColor = .black
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            markupToolbar
            Divider()
            CanvasViewRepresentable(canvas: canvas, backgroundImage: loadBackgroundImage())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // V6.97 P2-1: 窗口尺寸走 SheetMetrics (跟 NSView container 同步)
        .frame(minWidth: SheetMetrics.markupWidth, minHeight: SheetMetrics.markupHeight)
        // V6.97 P2-1: 工具栏 macOS 标准 .bar 材质 — 自动适配 light/dark mode
        //   替代之前 hardcoded color, 跟系统 toolbar 视觉锤一致
        .toolbar(.hidden)  // 用自定义 toolbar, 不显示 SwiftUI 默认 toolbar
        .onAppear {
            if let data = photo.markupData {
                canvas.loadFromData(data)
            }
            canvas.onChange = { /* trigger SwiftUI redraw if needed */ }
        }
    }

    // V6.97 P2-1: 7 个预设颜色 — Photos Preview 范式 (基础色 + 二级色)
    //   之前 hardcoded 7 色现在提常量, 方便后续扩展 (e.g. 8/10 色或系统 ColorPicker)
    private static let markupColors: [NSColor] = [
        .black, .red, .orange, .yellow, .green, .blue, .purple
    ]

    // V6.97 P2-1: 工具栏重做 — 4 段视觉分组 (Photos Preview 范式)
    //   [Tools] | [Undo] | [Colors] | [Cancel · Done]
    //   每段独立 HStack + Spacing 间隔, 中间放 Divider 强化分组感
    //   工具按钮走 Toggle 视觉态 (selected 蓝色 + 圆角背景), 不再只靠 accentColor
    private var markupToolbar: some View {
        HStack(spacing: Spacing.lg) {
            // 段 1: 工具组 (3 个 connected-style 按钮)
            HStack(spacing: 0) {
                markupToolButton(.pen, icon: "pencil.tip", label: Copy.markupTool("pen"))
                markupToolButton(.marker, icon: "highlighter", label: Copy.markupTool("marker"))
                markupToolButton(.eraser, icon: "eraser", label: Copy.markupTool("eraser"))
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Surface.panel)
            )

            // 段 2: 撤销 (独立按钮, 跟工具组用 Divider 隔开)
            Divider().frame(height: 22)
            Button {
                canvas.undoLastStroke()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: SheetMetrics.markupToolButtonSize, height: SheetMetrics.markupToolButtonSize)
            .disabled(canvas.strokeCount() == 0)
            .help(Copy.markupUndoLastStroke)

            // 段 3: 颜色盘 (7 个圆点, 选中态有 accent ring + 缩放)
            Divider().frame(height: 22)
            HStack(spacing: Spacing.xs + 2) {
                ForEach(Self.markupColors, id: \.self) { c in
                    markupColorButton(c)
                }
            }

            Spacer(minLength: Spacing.lg)

            // 段 4: Cancel + Done (右侧 CTA 组, Done 用 borderedProminent)
            Button(Copy.markupSheetCancel, role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
            Button(Copy.markupSheetDone) { save() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(.bar)  // V6.97 P2-1: macOS 系统 .bar 材质 — 自动 light/dark + vibrancy
    }

    // V6.97 P2-1: 工具按钮子组件 — 选中态用 Surface 圆角背景 + accentColor icon
    @ViewBuilder
    private func markupToolButton(_ tool: MarkupCanvasTool, icon: String, label: String) -> some View {
        let isSelected = selectedTool == tool
        Button {
            selectedTool = tool
            canvas.currentTool = tool
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(
                    width: SheetMetrics.markupToolButtonSize,
                    height: SheetMetrics.markupToolButtonSize
                )
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // V6.97 P2-1: 颜色按钮子组件 — 选中态 ring + 轻微缩放, 走 SheetMetrics.markupColorSwatchSize
    @ViewBuilder
    private func markupColorButton(_ color: NSColor) -> some View {
        let isSelected = selectedColor == color
        Button {
            selectedColor = color
            canvas.currentColor = color
        } label: {
            Circle()
                .fill(Color(color))
                .frame(
                    width: SheetMetrics.markupColorSwatchSize,
                    height: SheetMetrics.markupColorSwatchSize
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )
                .scaleEffect(isSelected ? 1.12 : 1.0)
                .animation(Animations.press, value: isSelected)
        }
        .buttonStyle(.plain)
        // NSColor 没 localizedName — 用 Color 转 string (R,G,B) 作为简易 fallback tooltip
        .help(String(format: "#%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255)
        ))
    }

    private func loadBackgroundImage() -> NSImage? {
        guard let data = try? Data(contentsOf: photo.fileURL),
              let image = NSImage(data: data) else { return nil }
        return image
    }

    private func save() {
        guard let data = canvas.serializeToData() else { dismiss(); return }
        // V6.94.1: 用 @Environment modelContext 写 markupData (跟 rotate 等其他 operation 一致)
        MarkupService.applyMarkup(data, to: photo, in: modelContext)
        dismiss()
    }
}