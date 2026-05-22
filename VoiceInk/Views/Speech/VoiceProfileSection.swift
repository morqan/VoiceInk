//
//  VoiceProfileSection.swift
//  VoiceInk
//
//  Секция Voice Profile Match — сравнение реальной речи с целевым стилем.
//

import SwiftUI
import SwiftData

struct VoiceProfileSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceProfileTarget.name) private var profiles: [VoiceProfileTarget]

    /// Метрики за выбранный период (передаём из родителя).
    let metrics: [SpeechMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            profileSelector

            if let active = activeProfile {
                profileSummary(active)
                if let result = VoiceProfileMatcher.compute(target: active, metrics: metrics) {
                    totalScoreCard(result)
                    breakdown(result)
                    suggestion(result)
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

    private func totalScoreCard(_ result: VoiceProfileMatcher.MatchResult) -> some View {
        HStack(spacing: 16) {
            // Circular score
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: CGFloat(result.totalScore / 100))
                    .stroke(scoreColor(result.totalScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(result.totalScore))")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor(result.totalScore))
            }

            VStack(alignment: .leading, spacing: 4) {
                LocalizedText(en: "Match Score", ru: "Совпадение")
                    .font(.system(size: 13, weight: .semibold))
                Text(matchVerdict(result.totalScore))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func breakdown(_ result: VoiceProfileMatcher.MatchResult) -> some View {
        VStack(spacing: 6) {
            metricRow(L10n.t(en: "Speed (WPM)", ru: "Темп (WPM)"), actual: result.actualWPM, format: "%.0f", score: result.wpmScore)
            metricRow(L10n.t(en: "Sentence length", ru: "Длина предложения"), actual: result.actualSentenceLength, format: "%.0f", score: result.sentenceLengthScore)
            metricRow(L10n.t(en: "Complexity", ru: "Сложность"), actual: result.actualComplexity, format: "%.1f", score: result.complexityScore)
            metricRow(L10n.t(en: "Fillers / 100w", ru: "Паразиты / 100w"), actual: result.actualFillerRate, format: "%.1f", score: result.fillerScore)
            metricRow(L10n.t(en: "Marker phrases / 100w", ru: "Маркеры / 100w"), actual: result.actualMarkerRatePer100Words, format: "%.1f", score: result.markerScore)
        }
        .padding(.top, 6)
    }

    private func metricRow(_ name: String, actual: Double, format: String, score: Double) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 11))
                .frame(width: 160, alignment: .leading)
            Text(String(format: format, actual))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            // Прогресс-бар
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(score / 100), height: 6)
                }
            }
            .frame(height: 6)
            Text("\(Int(score))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(scoreColor(score))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func suggestion(_ result: VoiceProfileMatcher.MatchResult) -> some View {
        let weak = result.weakestMetric
        return HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
            Text(L10n.t(
                en: "Pull up first: **\(weak.name)** (\(Int(weak.score))%)",
                ru: "Подтягивай в первую очередь: **\(weak.name)** (\(Int(weak.score))%)"
            ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
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

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    private func matchVerdict(_ score: Double) -> String {
        switch score {
        case 90...:    return L10n.t(en: "You sound like this style", ru: "Звучишь как этот стиль")
        case 75..<90:  return L10n.t(en: "Close to the style", ru: "Близко к стилю")
        case 50..<75:  return L10n.t(en: "Partial match — room to grow", ru: "Местами совпадает — есть к чему расти")
        case 25..<50:  return L10n.t(en: "Far from the style — lots to do", ru: "Далеко от стиля — много работы")
        default:       return L10n.t(en: "Completely different style", ru: "Совсем другой стиль речи")
        }
    }
}
