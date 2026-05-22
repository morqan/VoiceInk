//
//  SpeechInsightsSection.swift
//  VoiceInk
//
//  блок на Dashboard со сводкой речевых метрик за сегодня.
//  Считает: filler rate, средняя длина предложения, anglicism rate, средний WPM.
//
//  Цвета карточек:
//   🟢 — в цели
//   🟡 — близко к границе
//   🔴 — выше порога
//

import SwiftUI
import SwiftData

struct SpeechInsightsSection: View {
    /// Все метрики — фильтруем по сегодня в памяти
    /// (SwiftData @Predicate macro не умеет Calendar.startOfDay).
    @Query(sort: \SpeechMetric.timestamp, order: .reverse) private var allMetrics: [SpeechMetric]

    private var todayMetrics: [SpeechMetric] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return allMetrics.filter { $0.timestamp >= startOfDay }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if todayMetrics.isEmpty {
                emptyState
            } else {
                metricsGrid
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
            Text("Speech Today")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            Spacer()
            if !todayMetrics.isEmpty {
                Text("\(todayMetrics.count) session\(todayMetrics.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No dictations today yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Speech metrics will appear after your first dictation ≥ 15 words")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            SpeechMetricCard(
                icon: "text.bubble",
                title: "Fillers",
                value: String(format: "%.1f", avgFillerRate),
                unit: "/ 100 words",
                detail: "Target ≤ 2",
                color: fillerColor
            )

            SpeechMetricCard(
                icon: "text.alignleft",
                title: "Avg sentence",
                value: String(format: "%.0f", avgSentenceLength),
                unit: "words",
                detail: "Target ≤ 18",
                color: sentenceColor
            )

            SpeechMetricCard(
                icon: "globe",
                title: "Anglicisms",
                value: String(format: "%.1f", avgAnglicismRate),
                unit: "/ 100 words",
                detail: "Target ≤ 1",
                color: anglicismColor
            )

            SpeechMetricCard(
                icon: "speedometer",
                title: "Speed",
                value: String(format: "%.0f", avgWPM),
                unit: "WPM",
                detail: averageWPMDetail,
                color: .blue
            )

            SpeechMetricCard(
                icon: "character.textbox",
                title: "EN / RU ratio",
                value: String(format: "%.0f", avgEnRuRatio * 100),
                unit: "%",
                detail: "English chars share",
                color: .pink
            )
        }
    }

    // MARK: - Computed

    private var totalWords: Int {
        todayMetrics.reduce(0) { $0 + $1.wordCount }
    }

    private var totalFillers: Int {
        todayMetrics.reduce(0) { $0 + $1.fillerCount }
    }

    private var totalAnglicisms: Int {
        todayMetrics.reduce(0) { $0 + $1.anglicismCount }
    }

    /// Средний filler rate (взвешенный по словам, не по сессиям)
    private var avgFillerRate: Double {
        guard totalWords > 0 else { return 0 }
        return Double(totalFillers) / Double(totalWords) * 100
    }

    private var avgAnglicismRate: Double {
        guard totalWords > 0 else { return 0 }
        return Double(totalAnglicisms) / Double(totalWords) * 100
    }

    /// Средняя длина предложения (взвешенная)
    private var avgSentenceLength: Double {
        let totalSentences = todayMetrics.reduce(0) { $0 + $1.sentenceCount }
        guard totalSentences > 0 else { return 0 }
        return Double(totalWords) / Double(totalSentences)
    }

    /// Средний WPM (среднее арифметическое по сессиям где WPM > 0)
    private var avgWPM: Double {
        let valid = todayMetrics.filter { $0.wpm > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.wpm } / Double(valid.count)
    }

    /// Средняя доля латинских символов
    private var avgEnRuRatio: Double {
        guard !todayMetrics.isEmpty else { return 0 }
        return todayMetrics.reduce(0) { $0 + $1.enRuRatio } / Double(todayMetrics.count)
    }

    private var averageWPMDetail: String {
        if avgWPM == 0 { return "—" }
        // Подкастер ~150 WPM, твоё среднее VoiceInk 88.7
        if avgWPM < 80 { return "Slower than average" }
        if avgWPM < 140 { return "Conversational pace" }
        return "Fast pace"
    }

    // MARK: - Color thresholds

    private var fillerColor: Color {
        if totalWords == 0 { return .secondary }
        if avgFillerRate <= 2 { return .green }
        if avgFillerRate <= 4 { return .orange }
        return .red
    }

    private var sentenceColor: Color {
        if totalWords == 0 { return .secondary }
        if avgSentenceLength <= 18 { return .green }
        if avgSentenceLength <= 25 { return .orange }
        return .red
    }

    private var anglicismColor: Color {
        if totalWords == 0 { return .secondary }
        if avgAnglicismRate <= 1 { return .green }
        if avgAnglicismRate <= 3 { return .orange }
        return .red
    }
}

/// Карточка одной метрики речи. Похожа на MetricCard, но с unit и более компактная.
private struct SpeechMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let detail: String
    let color: Color

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
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
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
}
