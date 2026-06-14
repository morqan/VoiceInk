//
//  SpeechHistoryTab.swift
//  VoiceInk
//
//  "History" tab of the Speech analytics page: trend charts (WPM, fillers, match score)
//  + the recent-sessions list. Daily WPM/filler series are computed from the passed
//  metrics; the match-score series is precomputed by the parent (off-main) and passed in.
//

import SwiftUI
import Charts

struct SpeechHistoryTab: View {
    let metrics: [SpeechMetric]
    let matchSeries: [(date: Date, value: Double)]
    let showMatchChart: Bool
    let showTrends: Bool
    let onSelect: (SpeechMetric) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showTrends {
                trendCharts
            }
            recentSessions
        }
    }

    // MARK: - Trends

    private var trendCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Trends", ru: "Тренды")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.trends, iconSize: .small, iconColor: .secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                chartCard(title: "WPM", series: dailyWPMSeries, color: .blue, yAxisLabel: "WPM")
                chartCard(
                    title: L10n.t(en: "Fillers / 100 words", ru: "Паразиты / 100 слов"),
                    series: dailyFillerRateSeries,
                    color: .orange,
                    yAxisLabel: "rate",
                    targetLine: 2
                )
            }

            // Style match over time — the trainer's main motivator.
            if showMatchChart {
                chartCard(
                    title: L10n.t(en: "Match Score (style)", ru: "Match Score (стиль)"),
                    series: matchSeries,
                    color: .indigo,
                    yAxisLabel: "score",
                    yDomain: 0...100
                )
            }
        }
    }

    private func chartCard(
        title: String,
        series: [(date: Date, value: Double)],
        color: Color,
        yAxisLabel: String,
        targetLine: Double? = nil,
        yDomain: ClosedRange<Double>? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            if series.isEmpty {
                LocalizedText(en: "Not enough data", ru: "Недостаточно данных")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    if let targetLine {
                        RuleMark(y: .value("Target", targetLine))
                            .foregroundStyle(.green.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(series, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value(yAxisLabel, point.value))
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value(yAxisLabel, point.value))
                            .foregroundStyle(color)
                    }
                }
                .frame(height: 120)
                .modifier(OptionalYDomain(domain: yDomain))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, series.count / 5))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Recent sessions

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Recent sessions", ru: "Недавние сессии")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.recentSessions, iconSize: .small, iconColor: .secondary)
            }

            VStack(spacing: 6) {
                ForEach(metrics.prefix(15)) { metric in
                    Button {
                        onSelect(metric)
                    } label: {
                        sessionRow(metric)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t(en: "Open dictation breakdown", ru: "Открыть разбор диктовки"))
                    .pointingHandCursor()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func sessionRow(_ metric: SpeechMetric) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.text.prefix(80) + (metric.text.count > 80 ? "…" : ""))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(metric.timestamp, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                metricBadge("\(metric.wordCount)w", color: .secondary,
                            help: L10n.t(en: "Words in this dictation", ru: "Слов в диктовке"))
                metricBadge(String(format: "%.0f wpm", metric.wpm), color: .blue,
                            help: L10n.t(en: "Pace, words per minute", ru: "Темп, слов в минуту"))
                if metric.fillerCount > 0 {
                    metricBadge("\(metric.fillerCount)f", color: .orange,
                                help: L10n.t(en: "Filler words found", ru: "Найдено слов-паразитов"))
                }
                if metric.anglicismCount > 0 {
                    metricBadge("\(metric.anglicismCount)en", color: .pink,
                                help: L10n.t(en: "Anglicisms found", ru: "Найдено англицизмов"))
                }
                if metric.repetitionCount > 0 {
                    metricBadge("\(metric.repetitionCount)rep", color: .purple,
                                help: L10n.t(en: "Words repeated ≥ 5 times", ru: "Слов с повторами ≥ 5 раз"))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricBadge(_ text: String, color: Color, help: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
            .help(help)
    }

    // MARK: - Daily series

    private var dailyWPMSeries: [(date: Date, value: Double)] {
        let cal = Calendar.current
        var buckets: [Date: (words: Int, seconds: Double)] = [:]
        for m in metrics where m.durationSeconds > 0 && m.wordCount > 0 {
            let day = cal.startOfDay(for: m.timestamp)
            let prev = buckets[day, default: (0, 0)]
            buckets[day] = (prev.words + m.wordCount, prev.seconds + m.durationSeconds)
        }
        return buckets
            .compactMap { day, t -> (date: Date, value: Double)? in
                guard t.seconds > 0 else { return nil }
                return (date: day, value: Double(t.words) / (t.seconds / 60.0))
            }
            .sorted { $0.date < $1.date }
    }

    private var dailyFillerRateSeries: [(date: Date, value: Double)] {
        let cal = Calendar.current
        var buckets: [Date: (fillers: Int, words: Int)] = [:]
        for m in metrics {
            let day = cal.startOfDay(for: m.timestamp)
            let prev = buckets[day, default: (0, 0)]
            buckets[day] = (prev.fillers + m.fillerCount, prev.words + m.wordCount)
        }
        return buckets
            .map { day, t -> (date: Date, value: Double) in
                let rate = t.words > 0 ? Double(t.fillers) / Double(t.words) * 100 : 0
                return (date: day, value: rate)
            }
            .sorted { $0.date < $1.date }
    }
}

/// Optional fixed Y domain (for Match Score 0–100).
private struct OptionalYDomain: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain {
            content.chartYScale(domain: domain)
        } else {
            content
        }
    }
}
