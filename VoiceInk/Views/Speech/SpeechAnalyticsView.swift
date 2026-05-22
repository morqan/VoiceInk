//
//  SpeechAnalyticsView.swift
//  VoiceInk
//
//  полная аналитика речи.
//
//  Включает:
//   - Period selector (Today / Week / Month)
//   - 4 агрегированные метрики (filler / sentence / anglicism / WPM)
//   - Графики тренда за 30 дней (WPM, filler rate)
//   - Top fillers — таблица
//   - Top anglicisms — таблица
//   - Recent sessions — последние диктовки
//

import SwiftUI
import SwiftData
import Charts

enum SpeechPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case all = "All"

    var id: String { rawValue }

    /// Начало периода. Возвращает nil для .all (без фильтра).
    func startDate(now: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: now)
        case .week:  return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))
        case .month: return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))
        case .all:   return nil
        }
    }
}

struct SpeechAnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var period: SpeechPeriod = .week
    @Query(sort: \SpeechMetric.timestamp, order: .reverse) private var allMetrics: [SpeechMetric]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                periodSelector

                if filteredMetrics.isEmpty {
                    emptyState
                } else {
                    aggregatedMetrics
                    if period != .today {
                        trendCharts
                    }
                    topFillers
                    topAnglicisms
                    recentSessions
                }
            }
            .padding(28)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech Analytics")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Track your speech patterns and improve over time")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Period selector

    private var periodSelector: some View {
        HStack(spacing: 8) {
            ForEach(SpeechPeriod.allCases) { p in
                Button {
                    period = p
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(period == p ? Color.accentColor : Color.gray.opacity(0.15))
                        )
                        .foregroundColor(period == p ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(filteredMetrics.count) session\(filteredMetrics.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No dictations in this period yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Speech metrics are recorded after each dictation ≥ 15 words")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Aggregated metrics

    private var aggregatedMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            statCard(
                title: "Fillers",
                value: String(format: "%.1f", aggFillerRate),
                unit: "/100w",
                detail: "Target ≤ 2",
                color: fillerColor(aggFillerRate),
                icon: "text.bubble"
            )
            statCard(
                title: "Avg sentence",
                value: String(format: "%.0f", aggSentenceLength),
                unit: "words",
                detail: "Target ≤ 18",
                color: sentenceColor(aggSentenceLength),
                icon: "text.alignleft"
            )
            statCard(
                title: "Anglicisms",
                value: String(format: "%.1f", aggAnglicismRate),
                unit: "/100w",
                detail: "Target ≤ 1",
                color: anglicismColor(aggAnglicismRate),
                icon: "globe"
            )
            statCard(
                title: "Speed",
                value: String(format: "%.0f", aggWPM),
                unit: "WPM",
                detail: "Avg speaking pace",
                color: .blue,
                icon: "speedometer"
            )
            statCard(
                title: "Total words",
                value: "\(aggWordCount)",
                unit: "",
                detail: "in this period",
                color: .indigo,
                icon: "text.alignleft"
            )
            statCard(
                title: "EN / RU ratio",
                value: String(format: "%.0f%%", aggEnRatio * 100),
                unit: "",
                detail: "English chars share",
                color: .pink,
                icon: "character.textbox"
            )
        }
    }

    private func statCard(
        title: String,
        value: String,
        unit: String,
        detail: String,
        color: Color,
        icon: String
    ) -> some View {
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
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
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

    // MARK: - Charts (Stage 4)

    private var trendCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trends")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            HStack(alignment: .top, spacing: 12) {
                chartCard(
                    title: "WPM",
                    series: dailySeries(\.wpm, average: true),
                    color: .blue,
                    yAxisLabel: "WPM"
                )
                chartCard(
                    title: "Fillers / 100 words",
                    series: dailyFillerRateSeries,
                    color: .orange,
                    yAxisLabel: "rate"
                )
            }
        }
    }

    private func chartCard(
        title: String,
        series: [(date: Date, value: Double)],
        color: Color,
        yAxisLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            if series.isEmpty {
                Text("Not enough data")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(series, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                    }
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, series.count / 5))) { value in
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

    // MARK: - Top fillers

    private var topFillers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top fillers")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            if topFillerList.isEmpty {
                Text("No fillers detected — well done!")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(topFillerList.prefix(10), id: \.word) { item in
                        wordCountRow(item.word, count: item.count, color: .orange)
                    }
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

    // MARK: - Top anglicisms

    private var topAnglicisms: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top anglicisms")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            if topAnglicismList.isEmpty {
                Text("No anglicisms detected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(topAnglicismList.prefix(10), id: \.word) { item in
                        wordCountRow(item.word, count: item.count, color: .pink)
                    }
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

    private func wordCountRow(_ word: String, count: Int, color: Color) -> some View {
        HStack {
            Text(word)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
            Spacer()
            Text("\(count)×")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
    }

    // MARK: - Recent sessions

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sessions")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            VStack(spacing: 6) {
                ForEach(filteredMetrics.prefix(15)) { metric in
                    sessionRow(metric)
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
                metricBadge("\(metric.wordCount)w", color: .secondary)
                metricBadge(String(format: "%.0f wpm", metric.wpm), color: .blue)
                if metric.fillerCount > 0 {
                    metricBadge("\(metric.fillerCount)f", color: .orange)
                }
                if metric.anglicismCount > 0 {
                    metricBadge("\(metric.anglicismCount)en", color: .pink)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metricBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .foregroundColor(color)
    }

    // MARK: - Filtering

    private var filteredMetrics: [SpeechMetric] {
        guard let start = period.startDate() else { return allMetrics }
        return allMetrics.filter { $0.timestamp >= start }
    }

    // MARK: - Aggregations

    private var aggWordCount: Int {
        filteredMetrics.reduce(0) { $0 + $1.wordCount }
    }

    private var aggFillerCount: Int {
        filteredMetrics.reduce(0) { $0 + $1.fillerCount }
    }

    private var aggAnglicismCount: Int {
        filteredMetrics.reduce(0) { $0 + $1.anglicismCount }
    }

    private var aggFillerRate: Double {
        guard aggWordCount > 0 else { return 0 }
        return Double(aggFillerCount) / Double(aggWordCount) * 100
    }

    private var aggAnglicismRate: Double {
        guard aggWordCount > 0 else { return 0 }
        return Double(aggAnglicismCount) / Double(aggWordCount) * 100
    }

    private var aggSentenceLength: Double {
        let totalSentences = filteredMetrics.reduce(0) { $0 + $1.sentenceCount }
        guard totalSentences > 0 else { return 0 }
        return Double(aggWordCount) / Double(totalSentences)
    }

    private var aggWPM: Double {
        let valid = filteredMetrics.filter { $0.wpm > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.wpm } / Double(valid.count)
    }

    private var aggEnRatio: Double {
        guard !filteredMetrics.isEmpty else { return 0 }
        return filteredMetrics.reduce(0) { $0 + $1.enRuRatio } / Double(filteredMetrics.count)
    }

    private var topFillerList: [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in filteredMetrics {
            for (word, count) in metric.fillersByWord {
                totals[word, default: 0] += count
            }
        }
        return totals.map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var topAnglicismList: [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in filteredMetrics {
            for (word, count) in metric.anglicismsByWord {
                totals[word, default: 0] += count
            }
        }
        return totals.map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Daily series for charts

    /// Группирует filteredMetrics по дням, для каждого дня — среднее значение поля.
    private func dailySeries(_ keyPath: KeyPath<SpeechMetric, Double>, average: Bool) -> [(date: Date, value: Double)] {
        let cal = Calendar.current
        var buckets: [Date: [Double]] = [:]
        for m in filteredMetrics {
            let day = cal.startOfDay(for: m.timestamp)
            buckets[day, default: []].append(m[keyPath: keyPath])
        }
        return buckets
            .map { (date: $0.key, value: average ? ($0.value.reduce(0, +) / Double($0.value.count)) : $0.value.reduce(0, +)) }
            .sorted { $0.date < $1.date }
    }

    /// Daily filler rate (per 100 words) с weighted average.
    private var dailyFillerRateSeries: [(date: Date, value: Double)] {
        let cal = Calendar.current
        var buckets: [Date: (fillers: Int, words: Int)] = [:]
        for m in filteredMetrics {
            let day = cal.startOfDay(for: m.timestamp)
            let prev = buckets[day, default: (0, 0)]
            buckets[day] = (prev.fillers + m.fillerCount, prev.words + m.wordCount)
        }
        return buckets
            .map { day, t -> (Date, Double) in
                let rate = t.words > 0 ? Double(t.fillers) / Double(t.words) * 100 : 0
                return (day, rate)
            }
            .map { (date: $0.0, value: $0.1) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Color thresholds

    private func fillerColor(_ rate: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if rate <= 2 { return .green }
        if rate <= 4 { return .orange }
        return .red
    }

    private func sentenceColor(_ length: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if length <= 18 { return .green }
        if length <= 25 { return .orange }
        return .red
    }

    private func anglicismColor(_ rate: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if rate <= 1 { return .green }
        if rate <= 3 { return .orange }
        return .red
    }
}
