//
//  MarkupService.swift
//  ImageGallery
//
//  V6.94.1: Markup 服务 (P0 #3)
//
//  macOS PencilKit 只有 PKDrawing (PKCanvasView 是 iOS-only),
//  所以用 NSBezierPath-based 自绘 (MarkupSheet.swift) + plist 序列化.
//
//  设计：
//  - applyMarkup: 写 photo.markupData + register undo + save context
//  - compose: 显示时跟原图合成 (NSImage + NSBezierPath → NSImage)
//  - 不改原图文件 (PhotoStorage 路径), 标注独立存 SwiftData
//  - undo coalesceId="markup" (1s 窗内连续标注合并, 跟 rotate 模式一致)
//

import Foundation
import SwiftUI
import AppKit
import SwiftData

enum MarkupService {
    @MainActor
    static func applyMarkup(
        _ data: Data,
        to photo: Photo,
        in context: ModelContext,
        undoManager: ImageGalleryUndoManager? = nil
    ) {
        let oldData = photo.markupData
        photo.markupData = data
        do {
            try context.save()
            undoManager?.registerUndoOnly(
                description: Copy.undoMarkup(1),
                undo: {
                    photo.markupData = oldData
                    try? context.save()
                },
                coalesceId: "markup"
            )
        } catch {
            NSLog("V6.94.1: failed to save markupData: \(error)")
        }
    }

    // V6.94.1: 合成原图 + 标注 — 用 NSBezierPath 反序列化 plist
    //   markupData 是 plist 序列化的 MarkupPath 数组
    @MainActor
    static func compose(baseImage: NSImage, markupData: Data?) -> NSImage {
        guard let markupData else { return baseImage }
        guard let paths = deserializePaths(from: markupData), !paths.isEmpty else { return baseImage }

        let composite = NSImage(size: baseImage.size)
        composite.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size))
        for path in paths {
            // V6.94.1: eraser 画白色 (跟 MarkupCanvasView.draw 同步)
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
        composite.unlockFocus()
        return composite
    }

    private static func deserializePaths(from data: Data) -> [CompositeMarkupPath]? {
        guard let array = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return nil }
        return array.compactMap { dict in
            guard let toolStr = dict["tool"] as? String,
                  let colorStr = dict["color"] as? String,
                  let pointsArr = dict["points"] as? [[String: Double]] else { return nil }
            let tool = CompositeTool(rawValue: toolStr) ?? .pen
            let color = NSColor.fromHex(colorStr) ?? .black
            let points = pointsArr.compactMap { p -> NSPoint? in
                guard let x = p["x"], let y = p["y"] else { return nil }
                return NSPoint(x: x, y: y)
            }
            return CompositeMarkupPath(tool: tool, color: color, points: points)
        }
    }
}

// V6.94.1: 服务端 compose 用的纯数据 path (不依赖 MarkupSheet 的 NSView 类型)
struct CompositeMarkupPath {
    let tool: CompositeTool
    let color: NSColor
    let points: [NSPoint]
}

enum CompositeTool: String {
    case pen, marker, eraser
}