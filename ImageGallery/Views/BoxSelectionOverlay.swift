//
//  BoxSelectionOverlay.swift
//  ImageGallery
//
//  V3.7.1: ⌥+drag 框选视觉层
//  之前 BoxSelectionGesture 没视觉反馈, 用户不知道框选生效
//  加 2pt accent border + 半透明 accent 填充
//  范式: macOS Photos / Finder 文件框选一致
//
//  V6.22.9: 砍"已选 N 张" floating label
//   - 之前 drag 期间显示 "已选 N 张" 让用户误以为**实时**选中
//     (cell.selectedIDs 在 drag 时不变, 只 onEnded 才设置 — 跟 Photos.app 一致)
//   - 但 "已选 N 张" 视觉强暗示 cell 已经被选中, 用户期望框完才选 (实际行为)
//   - 删 label: drag 期间只显示 rect, 无数字误导
//   - 选区反馈在 onEnded 之后: detail panel / toolbar 显示
//
//  V6.22.9: 改用 ZStack(alignment: .topLeading) + .offset(x: rect.minX, y: rect.minY)
//   - 之前用 .position(x: rect.midX, y: rect.midY) 视觉滞后 1-2pt (用户反馈 'marquee 不跟鼠标')
//   - offset 从 ZStack origin (即 photoGrid 命名空间的 (0,0)) 平移 rect,
//     跟 drag.value.location 在同一坐标空间, 像素级对齐
//

import SwiftUI

struct BoxSelectionOverlay: View {
    let rect: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .allowsHitTesting(false)
    }
}