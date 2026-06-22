//
//  VoiceProfileBreakdownView.swift
//  VoiceInk
//
//  The total Match Score card plus the 5-row per-axis breakdown table (WPM,
//  sentence length, complexity, fillers, marker phrases) for the active profile.
//

import SwiftUI

struct VoiceProfileBreakdownView: View {
    let result: VoiceProfileMatcher.MatchResult
    let profile: VoiceProfileTarget

    var body: some View {
        totalScoreCard
        breakdown
    }

    private var totalScoreCard: some View {
        HStack(spacing: 16) {
            // Circular score
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: CGFloat(result.totalScore / 100))
                    .stroke(scoreColor(result.totalScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(result.totalScore))")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor(result.totalScore))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    LocalizedText(en: "Match Score", ru: "Совпадение")
                        .font(.system(size: 13, weight: .semibold))
                    InfoTip(message: SpeechMetricTips.matchScore, iconSize: .small, iconColor: .secondary)
                }
                Text(matchVerdict(result.totalScore))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var breakdown: some View {
        VStack(spacing: 6) {
            metricRow(
                L10n.t(en: "Speed (WPM)", ru: "Темп (WPM)"),
                tip: SpeechMetricTips.axisWPM,
                actual: result.actualWPM,
                target: String(format: "→ %.0f", profile.targetWPM),
                format: "%.0f",
                score: result.wpmScore
            )
            metricRow(
                L10n.t(en: "Sentence length", ru: "Длина предложения"),
                tip: SpeechMetricTips.axisSentence,
                actual: result.actualSentenceLength,
                target: String(format: "→ %.0f", profile.targetSentenceLength),
                format: "%.0f",
                score: result.sentenceLengthScore
            )
            metricRow(
                L10n.t(en: "Complexity", ru: "Сложность"),
                tip: SpeechMetricTips.axisComplexity,
                actual: result.actualComplexity,
                target: String(format: "→ %.1f", profile.targetComplexity),
                format: "%.1f",
                score: result.complexityScore
            )
            metricRow(
                L10n.t(en: "Fillers /100w", ru: "Паразиты /100сл"),
                tip: SpeechMetricTips.axisFillers,
                actual: result.actualFillerRate,
                target: String(format: "→ ≤ %.0f", profile.maxFillerRate),
                format: "%.1f",
                score: result.fillerScore
            )
            metricRow(
                L10n.t(en: "Marker phrases /100w", ru: "Маркеры /100сл"),
                tip: SpeechMetricTips.axisMarkers(phrases: profile.markerPhrases),
                actual: result.actualMarkerRatePer100Words,
                target: String(format: "→ ≥ %.0f", profile.targetMarkerRatePer100Words),
                format: "%.1f",
                score: result.markerScore
            )
        }
        .padding(.top, 6)
    }

    private func metricRow(
        _ name: String,
        tip: String,
        actual: Double,
        target: String,
        format: String,
        score: Double
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                InfoTip(message: tip, iconSize: .small, iconColor: .secondary)
                Spacer(minLength: 0)
            }
            .frame(width: 170, alignment: .leading)
            Text(String(format: format, actual))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
            // The profile's target for this axis — shows which direction to aim for
            Text(target)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(score / 100), height: 6)
                }
            }
            .frame(height: 6)
            Text("\(Int(score))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(scoreColor(score))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    private func matchVerdict(_ score: Double) -> String {
        switch score {
        case 90...:    return L10n.t(en: "You sound like this style", ru: "Звучишь как этот стиль")
        case 75..<90:  return L10n.t(en: "Close to the style", ru: "Близко к стилю")
        case 50..<75:  return L10n.t(en: "Partial match — room to grow", ru: "Местами совпадает — есть к чему расти")
        case 25..<50:  return L10n.t(en: "Far from the style — lots to do", ru: "Далеко от стиля — много работы")
        default:       return L10n.t(en: "Completely different style", ru: "Совсем другой стиль речи")
        }
    }
}
