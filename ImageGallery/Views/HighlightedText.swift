//
//  HighlightedText.swift
//  ImageGallery
//
//  V6.XX NEW: 搜索结果高亮——在 text 中查找 query 匹配项，用 accent 色 + semibold 标记
//   AttributedString 确保多段匹配全部高亮且不干扰原始布局
//

import SwiftUI

struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributedString)
    }

    private var attributedString: AttributedString {
        guard !query.isEmpty else { return AttributedString(text) }

        var attrStr = AttributedString(text)
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()

        var searchStart = lowerText.startIndex
        while searchStart < lowerText.endIndex {
            guard let range = lowerText[searchStart...].range(of: lowerQuery) else { break }
            guard let attrRange = Range(range, in: attrStr) else {
                searchStart = range.upperBound
                continue
            }
            attrStr[attrRange].foregroundColor = .accentColor
            attrStr[attrRange].font = Font.body.weight(.semibold)
            searchStart = range.upperBound
        }

        return attrStr
    }
}

#Preview("HighlightedText") {
    VStack(spacing: 20) {
        HighlightedText(text: "我的猫照片.jpg", query: "猫")
        HighlightedText(text: "无匹配文字.png", query: "猫")
        HighlightedText(text: "Cat photo.jpg", query: "cat")
        HighlightedText(text: "多段匹配 cat vs Cat.jpg", query: "cat")
    }
    .padding()
    .frame(width: 300)
}
