//
//  VoiceProfileStyleCoachView.swift
//  VoiceInk
//
//  The "How to reach the style" learning block: a lock gate (min sessions / words),
//  a single-suggestion fallback when everything is on target, and the per-axis
//  CoachCards (top 3 by weighted gain) for the active profile.
//

import SwiftUI

struct VoiceProfileStyleCoachView: View {
    let result: VoiceProfileMatcher.MatchResult
    let profile: VoiceProfileTarget
    let metrics: [SpeechMetric]

    private static let minSessionsForCoach = 3
    private static let minWordsForCoach = 150

    var body: some View {
        let totalWords = metrics.reduce(0) { $0 + $1.wordCount }
        let unlocked = result.sampleSize >= Self.minSessionsForCoach && totalWords >= Self.minWordsForCoach
        let key = VoiceStyleKey.from(profile: profile)
        // Exclude on-target axes (.onTarget): there's nothing to pull, and a directional verb would be misleading.
        let cards = Array(result.axesByGain
            .filter { $0.weightedGain >= 1 && $0.direction != .onTarget }
            .prefix(3))

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo)
                LocalizedText(en: "How to reach the style", ru: "Как дойти до стиля")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }

            if !unlocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.t(
                        en: "Coach unlocks after \(Self.minSessionsForCoach) dictations (≥\(Self.minWordsForCoach) words) — keep dictating",
                        ru: "Тренер появится после \(Self.minSessionsForCoach) диктовок (≥\(Self.minWordsForCoach) слов) — продолжай диктовать"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if cards.isEmpty {
                suggestion
            } else {
                // .id(profile.id) — on profile change the cards are recreated,
                // so `expanded` reinitializes for the new style (instead of getting stuck).
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cards) { bd in
                        CoachCard(
                            breakdown: bd,
                            styleKey: key,
                            markerUsage: bd.axis == .markers ? result.markerUsage : [],
                            topFillers: bd.axis == .fillers ? topPersonalFillers() : [],
                            defaultExpanded: bd.id == cards.first?.id
                        )
                    }
                }
                .id(profile.id)
            }
        }
    }

    private var suggestion: some View {
        let weak = result.weakestMetric
        return HStack(spacing: 8) {
            Image(systemName: weak.gain >= 1 ? "lightbulb.fill" : "checkmark.seal.fill")
                .foregroundStyle(weak.gain >= 1 ? .yellow : .green)
                .font(.system(size: 12))
            // When gain < 1 all axes are on target — a "pull up" suggestion would be absurd
            Text(weak.gain >= 1
                ? L10n.t(
                    en: "Pull up first: \(axisName(weak.axis)) (\(Int(weak.score))%) — up to +\(Int(weak.gain.rounded())) to the total score",
                    ru: "Подтягивай в первую очередь: \(axisName(weak.axis)) (\(Int(weak.score))%) — до +\(Int(weak.gain.rounded())) к общему результату"
                )
                : L10n.t(
                    en: "All axes are on target — keep it up",
                    ru: "Все оси у цели — держи уровень"
                )
            )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    /// Top 3 personal filler words for the period (for the fillers axis card).
    private func topPersonalFillers() -> [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for m in metrics {
            for (word, count) in m.fillersByWord {
                totals[word, default: 0] += count
            }
        }
        return totals
            .map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }
    }

    private func axisName(_ axis: VoiceProfileMatcher.Axis) -> String {
        switch axis {
        case .wpm:            return L10n.t(en: "Speed (WPM)", ru: "Темп (WPM)")
        case .sentenceLength: return L10n.t(en: "Sentence length", ru: "Длина предложения")
        case .complexity:     return L10n.t(en: "Complexity", ru: "Сложность")
        case .fillers:        return L10n.t(en: "Fillers", ru: "Паразиты")
        case .markers:        return L10n.t(en: "Marker phrases", ru: "Маркер-фразы")
        }
    }
}
