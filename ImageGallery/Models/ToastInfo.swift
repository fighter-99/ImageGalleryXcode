//
//  ToastInfo.swift
//  ImageGallery
//
//  Toast 通知的数据模型。
//  V3.5.17：从 ContentView 的 nested struct 提到 top-level。
//  V5.13：加 id (UUID) + Duration enum + Identifiable，为 Day 4 队列做准备。
//         自定义 == 忽略 id（UUID 每次 init 变）—— 保持原有 message/type/duration 比对语义。
//

import Foundation

struct ToastInfo: Equatable, Identifiable {
    /// Toast 显示时长
    enum Duration: Equatable {
        case short   // 2s
        case normal  // 2.5s（V4.36.x 默认值）
        case long    // 5s（错误 toast 用 .long 让用户看清）

        var seconds: TimeInterval {
            switch self {
            case .short: return 2
            case .normal: return 2.5
            case .long: return 5
            }
        }
    }

    let id: UUID
    let message: String
    let type: ToastView.ToastType
    let duration: Duration

    init(message: String, type: ToastView.ToastType, duration: Duration = .normal) {
        self.id = UUID()
        self.message = message
        self.type = type
        self.duration = duration
    }

    /// 自定义 Equatable：忽略 id（UUID 每次 init 不同，message/type/duration 才是业务语义）
    static func == (lhs: ToastInfo, rhs: ToastInfo) -> Bool {
        lhs.message == rhs.message
            && lhs.type == rhs.type
            && lhs.duration == rhs.duration
    }
}
