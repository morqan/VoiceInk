//
//  MetricCardBackground.swift
//  VoiceInk
//
//  Shared metric-card chrome (gradient fill + border + shadow) and the info/analysis
//  panel mode, used across the performance/metrics panels.
//

import SwiftUI
import AppKit

enum PanelMode {
    case info
    case analysis
}

struct MetricCardBackground: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: color.opacity(0.15), location: 0),
                        .init(color: Color(NSColor.windowBackgroundColor).opacity(0.1), location: 0.6)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(NSColor.quaternaryLabelColor).opacity(0.3),
                                Color(NSColor.quaternaryLabelColor).opacity(0.1)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
    }
}
