//
//  SpeechSessionDetailView.swift
//  VoiceInk
//
//  Drill-down одной диктовки: полный текст с подсветкой всего, что засчитала
//  аналитика — паразиты (оранжевый), англицизмы (розовый), маркер-фразы
//  активного стиля (индиго). Отвечает на вопрос «откуда цифры».
//
//  Плюс «Как сказал бы [стиль]»: AI переписывает твою диктовку в целевом стиле
//  (переиспользует enhancement-пайплайн), показывает side-by-side через
//  переключатель Оригинал/Переписано и Match Score до→после — учишься на своём
//  тексте.
//

import SwiftUI

struct SpeechSessionDetailView: View {
    let metric: SpeechMetric
    let profile: VoiceProfileTarget?

    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.dismiss) private var dismiss

    private enum RewriteState: Equatable {
        case idle, loading, done(String), error(String)
    }
    @State private var rewriteState: RewriteState = .idle
    @State private var showRewrite = false
    @State private var scoreBefore: Double?
    @State private var scoreAfter: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statsRow
            if case .done = rewriteState { viewToggle }
            if !showRewrite { legend }
            Divider()
            ScrollView {
                Text(displayedText)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showRewrite, !foundMarkersInRewrite.isEmpty {
                wovenMarkersSummary
            } else if !showRewrite, !foundMarkers.isEmpty {
                markersSummary
            }
            rewriteFooter
        }
        .padding(20)
        .frame(width: 600, height: 600)
    }

    // MARK: - Header / stats

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(en: "Dictation breakdown", ru: "Разбор диктовки")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Text(metric.timestamp, format: .dateTime.day().month(.wide).hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statBadge("\(metric.wordCount)", L10n.t(en: "words", ru: "слов"), color: .indigo)
            statBadge(String(format: "%.0f", metric.wpm), "WPM", color: .blue)
            statBadge("\(metric.sentenceCount)", L10n.t(en: "sentences", ru: "предл."), color: .teal)
            statBadge(String(format: "%.1f", metric.fillerRatePer100Words), L10n.t(en: "fillers/100w", ru: "параз./100сл"), color: .orange)
            if metric.anglicismCount > 0 {
                statBadge("\(metric.anglicismCount)", L10n.t(en: "anglicisms", ru: "англ."), color: .pink)
            }
            Spacer()
        }
    }

    private func statBadge(_ value: String, _ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    // MARK: - Оригинал / Переписано

    private var viewToggle: some View {
        HStack(spacing: 10) {
            Picker("", selection: $showRewrite) {
                LocalizedText(en: "Original", ru: "Оригинал").tag(false)
                Text(L10n.t(en: "Rewritten", ru: "Переписано")).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()

            if let before = scoreBefore, let after = scoreAfter {
                HStack(spacing: 4) {
                    LocalizedText(en: "Match", ru: "Совпадение").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(Int(before)) → \(Int(after))")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(after >= before ? .green : .orange)
                }
            }
            Spacer()
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.orange, L10n.t(en: "fillers", ru: "паразиты"))
            legendDot(.pink, L10n.t(en: "anglicisms", ru: "англицизмы"))
            if profile != nil { legendDot(.indigo, L10n.t(en: "style markers", ru: "маркеры стиля")) }
            Spacer()
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.35)).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer: кнопка переписывания

    @ViewBuilder
    private var rewriteFooter: some View {
        if let profile {
            Divider()
            switch rewriteState {
            case .idle:
                Button {
                    Task { await runRewrite(profile: profile) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(L10n.t(en: "How \(profileShort(profile)) would say it",
                                    ru: "Как сказал бы «\(profileShort(profile))»"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.indigo.opacity(0.15)))
                    .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    LocalizedText(en: "Rewriting in style…", ru: "Переписываю в стиле…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            case .done:
                Button {
                    Task { await runRewrite(profile: profile) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        LocalizedText(en: "Rewrite again", ru: "Переписать заново")
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            case .error(let msg):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 11))
                    Text(msg).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private func profileShort(_ p: VoiceProfileTarget) -> String {
        // Короткое имя без длинных слов для кнопки
        p.name.replacingOccurrences(of: "Эриксоновский гипнотизёр", with: "Эриксон")
    }

    // MARK: - Rewrite action

    private func runRewrite(profile: VoiceProfileTarget) async {
        guard enhancementService.isConfigured else {
            rewriteState = .error(L10n.t(
                en: "Set up an AI model in the Enhancement tab first",
                ru: "Сначала настрой AI-модель во вкладке Enhancement"
            ))
            return
        }
        rewriteState = .loading
        // Совпадение оригинала с этим стилем
        scoreBefore = VoiceProfileMatcher.compute(target: profile, metrics: [metric])?.totalScore
        do {
            let prompt = StyleRewritePrompt.systemPrompt(for: profile)
            let result = try await enhancementService.rewrite(text: sourceText, systemPrompt: prompt)
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                rewriteState = .error(L10n.t(en: "Model returned empty text", ru: "Модель вернула пустой текст"))
                return
            }
            // Совпадение переписанного варианта (по тем же осям, темп унаследован)
            if let rewrittenMetric = SpeechMetricsAnalyzer.analyze(
                text: trimmed,
                durationSeconds: metric.durationSeconds,
                activeFillers: AutoFillerDetector.cachedActiveFillers()
            ) {
                scoreAfter = VoiceProfileMatcher.compute(target: profile, metrics: [rewrittenMetric])?.totalScore
            }
            rewriteState = .done(trimmed)
            showRewrite = true
        } catch {
            let desc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            rewriteState = .error(desc)
        }
    }

    // MARK: - Highlighting

    private var sourceText: String { AutoFillerDetector.sourceText(metric) }

    private var rewrittenText: String {
        if case .done(let text) = rewriteState { return text }
        return ""
    }

    private var displayedText: AttributedString {
        showRewrite ? highlightedRewrite : highlightedOriginal
    }

    private var foundMarkers: [(phrase: String, count: Int)] {
        markersIn(sourceText)
    }

    private var foundMarkersInRewrite: [(phrase: String, count: Int)] {
        markersIn(rewrittenText)
    }

    private func markersIn(_ text: String) -> [(phrase: String, count: Int)] {
        guard let phrases = profile?.markerPhrases, !phrases.isEmpty, !text.isEmpty else { return [] }
        let original = Dictionary(phrases.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return PhraseOccurrenceScanner.counts(of: phrases, in: text)
            .filter { $0.value > 0 }
            .map { (phrase: original[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var markersSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(en: "Style markers in this dictation", ru: "Маркеры стиля в этой диктовке")
                .font(.system(size: 11, weight: .semibold))
            Text(foundMarkers.map { "«\($0.phrase)» ×\($0.count)" }.joined(separator: "   "))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.indigo)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wovenMarkersSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(en: "Style phrases woven in (green)", ru: "Вплетённые фразы стиля (зелёным)")
                .font(.system(size: 11, weight: .semibold))
            Text(foundMarkersInRewrite.map { "«\($0.phrase)» ×\($0.count)" }.joined(separator: "   "))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlightedOriginal: AttributedString {
        let text = sourceText
        var attr = AttributedString(text)
        if let phrases = profile?.markerPhrases, !phrases.isEmpty {
            apply(color: .indigo, phrases: phrases, text: text, to: &attr)
        }
        apply(color: .orange, phrases: Array(metric.fillersByWord.keys), text: text, to: &attr)
        apply(color: .pink, phrases: Array(metric.anglicismsByWord.keys), text: text, to: &attr)
        return attr
    }

    private var highlightedRewrite: AttributedString {
        let text = rewrittenText
        var attr = AttributedString(text)
        if let phrases = profile?.markerPhrases, !phrases.isEmpty {
            apply(color: .green, phrases: phrases, text: text, to: &attr)
        }
        return attr
    }

    private func apply(color: Color, phrases: [String], text: String, to attr: inout AttributedString) {
        guard !phrases.isEmpty else { return }
        for (_, ranges) in PhraseOccurrenceScanner.occurrences(of: phrases, in: text) {
            for range in ranges {
                guard let attrRange = Range(range, in: attr) else { continue }
                attr[attrRange].backgroundColor = color.opacity(0.28)
            }
        }
    }
}
