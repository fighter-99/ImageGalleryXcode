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

        // V6.108 (crash fix): try-catch 整体保护, 任何崩溃 fallback 到 baseImage
        //   之前用户在 thumbnail 上 (V6.106 加 markup overlay) 多次触发崩溃
        //   真因未知 (NSPoint 极值? 损坏 plist? NSBezierPath 内部?) — 全方位防御
        //   任何 path 异常 → 跳过 path, 不影响其他 path 渲染
        //   整体崩溃 → fallback baseImage, 至少不崩
        return safeCompose(baseImage: baseImage, paths: paths)
    }

    /// V6.108: 安全 compose — try-catch + 极值检测 + 单 path 失败隔离
    private static func safeCompose(baseImage: NSImage, paths: [CompositeMarkupPath]) -> NSImage {
        let composite: NSImage
        do {
            composite = NSImage(size: baseImage.size)
            composite.lockFocus()
            baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size))
            for path in paths {
                try drawPathSafe(path)
            }
            composite.unlockFocus()
            return composite
        } catch {
            // V6.108: 任何崩溃 → fallback 原图 (不画 markup, 至少不崩)
            //   已知 crash 路径: NSPoint 极值 / NSBezierPath 内部 / NSImage size 异常
            NSLog("V6.108: MarkupService.safeCompose failed, fallback to baseImage: \(error)")
            return baseImage
        }
    }

    /// V6.108: 单 path 渲染 — try-catch + 极值检测, 单 path 失败不影响其他
    private static func drawPathSafe(_ path: CompositeMarkupPath) throws {
        // V6.108: 极值检测 — NSPoint NaN/Inf 会让 NSBezierPath 内部 crash
        //   有效 NSPoint: x 和 y 都是 finite number (非 NaN, 非 Inf)
        //   损坏 markupData 可能含 NaN (例如浮点精度溢出) — 直接跳过
        let validPoints = path.points.filter { pt in
            pt.x.isFinite && pt.y.isFinite &&
            abs(pt.x) < 1e6 && abs(pt.y) < 1e6  // 防止极大值 (1M+ 像素)
        }
        guard validPoints.count >= 2 else { return }  // 至少 2 点才能画线

        // V6.108: 单 path try-catch — 一个 path 抛异常不影响其他 path
        do {
            let strokeColor = path.tool == .eraser ? NSColor.white : path.color
            strokeColor.setStroke()
            let bezier = NSBezierPath()
            bezier.lineWidth = path.tool == .marker ? 12 : (path.tool == .eraser ? 18 : 5)
            bezier.lineCapStyle = .round
            for (i, pt) in validPoints.enumerated() {
                if i == 0 { bezier.move(to: pt) } else { bezier.line(to: pt) }
            }
            bezier.stroke()
        } catch {
            NSLog("V6.108: drawPathSafe failed for path: \(error)")
            // 单 path 失败 → 跳过, 不抛 (try-catch 隔离)
        }
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