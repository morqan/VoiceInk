//
//  DailyTrainingCard.swift
//  VoiceInk
//
//  "Exercise of the day" card on the Speech page: shows today's speaking prompt,
//  the target marker phrases to weave in, and the target pace. After the user
//  dictates on the topic (normal hotkey), it scores their latest dictation against
//  those targets. The "style ideal" rewrite lives in the existing drill-down — the
//  "Analyze in detail" button just opens it, so nothing blocks or auto-waits.
//

import SwiftUI

struct DailyTrainingCard: View {
    let exercise: DailyExercise
    let latestMetric: SpeechMetric?
    let profile: VoiceProfileTarget?
    /// Opens the latest dictation in the drill-down (where the style rewrite lives).
    let onOpenDetail: (SpeechMetric) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            topicBlock
            if !exercise.targetPhrases.isEmpty {
                targetPhrasesBlock
            }
            Divider().opacity(0.4)
            if let latestMetric {
                scorecard(for: latestMetric)
            } else {
                hint
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            LocalizedText(en: "Daily training", ru: "Тренировка дня")
                .font(.system(size: 15, weight: .bold))
            Spacer()
            if exercise.hasProfile, let profile {
                Text(profile.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            InfoTip(message: SpeechMetricTips.dailyTraining, iconSize: .small, iconColor: .secondary)
        }
    }

    // MARK: - Topic

    private var topicBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            LocalizedText(en: "Today's topic", ru: "Тема дня")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(exercise.topic)
                .font(.system(size: 16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t(
                en: "Target pace ≈ \(Int(exercise.targetWPM)) WPM",
                ru: "Целевой темп ≈ \(Int(exercise.targetWPM)) сл/мин"
            ))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Target phrases

    private var targetPhrasesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(en: "Weave in these phrases", ru: "Вплети эти фразы")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            FlowLayout(spacing: 6) {
                ForEach(exercise.targetPhrases, id: \.self) { phrase in
                    phraseChip(phrase)
                }
            }
        }
    }

    private func phraseChip(_ phrase: String) -> some View {
        let hit = latestMetric.map { phraseHit(phrase, in: $0) } ?? false
        return HStack(spacing: 4) {
            Image(systemName: hit ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(hit ? Color.green : Color.secondary)
            Text("«\(phrase)»")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((hit ? Color.green : Color.secondary).opacity(0.12))
        )
    }

    // MARK: - Scorecard

    private func scorecard(for metric: SpeechMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LocalizedText(en: "Your latest take", ru: "Твоя последняя попытка")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onOpenDetail(metric)
                } label: {
                    HStack(spacing: 4) {
                        LocalizedText(en: "Analyze in detail", ru: "Разобрать детально")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 10) {
                scoreChip(
                    title: L10n.t(en: "Pace", ru: "Темп"),
                    value: "\(Int(metric.wpm))",
                    color: paceColor(metric.wpm),
                    arrow: paceArrow(metric.wpm)
                )
                scoreChip(
                    title: L10n.t(en: "Fillers", ru: "Паразиты"),
                    value: String(format: "%.1f", metric.fillerRatePer100Words),
                    color: metric.fillerRatePer100Words <= 2 ? .green : (metric.fillerRatePer100Words <= 4 ? .orange : .red),
                    arrow: nil
                )
                scoreChip(
                    title: L10n.t(en: "Smoothness", ru: "Гладкость"),
                    value: String(format: "%.1f", metric.selfCorrectionRatePer100Words),
                    color: metric.selfCorrectionRatePer100Words <= 1 ? .green : (metric.selfCorrectionRatePer100Words <= 3 ? .orange : .red),
                    arrow: nil
                )
                if let score = matchScore(for: metric) {
                    scoreChip(
                        title: L10n.t(en: "Match", ru: "Совпадение"),
                        value: "\(Int(score))",
                        color: score >= 70 ? .green : (score >= 45 ? .orange : .red),
                        arrow: nil
                    )
                }
            }
        }
    }

    private func scoreChip(title: String, value: String, color: Color, arrow: String?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                if let arrow {
                    Image(systemName: arrow)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            LocalizedText(
                en: "Dictate on this topic with your hotkey — the breakdown shows up here.",
                ru: "Продиктуй на эту тему своим хоткеем — разбор появится здесь."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func phraseHit(_ phrase: String, in metric: SpeechMetric) -> Bool {
        let source = metric.rawText.isEmpty ? metric.text : metric.rawText
        return PhraseOccurrenceScanner.totalCount(of: [phrase], in: source) > 0
    }

    private func matchScore(for metric: SpeechMetric) -> Double? {
        guard let profile else { return nil }
        return VoiceProfileMatcher.compute(target: profile, metrics: [metric])?.totalScore
    }

    private func paceArrow(_ wpm: Double) -> String? {
        if wpm < exercise.targetWPM - 5 { return "arrow.up" }      // speak faster
        if wpm > exercise.targetWPM + 5 { return "arrow.down" }    // slow down
        return "checkmark"
    }

    private func paceColor(_ wpm: Double) -> Color {
        abs(wpm - exercise.targetWPM) <= 10 ? .green : .orange
    }
}
