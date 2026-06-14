//
//  PhraseOccurrenceScanner.swift
//  VoiceInk
//
//  Общий поиск вхождений фраз в тексте: регистронезависимо, по границам слов,
//  длинные фразы первыми, без двойного счёта пересечений (одно место текста
//  засчитывается один раз — «именно поэтому» не даёт ещё и «поэтому»).
//
//  Используется: VoiceProfileMatcher (маркер-фразы стилей), SpeechMetricsAnalyzer
//  (мультисловные паразиты, маркеры подчинения), drill-down подсветка сессии.
//

import Foundation

enum PhraseOccurrenceScanner {

    /// Нормализованный порядок фраз для скана: lowercase, дедуп, длинные первыми
    /// (чтобы вложенная короткая фраза не съела место длинной). Считается один раз —
    /// вызывай перед циклом по многим текстам и передавай в `*ofOrdered`.
    static func normalizedOrdered(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        return phrases
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// Вхождения каждой фразы в тексте. Ranges — в исходной строке (для подсветки).
    /// Ключ результата — фраза в lowercase.
    static func occurrences(of phrases: [String], in text: String) -> [String: [Range<String.Index>]] {
        guard !phrases.isEmpty, !text.isEmpty else { return [:] }
        return occurrences(ofOrdered: normalizedOrdered(phrases), in: text)
    }

    /// Как `occurrences(of:in:)`, но принимает уже нормализованный список (см.
    /// `normalizedOrdered`) — чтобы не пересчитывать его на каждый текст в цикле.
    static func occurrences(ofOrdered ordered: [String], in text: String) -> [String: [Range<String.Index>]] {
        guard !ordered.isEmpty, !text.isEmpty else { return [:] }

        var result: [String: [Range<String.Index>]] = [:]
        var consumed: [Range<String.Index>] = []

        for phrase in ordered {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: phrase, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                // Продвигаемся на один символ, а не на upperBound: отказ по границе
                // слова не должен прятать валидное вхождение чуть правее.
                searchStart = text.index(after: range.lowerBound)

                guard isWordBounded(range, in: text) else { continue }
                guard !consumed.contains(where: { $0.overlaps(range) }) else { continue }

                consumed.append(range)
                result[phrase, default: []].append(range)
            }
        }
        return result
    }

    /// Число вхождений каждой фразы (границы слов, без пересечений).
    static func counts(of phrases: [String], in text: String) -> [String: Int] {
        occurrences(of: phrases, in: text).mapValues { $0.count }
    }

    /// Как `counts(of:in:)`, но для уже нормализованного списка фраз (см.
    /// `normalizedOrdered`) — для горячих циклов по многим текстам.
    static func counts(ofOrdered ordered: [String], in text: String) -> [String: Int] {
        occurrences(ofOrdered: ordered, in: text).mapValues { $0.count }
    }

    /// Суммарное число вхождений всех фраз.
    static func totalCount(of phrases: [String], in text: String) -> Int {
        counts(of: phrases, in: text).values.reduce(0, +)
    }

    /// Вхождение валидно, только если слева и справа не «словесный» символ.
    /// «возможно» не матчится внутри «невозможно», «цель» — внутри «прицельный».
    /// Дефис и апостроф считаются частью слова — как в SpeechMetricsAnalyzer.extractWords:
    /// «ну» внутри «ну-ка» не подсвечивается и не засчитывается.
    private static func isWordBounded(_ range: Range<String.Index>, in text: String) -> Bool {
        let startOK = range.lowerBound == text.startIndex
            || !isWordChar(text[text.index(before: range.lowerBound)])
        let endOK = range.upperBound == text.endIndex
            || !isWordChar(text[range.upperBound])
        return startOK && endOK
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch == "-" || ch == "'"
    }
}
