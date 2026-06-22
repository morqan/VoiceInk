//
//  SpeechOverviewTab.swift
//  VoiceInk
//
//  "Overview" tab of the Speech analytics page: the daily-training card, the
//  aggregated metric cards (fillers / sentence / anglicisms / smoothness / speed /
//  words / EN-RU / complexity) with period-over-period deltas, and the voice
//  (prosody) cards. All aggregation goes through SpeechAggregates; the parent
//  passes in the current + previous period slices and the cached exercise.
//

import SwiftUI

struct SpeechOverviewTab: View {
    let metrics: [SpeechMetric]
    let previousMetrics: [SpeechMetric]
    let exercise: DailyExercise?
    let todaysLatest: SpeechMetric?
    let profile: VoiceProfileTarget?
    let onOpenDetail: (SpeechMetric) -> Void

    var body: some View {
        dailyTraining
        if metrics.isEmpty {
            SpeechEmptyState()
        } else {
            aggregatedMetrics
            prosodySection
        }
    }

    // MARK: - Daily training (exercise of the day)

    /// Exercise-of-the-day card. Scores today's dictation against today's targets;
    /// «Analyze in detail» opens the existing drill-down (where the style rewrite lives).
    @ViewBuilder
    private var dailyTraining: some View {
        if let exercise {
            DailyTrainingCard(
                exercise: exercise,
                latestMetric: todaysLatest,
                profile: profile,
                onOpenDetail: onOpenDetail
            )
        }
    }

    // MARK: - Aggregated metrics

