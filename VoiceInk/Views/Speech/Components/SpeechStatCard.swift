//
//  SpeechStatCard.swift
//  VoiceInk
//
//  Reusable metric card for the Speech analytics tabs (value + unit + delta-vs-previous
//  + optional info tip). Extracted from SpeechAnalyticsView so the tab views can be
//  split out without dragging the whole view along.
//

import SwiftUI

/// Period-over-period delta shown on a stat card. `improved == nil` → neutral metric.
struct SpeechCardDelta {
    let value: Double
    let format: String
    let improved: Bool?
}

struct SpeechStatCard: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    let color: Color
    let icon: String
    var tip: String? = nil
    var delta: SpeechCardDelta? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 26, height: 26)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let tip {
                    Spacer(minLength: 0)
                    InfoTip(message: tip, iconSize: .small, iconColor: .secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                if let delta {
                    deltaBadge(delta)
                }
            }

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    @ViewBuilder
    private func deltaBadge(_ delta: SpeechCardDelta) -> some View {
        let formatted = String(format: delta.format, abs(delta.value))
        // A coloured "↑0" is misleading — don't show a zero delta.
        if (Double(formatted) ?? 0) != 0 {
            HStack(spacing: 1) {
                Image(systemName: delta.value >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text(formatted)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(delta.improved.map { $0 ? Color.green : .red } ?? .secondary)
            .help(L10n.t(
                en: "vs previous period of the same length",
                ru: "к предыдущему периоду той же длины"
            ))
        }
    }
}
