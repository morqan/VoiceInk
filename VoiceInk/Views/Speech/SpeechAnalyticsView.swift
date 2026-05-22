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
    case today
    case week
    case month
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return L10n.t(en: "Today", ru: "Сегодня")
        case .week:  return L10n.t(en: "Week", ru: "Неделя")
        case .month: return L10n.t(en: "Month", ru: "Месяц")
        case .all:   return L10n.t(en: "All", ru: "Всё")
        }
    }

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
                    VoiceProfileSection(metrics: filteredMetrics)
                    streaksSection
                    if period != .today {
                        trendCharts
                    }
                    topFillers
                    topAnglicisms
                    topRepetitions
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
                    LocalizedText(en: "Speech Analytics", ru: "Аналитика речи")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    LocalizedText(
                        en: "Track your speech patterns and improve over time",
                        ru: "Отслеживай паттерны речи и улучшайся со временем"
                    )
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
                    Text(p.displayName)
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
            Text(L10n.t(
                en: "\(filteredMetrics.count) session\(filteredMetrics.count == 1 ? "" : "s")",
                ru: "\(filteredMetrics.count) \(filteredMetrics.count == 1 ? "сессия" : "сессий")"
            ))
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
            LocalizedText(
                en: "No dictations in this period yet",
                ru: "В этом периоде ещё нет диктовок"
            )
                .font(.system(size: 15, weight: .semibold))
            LocalizedText(
                en: "Speech metrics are recorded after each dictation ≥ 15 words",
                ru: "Метрики записываются после каждой диктовки ≥ 15 слов"
            )
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
                title: L10n.t(en: "Fillers", ru: "Паразиты"),
                value: String(format: "%.1f", aggFillerRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 2", ru: "Цель ≤ 2"),
                color: fillerColor(aggFillerRate),
                icon: "text.bubble"
            )
            statCard(
                title: L10n.t(en: "Avg sentence", ru: "Длина предложения"),
                value: String(format: "%.0f", aggSentenceLength),
                unit: L10n.t(en: "words", ru: "слов"),
                detail: L10n.t(en: "Target ≤ 18", ru: "Цель ≤ 18"),
                color: sentenceColor(aggSentenceLength),
                icon: "text.alignleft"
            )
            statCard(
                title: L10n.t(en: "Anglicisms", ru: "Англицизмы"),
                value: String(format: "%.1f", aggAnglicismRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 1", ru: "Цель ≤ 1"),
                color: anglicismColor(aggAnglicismRate),
                icon: "globe"
            )
            statCard(
                title: L10n.t(en: "Speed", ru: "Темп"),
                value: String(format: "%.0f", aggWPM),
                unit: "WPM",
                detail: L10n.t(en: "Avg speaking pace", ru: "Средний темп речи"),
                color: .blue,
                icon: "speedometer"
            )
            statCard(
                title: L10n.t(en: "Total words", ru: "Всего слов"),
                value: "\(aggWordCount)",
                unit: "",
                detail: L10n.t(en: "in this period", ru: "за период"),
                color: .indigo,
                icon: "text.alignleft"
            )
            statCard(
                title: L10n.t(en: "EN / RU ratio", ru: "EN / RU"),
                value: String(format: "%.0f%%", aggEnRatio * 100),
                unit: "",
                detail: L10n.t(en: "English chars share", ru: "Доля латинских букв"),
                color: .pink,
                icon: "character.textbox"
            )

            statCard(
                title: L10n.t(en: "Complexity", ru: "Сложность"),
                value: String(format: "%.1f", aggComplexity),
                unit: "",
                detail: L10n.t(en: "Subordinations per sentence", ru: "Подчинения в предложении"),
                color: .teal,
                icon: "arrow.triangle.branch"
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
            LocalizedText(en: "Trends", ru: "Тренды")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            HStack(alignment: .top, spacing: 12) {
                chartCard(
                    title: "WPM",
                    series: dailySeries(\.wpm, average: true),
                    color: .blue,
                    yAxisLabel: "WPM"
                )
                chartCard(
                    title: L10n.t(en: "Fillers / 100 words", ru: "Паразиты / 100 слов"),
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
                LocalizedText(en: "Not enough data", ru: "Недостаточно данных")
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
            LocalizedText(en: "Top fillers", ru: "Топ паразитов")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            if topFillerList.isEmpty {
                LocalizedText(en: "No fillers detected — well done!", ru: "Паразитов нет — молодец!")
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
            LocalizedText(en: "Top anglicisms", ru: "Топ англицизмов")
                .font(.system(size: 16, weight: .heavy, design: .rounded))

            if topAnglicismList.isEmpty {
                LocalizedText(en: "No anglicisms detected", ru: "Англицизмов не обнаружено")
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

    // MARK: - Streaks

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                LocalizedText(en: "Streaks", ru: "Стрики")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                LocalizedText(
                    en: "(consecutive days under the target)",
                    ru: "(дней подряд под целью)"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                streakCard(
                    title: L10n.t(en: "Filler-free", ru: "Без паразитов"),
                    value: fillerStreak,
                    subtitle: L10n.t(en: "≤ 2 / 100 words", ru: "≤ 2 / 100 слов"),
                    color: .orange,
                    icon: "text.bubble"
                )
                streakCard(
                    title: L10n.t(en: "Anglicism-free", ru: "Без англицизмов"),
                    value: anglicismStreak,
                    subtitle: L10n.t(en: "≤ 1 / 100 words", ru: "≤ 1 / 100 слов"),
                    color: .pink,
                    icon: "globe"
                )
                streakCard(
                    title: L10n.t(en: "Short sentences", ru: "Короткие предложения"),
                    value: sentenceStreak,
                    subtitle: L10n.t(en: "≤ 18 words", ru: "≤ 18 слов"),
                    color: .green,
                    icon: "text.alignleft"
                )
            }
        }
    }

    private func streakCard(
        title: String,
        value: Int,
        subtitle: String,
        color: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(color)
                    Text(daysLabel(for: value))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    if value >= 7 {
                        Text("🔥")
                            .font(.system(size: 14))
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Streak calculation

    /// Группирует ВСЕ metrics (не filtered) по дням, считает streak с сегодня назад.
    /// Streak ломается на первом дне с данными где criteria failed.
    /// Дни без данных пропускаются (не ломают streak).
    private func computeStreak(
        passedCheck: (Int /* fillers */, Int /* anglicisms */, Int /* words */, Double /* avgSentenceLength */) -> Bool
    ) -> Int {
        let cal = Calendar.current
        // Группируем все metrics по дням
        var byDay: [Date: (fillers: Int, anglicisms: Int, words: Int, sentenceLengthSum: Double, sentenceCount: Int)] = [:]
        for m in allMetrics {
            let day = cal.startOfDay(for: m.timestamp)
            var d = byDay[day, default: (0, 0, 0, 0, 0)]
            d.fillers += m.fillerCount
            d.anglicisms += m.anglicismCount
            d.words += m.wordCount
            d.sentenceLengthSum += m.avgSentenceLength
            d.sentenceCount += 1
            byDay[day] = d
        }

        guard !byDay.isEmpty else { return 0 }

        // Идём с сегодня назад
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        let earliest = byDay.keys.min() ?? cursor

        while cursor >= earliest {
            if let d = byDay[cursor] {
                let avgSentence = d.sentenceCount > 0 ? d.sentenceLengthSum / Double(d.sentenceCount) : 0
                if passedCheck(d.fillers, d.anglicisms, d.words, avgSentence) {
                    streak += 1
                } else {
                    break
                }
            }
            // День без данных — пропускаем, не ломаем streak
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? earliest
        }
        return streak
    }

    /// Корректная форма «день/дня/дней» с учётом языка.
    private func daysLabel(for value: Int) -> String {
        if L10n.current == .english {
            return value == 1 ? "day" : "days"
        }
        if value == 1 { return "день" }
        if value > 1 && value < 5 { return "дня" }
        return "дней"
    }

    private var fillerStreak: Int {
        computeStreak { fillers, _, words, _ in
            guard words > 0 else { return false }
            return Double(fillers) / Double(words) * 100 <= 2.0
        }
    }

    private var anglicismStreak: Int {
        computeStreak { _, anglicisms, words, _ in
            guard words > 0 else { return false }
            return Double(anglicisms) / Double(words) * 100 <= 1.0
        }
    }

    private var sentenceStreak: Int {
        computeStreak { _, _, words, avgSentence in
            guard words > 0 else { return false }
            return avgSentence <= 18.0
        }
    }

    // MARK: - Top repetitions

    private var topRepetitions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                LocalizedText(en: "Top repeated words", ru: "Топ повторяющихся слов")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                LocalizedText(
                    en: "(≥ 5 times in one dictation)",
                    ru: "(≥ 5 раз в одной диктовке)"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if topRepetitionList.isEmpty {
                LocalizedText(en: "No word over-repetition detected", ru: "Повторов не обнаружено")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(topRepetitionList.prefix(10), id: \.word) { item in
                        wordCountRow(item.word, count: item.count, color: .purple)
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

    // MARK: - Recent sessions

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            LocalizedText(en: "Recent sessions", ru: "Недавние сессии")
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
                if metric.repetitionCount > 0 {
                    metricBadge("\(metric.repetitionCount)rep", color: .purple)
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

    private var aggComplexity: Double {
        let valid = filteredMetrics.filter { $0.avgSentenceComplexity > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.avgSentenceComplexity } / Double(valid.count)
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

    private var topRepetitionList: [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in filteredMetrics {
            for (word, count) in metric.repetitionsByWord {
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