    private var aggregatedMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            SpeechStatCard(
                title: L10n.t(en: "Fillers", ru: "Паразиты"),
                value: String(format: "%.1f", aggFillerRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 2", ru: "Цель ≤ 2"),
                color: SpeechMetricThresholds.fillerBand(rate: aggFillerRate, wordCount: aggWordCount),
                icon: "text.bubble",
                tip: SpeechMetricTips.fillers,
                delta: delta(SpeechAggregates.fillerRate).map { SpeechCardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Avg sentence", ru: "Длина предложения"),
                value: String(format: "%.0f", aggSentenceLength),
                unit: L10n.t(en: "words", ru: "слов"),
                detail: L10n.t(en: "Target ≤ 18", ru: "Цель ≤ 18"),
                color: SpeechMetricThresholds.sentenceBand(length: aggSentenceLength, wordCount: aggWordCount),
                icon: "text.alignleft",
                tip: SpeechMetricTips.sentenceLength,
                delta: delta(SpeechAggregates.sentenceLength).map { d in
                    // "Better" = closer to the active style's target (for Erickson, longer is good)
                    let target = profile?.targetSentenceLength ?? 18
                    let improved = abs(SpeechAggregates.sentenceLength(metrics) - target)
                        < abs(SpeechAggregates.sentenceLength(previousMetrics) - target)
                    return SpeechCardDelta(value: d, format: "%.0f", improved: improved)
                }
            )
            SpeechStatCard(
                title: L10n.t(en: "Anglicisms", ru: "Англицизмы"),
                value: String(format: "%.1f", aggAnglicismRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 1", ru: "Цель ≤ 1"),
                color: SpeechMetricThresholds.anglicismBand(rate: aggAnglicismRate, wordCount: aggWordCount),
                icon: "globe",
                tip: SpeechMetricTips.anglicisms,
                delta: delta(SpeechAggregates.anglicismRate).map { SpeechCardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Smoothness", ru: "Гладкость"),
                value: String(format: "%.1f", aggSelfCorrectionRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Self-corrections", ru: "Самоисправления"),
                color: SpeechMetricThresholds.smoothnessBand(rate: aggSelfCorrectionRate, wordCount: aggWordCount),
                icon: "pencil.and.scribble",
                tip: SpeechMetricTips.smoothness,
                delta: delta(SpeechAggregates.selfCorrectionRate).map { SpeechCardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Speed", ru: "Темп"),
                value: String(format: "%.0f", aggWPM),
                unit: "WPM",
                detail: wpmDetail,
                color: .blue,
                icon: "speedometer",
                tip: SpeechMetricTips.wpm,
                delta: delta(SpeechAggregates.wpm).map { SpeechCardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Total words", ru: "Всего слов"),
                value: "\(aggWordCount)",
                unit: "",
                detail: L10n.t(en: "in this period", ru: "за период"),
                color: .indigo,
                icon: "text.alignleft",
                tip: SpeechMetricTips.totalWords,
                delta: delta({ Double(SpeechAggregates.wordCount($0)) }).map { SpeechCardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            SpeechStatCard(
                title: L10n.t(en: "EN / RU ratio", ru: "EN / RU"),
                value: String(format: "%.0f%%", aggEnRatio * 100),
                unit: "",
                detail: L10n.t(en: "English chars share", ru: "Доля латинских букв"),
                color: .pink,
                icon: "character.textbox",
                tip: SpeechMetricTips.enRuRatio,
                delta: delta({ SpeechAggregates.enRatio($0) * 100 }).map { SpeechCardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Complexity", ru: "Сложность"),
                value: String(format: "%.1f", aggComplexity),
                unit: "",
                detail: L10n.t(en: "Subordinations per sentence", ru: "Подчинения в предложении"),
                color: .teal,
                icon: "arrow.triangle.branch",
                tip: SpeechMetricTips.complexity,
                delta: delta(SpeechAggregates.complexity).map { SpeechCardDelta(value: $0, format: "%.1f", improved: nil) }
            )
        }
    }

    private var aggWordCount: Int { SpeechAggregates.wordCount(metrics) }
    private var aggFillerRate: Double { SpeechAggregates.fillerRate(metrics) }
    private var aggAnglicismRate: Double { SpeechAggregates.anglicismRate(metrics) }
    private var aggSelfCorrectionRate: Double { SpeechAggregates.selfCorrectionRate(metrics) }
    private var aggSentenceLength: Double { SpeechAggregates.sentenceLength(metrics) }
    private var aggWPM: Double { SpeechAggregates.wpm(metrics) }
    private var aggEnRatio: Double { SpeechAggregates.enRatio(metrics) }
    private var aggComplexity: Double { SpeechAggregates.complexity(metrics) }

    /// Delta versus the previous window; nil when there is no prior data.
    private func delta(_ value: ([SpeechMetric]) -> Double) -> Double? {
        guard !previousMetrics.isEmpty else { return nil }
        return value(metrics) - value(previousMetrics)
    }

    /// Subtitle for the "Speed" card: the active style's target plus direction, or "average pace".
    private var wpmDetail: String {
        guard let target = profile?.targetWPM, aggWPM > 0 else {
            return L10n.t(en: "Avg speaking pace", ru: "Средний темп речи")
        }
        let dir = aggWPM < target - 5
            ? L10n.t(en: "speak faster", ru: "быстрее")
            : (aggWPM > target + 5 ? L10n.t(en: "slow down", ru: "медленнее") : L10n.t(en: "on target", ru: "в цели"))
        return L10n.t(
            en: "Target \(Int(target)) · \(dir)",
            ru: "Цель \(Int(target)) · \(dir)"
        )
    }

    // MARK: - Prosody (voice)

    /// Period metrics that already have prosody numbers (audio still on disk).
    private var prosodyMetrics: [SpeechMetric] {
        metrics.filter { $0.prosodyAnalyzed }
    }

    /// Voice/prosody cards — shown only once at least one dictation has been analysed.
    @ViewBuilder
    private var prosodySection: some View {
        if !prosodyMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    LocalizedText(en: "Voice (prosody)", ru: "Голос (просодика)")
                        .font(.system(size: 16, weight: .bold))
                    InfoTip(message: SpeechMetricTips.prosody, iconSize: .small, iconColor: .secondary)
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    SpeechStatCard(
                        title: L10n.t(en: "Expressiveness", ru: "Выразительность"),
                        value: String(format: "%.1f", avgPitchRange),
                        unit: L10n.t(en: "st", ru: "пт"),
                        detail: L10n.t(en: "F0 range", ru: "Разброс тона"),
                        color: .purple,
                        icon: "waveform.path",
                        tip: SpeechMetricTips.expressiveness,
                        delta: nil
                    )
                    SpeechStatCard(
                        title: L10n.t(en: "Pauses", ru: "Паузы"),
                        value: String(format: "%.0f", avgPauseRatio),
                        unit: "%",
                        detail: L10n.t(en: "of speaking time", ru: "от времени речи"),
                        color: .teal,
                        icon: "pause.circle",
                        tip: SpeechMetricTips.pauses,
                        delta: nil
                    )
                    SpeechStatCard(
                        title: L10n.t(en: "Dynamics", ru: "Динамика"),
                        value: String(format: "%.0f", avgLoudnessRange),
                        unit: "dB",
                        detail: L10n.t(en: "loudness spread", ru: "разброс громкости"),
                        color: .mint,
                        icon: "speaker.wave.3",
                        tip: SpeechMetricTips.dynamics,
                        delta: nil
                    )
                }
            }
        }
    }

    private var avgPitchRange: Double { meanOf(prosodyMetrics.map { $0.pitchRangeSemitones }.filter { $0 > 0 }) }
    private var avgPauseRatio: Double { meanOf(prosodyMetrics.map { $0.pauseRatioPercent }) }
    private var avgLoudnessRange: Double { meanOf(prosodyMetrics.map { $0.loudnessRangeDb }.filter { $0 > 0 }) }
    private func meanOf(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
}
