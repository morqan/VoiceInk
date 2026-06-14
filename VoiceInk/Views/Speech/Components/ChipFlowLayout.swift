//
//  ChipFlowLayout.swift
//  VoiceInk
//
//  Simple wrap/flow layout for chip rows (macOS 14+). Pure layout math, no domain
//  coupling — used by the coaching cards for marker/filler chips.
//

import SwiftUI

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !(rows[rows.count - 1].isEmpty) {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let width = maxWidth == .infinity
            ? rows.map { max(0, $0.reduce(0) { $0 + $1.width + spacing } - spacing) }.max() ?? 0
            : maxWidth
        var height: CGFloat = 0
        for row in rows {
            let rowHeight = row.map(\.height).max() ?? 0
            height += rowHeight + lineSpacing
        }
        height = max(0, height - lineSpacing)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
