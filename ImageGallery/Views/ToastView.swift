//
//  ToastView.swift
//  ImageGallery
//
//  轻量级提示条。底部弹出，自动消失。
//

import SwiftUI

struct ToastView: View {
    enum ToastType {
        case info
        case success
        case error

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .accentColor
            case .success: return .green
            case .error: return .red
            }
        }
    }

    let message: String
    let type: ToastType

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.callout)
                .foregroundStyle(type.tint)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(type.tint.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

#Preview {
    VStack(spacing: 12) {
        ToastView(message: "已导入 12 张图片", type: .success)
        ToastView(message: "复制失败：磁盘空间不足", type: .error)
        ToastView(message: "已切换到「旅行」文件夹", type: .info)
    }
    .padding()
    .frame(width: 400)
}
