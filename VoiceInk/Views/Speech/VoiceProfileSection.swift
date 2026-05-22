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
                Text("Выбери целевой стиль ↑")
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
            Text("Voice Profile Match")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
            Text("(целевой стиль речи)")
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
                            Text(p.name)
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

    private func profileSummary(_ profile: VoiceProfileTarget) -> some View {
        Text(profile.summary)
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
                Text("Match Score")
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
            metricRow("Темп (WPM)", actual: result.actualWPM, format: "%.0f", score: result.wpmScore)
            metricRow("Длина предложения", actual: result.actualSentenceLength, format: "%.0f", score: result.sentenceLengthScore)
            metricRow("Сложность", actual: result.actualComplexity, format: "%.1f", score: result.complexityScore)
            metricRow("Паразиты / 100w", actual: result.actualFillerRate, format: "%.1f", score: result.fillerScore)
            metricRow("Marker phrases / 100w", actual: result.actualMarkerRatePer100Words, format: "%.1f", score: result.markerScore)
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
            Text("Подтягивай в первую очередь: **\(weak.name)** (\(Int(weak.score))%)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        Text("Метрики появятся после первой диктовки ≥ 15 слов")
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
        case 90...: return "Звучишь как этот стиль"
        case 75..<90: return "Близко к стилю"
        case 50..<75: return "Местами совпадает — есть к чему расти"
        case 25..<50: return "Далеко от стиля — много работы"
        default: return "Совсем другой стиль речи"
        }
    }
}
