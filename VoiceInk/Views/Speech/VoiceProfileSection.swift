//
//  VoiceProfileSection.swift
//  VoiceInk
//
//  Секция Voice Profile Match — сравнение реальной речи с целевым стилем.
//  Профиль-селектор + summary; счёт/оси рисует VoiceProfileBreakdownView,
//  обучающий блок — VoiceProfileStyleCoachView.
//

import SwiftUI
import SwiftData

struct VoiceProfileSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceProfileTarget.name) private var profiles: [VoiceProfileTarget]

    /// Метрики за выбранный период (передаём из родителя).
    let metrics: [SpeechMetric]

    /// Cached match result — computed in `.task`, not on every render (the compute
    /// scans each metric's text and was a sub-tab-switch hotspot).
    @State private var matchResult: VoiceProfileMatcher.MatchResult?

    private var matchKey: String {
        let newest = metrics.first?.timestamp.timeIntervalSince1970 ?? 0
        return "\(activeProfile?.id.uuidString ?? "none")|\(metrics.count)|\(newest)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            profileSelector

            if let active = activeProfile {
                profileSummary(active)
                if let result = matchResult {
                    VoiceProfileBreakdownView(result: result, profile: active)
                    Divider().padding(.vertical, 2)
                    VoiceProfileStyleCoachView(result: result, profile: active, metrics: metrics)
                } else {
                    emptyState
                }
            } else {
                LocalizedText(en: "Choose a target style ↑", ru: "Выбери целевой стиль ↑")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .task(id: matchKey) {
            matchResult = activeProfile.flatMap { VoiceProfileMatcher.compute(target: $0, metrics: metrics) }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill.viewfinder")
                .font(.system(size: 14))
                .foregroundStyle(.indigo)
            LocalizedText(en: "Voice Profile Match", ru: "Совпадение со стилем")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
            LocalizedText(en: "(target speech style)", ru: "(целевой стиль речи)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var profileSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profiles) { p in
                    Button {
                        activate(p)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: p.iconName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(profileDisplayName(p))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(p.isActive ? Color.indigo : Color.gray.opacity(0.15))
                        )
                        .foregroundColor(p.isActive ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
    }

    /// Перевод названий пресетов на английский. Если профиль кастомный (не preset) —
    /// возвращаем как есть.
    private func profileDisplayName(_ p: VoiceProfileTarget) -> String {
        guard p.isPreset, L10n.current == .english else { return p.name }
        switch p.name {
        case "Эриксоновский гипнотизёр": return "Ericksonian Hypnotist"
        case "Жёсткий переговорщик":      return "Tactical Negotiator"
        case "Спокойный лидер":           return "Calm Leader"
        case "Харизматичный спикер":      return "Charismatic Speaker"
        default: return p.name
        }
    }

    /// Перевод summary пресета.
    private func profileSummaryText(_ p: VoiceProfileTarget) -> String {
        guard p.isPreset, L10n.current == .english else { return p.summary }
        switch p.name {
        case "Эриксоновский гипнотизёр":
            return "Slow pace, long subordinate sentences, embedded commands. Bypasses critical thinking through enveloping."
        case "Жёсткий переговорщик":
            return "Short direct sentences, framing constructions, minimum fluff. Controls conversation pace via clarity."
        case "Спокойный лидер":
            return "Medium pace, structured. List before action, clear priorities, zero fluff."
        case "Харизматичный спикер":
            return "Fast varied pace, direct address, few repetitions, emotional imagery."
        default: return p.summary
        }
    }

    private func profileSummary(_ profile: VoiceProfileTarget) -> some View {
        Text(profileSummaryText(profile))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        LocalizedText(
            en: "Metrics will appear after your first dictation ≥ 15 words",
            ru: "Метрики появятся после первой диктовки ≥ 15 слов"
        )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var activeProfile: VoiceProfileTarget? {
        profiles.first { $0.isActive }
    }

    private func activate(_ target: VoiceProfileTarget) {
        for p in profiles {
            p.isActive = (p.id == target.id)
        }
        try? modelContext.save()
    }
}
