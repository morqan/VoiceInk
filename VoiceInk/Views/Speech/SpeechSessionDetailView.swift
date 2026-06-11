//
//  SpeechSessionDetailView.swift
//  VoiceInk
//
//  Drill-down одной диктовки: полный текст с подсветкой всего, что засчитала
//  аналитика — паразиты (оранжевый), англицизмы (розовый), маркер-фразы
//  активного стиля (индиго). Отвечает на вопрос «откуда цифры»: видно буквально,
//  какие слова попали в каждый счётчик.
//
//  Подсветка использует тот же PhraseOccurrenceScanner, что и скоринг.
//  Нюанс: счётчики в бейджах — из сохранённых полей записи (алгоритм на момент
//  диктовки), подсветка — текущим алгоритмом; для старых сессий числа могут
//  незначительно расходиться с количеством подсвеченных мест.
//

import SwiftUI

struct SpeechSessionDetailView: View {
    let metric: SpeechMetric
    let profile: VoiceProfileTarget?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statsRow
            legend
            Divider()
            ScrollView {
                Text(highlightedText)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !foundMarkers.isEmpty {
                Divider()
                markersSummary
            }
        }
        .padding(20)
        .frame(width: 580, height: 560)
    }

    // MARK: - Subviews

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
            Button {
                dismiss()
            } label: {
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
            if metric.repetitionCount > 0 {
                statBadge("\(metric.repetitionCount)", L10n.t(en: "repeats", ru: "повторы"), color: .purple)
            }
            Spacer()
        }
    }

    private func statBadge(_ value: String, _ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.orange, L10n.t(en: "fillers", ru: "паразиты"))
            legendDot(.pink, L10n.t(en: "anglicisms", ru: "англицизмы"))
            if profile != nil {
                legendDot(.indigo, L10n.t(en: "style markers", ru: "маркеры стиля"))
            }
            Spacer()
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Highlighting

    /// Маркеры стиля, реально найденные в этой диктовке (фраза → счёт).
    /// Ключи сканера lowercased — маппим обратно на авторское написание профиля.
    private var sourceText: String { AutoFillerDetector.sourceText(metric) }

    private var foundMarkers: [(phrase: String, count: Int)] {
        guard let phrases = profile?.markerPhrases, !phrases.isEmpty else { return [] }
        let original = Dictionary(phrases.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return PhraseOccurrenceScanner.counts(of: phrases, in: sourceText)
            .filter { $0.value > 0 }
            .map { (phrase: original[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var markersSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(en: "Style markers in this dictation", ru: "Маркеры стиля в этой диктовке")
                .font(.system(size: 11, weight: .semibold))
            Text(foundMarkers.map { "«\($0.phrase)» ×\($0.count)" }.joined(separator: "   "))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.indigo)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlightedText: AttributedString {
        let text = sourceText
        var attr = AttributedString(text)

        // Порядок важен: маркеры стиля идут первыми (длинные фразы), потом
        // паразиты и англицизмы — пересечения перекрашиваются последними двумя
        // категориями, что соответствует приоритету счётчиков.
        if let phrases = profile?.markerPhrases, !phrases.isEmpty {
            apply(color: .indigo, phrases: phrases, text: text, to: &attr)
        }
        apply(color: .orange, phrases: Array(metric.fillersByWord.keys), text: text, to: &attr)
        apply(color: .pink, phrases: Array(metric.anglicismsByWord.keys), text: text, to: &attr)

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
