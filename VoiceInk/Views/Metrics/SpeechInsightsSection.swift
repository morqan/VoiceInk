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
    /// Recent metrics only — the DB fetch is capped to a short window so this
    /// always-visible Dashboard block never materializes the whole history. "Today"
    /// is filtered in memory (the @Predicate macro can't call Calendar.startOfDay),
    /// so it still rolls over correctly at midnight. The window is wider than a day
    /// so a session left open past midnight keeps showing the new day's data.
    @Query private var recentMetrics: [SpeechMetric]

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date.distantPast
        _recentMetrics = Query(
            filter: #Predicate { $0.timestamp >= cutoff },
            sort: [SortDescriptor(\SpeechMetric.timestamp, order: .reverse)]
        )
    }

    private var todayMetrics: [SpeechMetric] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return recentMetrics.filter { $0.timestamp >= startOfDay }
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
            LocalizedText(en: "Speech Today", ru: "Речь сегодня")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            Spacer()
            if !todayMetrics.isEmpty {
                Text(L10n.sessionsCount(todayMetrics.count))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            openAnalyticsButton
        }
    }

    /// Переход на полную страницу Speech Analytics — блок не должен быть тупиком.
    private var openAnalyticsButton: some View {
        Button {
            NotificationCenter.default.post(
                name: .navigateToDestination,
                object: nil,
                userInfo: ["destination": "Speech"]
            )
        } label: {
            HStack(spacing: 4) {
                Text(L10n.t(en: "Open analytics", ru: "Открыть аналитику"))
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                LocalizedText(en: "No dictations today yet", ru: "Сегодня ещё нет диктовок")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                LocalizedText(
                    en: "Speech metrics will appear after your first dictation ≥ 15 words",
                    ru: "Метрики появятся после первой диктовки ≥ 15 слов"
                )
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
                title: L10n.t(en: "Fillers", ru: "Паразиты"),
                value: String(format: "%.1f", avgFillerRate),
                unit: L10n.t(en: "/ 100 words", ru: "/ 100 слов"),
                detail: L10n.t(en: "Target ≤ 2", ru: "Цель ≤ 2"),
                color: fillerColor,
                tip: SpeechMetricTips.fillers
            )

            SpeechMetricCard(
                icon: "text.alignleft",
                title: L10n.t(en: "Avg sentence", ru: "Длина предл."),
                value: String(format: "%.0f", avgSentenceLength),
                unit: L10n.t(en: "words", ru: "слов"),
                detail: L10n.t(en: "Target ≤ 18", ru: "Цель ≤ 18"),
                color: sentenceColor,
                tip: SpeechMetricTips.sentenceLength
            )

            SpeechMetricCard(
                icon: "globe",
                title: L10n.t(en: "Anglicisms", ru: "Англицизмы"),
                value: String(format: "%.1f", avgAnglicismRate),
                unit: L10n.t(en: "/ 100 words", ru: "/ 100 слов"),
                detail: L10n.t(en: "Target ≤ 1", ru: "Цель ≤ 1"),
                color: anglicismColor,
                tip: SpeechMetricTips.anglicisms
            )

            SpeechMetricCard(
                icon: "speedometer",
                title: L10n.t(en: "Speed", ru: "Темп"),
                value: String(format: "%.0f", avgWPM),
                unit: "WPM",
                detail: averageWPMDetail,
                color: .blue,
                tip: SpeechMetricTips.wpm
            )

            SpeechMetricCard(
                icon: "character.textbox",
                title: L10n.t(en: "EN / RU ratio", ru: "EN / RU"),
                value: String(format: "%.0f", avgEnRuRatio * 100),
                unit: "%",
                detail: L10n.t(en: "English chars share", ru: "Доля латинских букв"),
                color: .pink,
                tip: SpeechMetricTips.enRuRatio
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

    /// WPM — pooled: слова дня ÷ суммарное время записей дня
    /// (невзвешенное среднее по сессиям давало короткой реплике вес длинной диктовки).
    private var avgWPM: Double {
        let timed = todayMetrics.filter { $0.durationSeconds > 0 && $0.wordCount > 0 }
        let minutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        guard minutes > 0 else { return 0 }
        return Double(timed.reduce(0) { $0 + $1.wordCount }) / minutes
    }

    /// Доля латинских символов — взвешенно по словам сессий
    private var avgEnRuRatio: Double {
        guard totalWords > 0 else { return 0 }
        return todayMetrics.reduce(0.0) { $0 + $1.enRuRatio * Double($1.wordCount) } / Double(totalWords)
    }

    private var averageWPMDetail: String {
        if avgWPM == 0 { return "—" }
        if avgWPM < 80 { return L10n.t(en: "Slower than average", ru: "Медленнее среднего") }
        if avgWPM < 140 { return L10n.t(en: "Conversational pace", ru: "Разговорный темп") }
        return L10n.t(en: "Fast pace", ru: "Быстрый темп")
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
    var tip: String? = nil

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
