//
//  SpeechCoachTab.swift
//  VoiceInk
//
//  "Coach" tab of the Speech analytics page: the style-match section (VoiceProfileSection)
//  plus on-target streaks. Streak values are precomputed off-main by the parent and
//  passed in; this view just renders them.
//

import SwiftUI

struct SpeechCoachTab: View {
    let metrics: [SpeechMetric]
    let streaks: (filler: Int, anglicism: Int, sentence: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VoiceProfileSection(metrics: metrics)
            streaksSection
        }
    }

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                LocalizedText(en: "Streaks", ru: "Стрики")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                LocalizedText(
                    en: "(consecutive days on target — all history)",
                    ru: "(дней подряд под целью — по всей истории)"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                InfoTip(message: SpeechMetricTips.streaks, iconSize: .small, iconColor: .secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                streakCard(
                    title: L10n.t(en: "Filler-free", ru: "Без паразитов"),
                    value: streaks.filler,
                    subtitle: L10n.t(en: "≤ 2 / 100 words", ru: "≤ 2 / 100 слов"),
                    color: .orange,
                    icon: "text.bubble"
                )
                streakCard(
                    title: L10n.t(en: "Anglicism-free", ru: "Без англицизмов"),
                    value: streaks.anglicism,
                    subtitle: L10n.t(en: "≤ 1 / 100 words", ru: "≤ 1 / 100 слов"),
                    color: .pink,
                    icon: "globe"
                )
                streakCard(
                    title: L10n.t(en: "Short sentences", ru: "Короткие предложения"),
                    value: streaks.sentence,
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

    /// Correct day/days plural for the current language.
    private func daysLabel(for value: Int) -> String {
        if L10n.current == .english {
            return value == 1 ? "day" : "days"
        }
        return L10n.ruPlural(value, one: "день", few: "дня", many: "дней")
    }
}
