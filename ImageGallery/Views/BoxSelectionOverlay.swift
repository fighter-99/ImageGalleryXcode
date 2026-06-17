//
//  BoxSelectionOverlay.swift
//  ImageGallery
//
//  V3.7.1: ⌥+drag 框选视觉层
//  之前 BoxSelectionGesture 没视觉反馈, 用户不知道框选生效
//  加 2pt accent border + 半透明 accent 填充 + "已选 N 张" floating label
//  范式: macOS Photos / Finder 文件框选一致
//

import SwiftUI

struct BoxSelectionOverlay: View {
    let rect: CGRect
    let count: Int

    var body: some View {
        // 框选矩形 (2pt accent border + 半透明 accent 填充)
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .background(
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            // 跟随框选 rect 右上角, 显示"已选 N 张" floating label
            .overlay(alignment: .topLeading) {
                Text("已选 \(count) 张")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
                    .offset(x: 4, y: -22)  // 浮在 rect 上方 22pt
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .position(x: rect.maxX, y: rect.minY)
            }
    }
}
