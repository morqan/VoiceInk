//
//  VoiceProfileMatcher.swift
//  VoiceInk
//
//  Считает Match Score — насколько реальная речь (за период) близка к целевому стилю.
//  Локально, без AI. Каждая метрика даёт частный score 0..100, total — взвешенная сумма.
//
//  Веса:
//    WPM             15%
//    Sentence length 20%
//    Complexity      20%
//    Filler rate     15%
//    Marker rate     30%  (главный — отличает стили друг от друга)
//

import Foundation
import OSLog

enum VoiceProfileMatcher {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "VoiceProfileMatcher"
    )

    /// Ось скоринга. UI локализует названия сам — здесь только ключи.
    enum Axis {
        case wpm
        case sentenceLength
        case complexity
        case fillers
        case markers
    }

    /// Направление, в которое надо тянуть ось, чтобы приблизиться к цели.
    /// proximity-оси (WPM/длина/сложность) могут требовать и +, и −;
    /// fillers — всегда .decrease; markers — всегда .increase.
    enum AxisDirection {
        case increase   // actual < target → удлиняй / ускоряй / усложняй / больше маркеров
        case decrease   // actual > target → укорачивай / замедляй / упрощай / меньше паразитов
        case onTarget   // в пределах допуска — стрелку не показываем
    }

    /// Полная карточка одной оси для тренера. Считается один раз в compute().
    struct AxisBreakdown: Identifiable {
        let axis: Axis
        var id: Int { axisOrder }
        let axisOrder: Int          // стабильный id для ForEach
        let score: Double           // 0..100, под-score этой оси
        let weight: Double          // 0.15 / 0.20 / 0.20 / 0.15 / 0.30
        let weightedGain: Double    // weight × (100 − score) — потенциальный прирост total
        let actual: Double
        let target: Double          // для fillers — это maxFillerRate (порог)
        let direction: AxisDirection
    }

    /// Разбивка одной marker-фразы: встретилась хоть раз = used.
    struct MarkerPhraseUsage: Identifiable {
        let phrase: String
        var id: String { phrase }
        let count: Int              // суммарно по всем текстам периода
        var isUsed: Bool { count > 0 }
        /// true, если фраза — один токен без пробелов: substring-матч без границ
        /// слова легко даёт ложное «used» (например «цель» внутри «целься»).
        let isAmbiguousSingleToken: Bool
    }

    /// Развёрнутый результат сравнения. Каждый под-score 0..100.
    struct MatchResult {
        let totalScore: Double            // 0..100
        let wpmScore: Double
        let sentenceLengthScore: Double
        let complexityScore: Double
        let fillerScore: Double
        let markerScore: Double

        let actualWPM: Double
        let actualSentenceLength: Double
        let actualComplexity: Double
        let actualFillerRate: Double
        let actualMarkerRatePer100Words: Double

        /// Все 5 осей, УЖЕ отсортированы по weightedGain убыв. (тай-брейк — меньший score).
        /// UI берёт prefix(2..3) для карточек тренера.
        let axesByGain: [AxisBreakdown]

        /// Per-phrase разбивка маркеров активного профиля (пустая, если фраз нет).
        let markerUsage: [MarkerPhraseUsage]

        /// Сколько диктовок участвовало в расчёте — для gating тренера.
        let sampleSize: Int

        /// Куда тянуть в первую очередь — топ оси по приросту итога.
        var weakestMetric: (axis: Axis, score: Double, gain: Double) {
            guard let top = axesByGain.first else { return (.markers, 0, 0) }
            return (top.axis, top.score, top.weightedGain)
        }
    }

    // MARK: - Веса

    private static let wpmWeight: Double = 0.15
    private static let sentenceWeight: Double = 0.20
    private static let complexityWeight: Double = 0.20
    private static let fillerWeight: Double = 0.15
    private static let markerWeight: Double = 0.30

    // MARK: - Public

    /// Считает Match Score между списком метрик речи и целевым профилем.
    static func compute(target: VoiceProfileTarget, metrics: [SpeechMetric]) -> MatchResult? {
        guard !metrics.isEmpty else { return nil }

        // Агрегаты
        let totalWords = metrics.reduce(0) { $0 + $1.wordCount }
        guard totalWords > 0 else { return nil }

        let totalFillers = metrics.reduce(0) { $0 + $1.fillerCount }
        let totalSentences = metrics.reduce(0) { $0 + $1.sentenceCount }

        let validWPM = metrics.filter { $0.wpm > 0 }
        let actualWPM = validWPM.isEmpty ? 0 : validWPM.reduce(0) { $0 + $1.wpm } / Double(validWPM.count)

        let actualSentenceLength = totalSentences > 0
            ? Double(totalWords) / Double(totalSentences)
            : 0

        let validComplexity = metrics.filter { $0.avgSentenceComplexity > 0 }
        let actualComplexity = validComplexity.isEmpty
            ? 0
            : validComplexity.reduce(0) { $0 + $1.avgSentenceComplexity } / Double(validComplexity.count)

        let actualFillerRate = Double(totalFillers) / Double(totalWords) * 100

        let actualMarkerHits = countMarkerHits(in: metrics.map { $0.text }, phrases: target.markerPhrases)
        let actualMarkerRate = Double(actualMarkerHits) / Double(totalWords) * 100

        // Под-scores
        let wpmS = proximityScore(actual: actualWPM, target: target.targetWPM)
        let sentenceS = proximityScore(actual: actualSentenceLength, target: target.targetSentenceLength)
        let complexityS = proximityScore(actual: actualComplexity, target: target.targetComplexity)
        let fillerS = inverseScore(actual: actualFillerRate, threshold: target.maxFillerRate)
        let markerS = upToScore(actual: actualMarkerRate, target: target.targetMarkerRatePer100Words)

        let total = wpmWeight * wpmS
            + sentenceWeight * sentenceS
            + complexityWeight * complexityS
            + fillerWeight * fillerS
            + markerWeight * markerS

        // Разбивка осей для тренера, отсортированная по приросту итога.
        let breakdowns: [AxisBreakdown] = [
            AxisBreakdown(axis: .wpm, axisOrder: 0, score: wpmS, weight: wpmWeight,
                          weightedGain: wpmWeight * (100 - wpmS),
                          actual: actualWPM, target: target.targetWPM,
                          direction: proximityDirection(actual: actualWPM, target: target.targetWPM)),
            AxisBreakdown(axis: .sentenceLength, axisOrder: 1, score: sentenceS, weight: sentenceWeight,
                          weightedGain: sentenceWeight * (100 - sentenceS),
                          actual: actualSentenceLength, target: target.targetSentenceLength,
                          direction: proximityDirection(actual: actualSentenceLength, target: target.targetSentenceLength)),
            AxisBreakdown(axis: .complexity, axisOrder: 2, score: complexityS, weight: complexityWeight,
                          weightedGain: complexityWeight * (100 - complexityS),
                          actual: actualComplexity, target: target.targetComplexity,
                          direction: proximityDirection(actual: actualComplexity, target: target.targetComplexity)),
            AxisBreakdown(axis: .fillers, axisOrder: 3, score: fillerS, weight: fillerWeight,
                          weightedGain: fillerWeight * (100 - fillerS),
                          actual: actualFillerRate, target: target.maxFillerRate,
                          direction: actualFillerRate <= target.maxFillerRate ? .onTarget : .decrease),
            AxisBreakdown(axis: .markers, axisOrder: 4, score: markerS, weight: markerWeight,
                          weightedGain: markerWeight * (100 - markerS),
                          actual: actualMarkerRate, target: target.targetMarkerRatePer100Words,
                          direction: actualMarkerRate >= target.targetMarkerRatePer100Words ? .onTarget : .increase)
        ].sorted { a, b in
            if a.weightedGain == b.weightedGain { return a.score < b.score }
            return a.weightedGain > b.weightedGain
        }

        // Per-phrase использование маркеров (для chips тренера).
        // Дедупим по lowercased — у кастомных профилей возможны дубли/регистровые
        // варианты, иначе ForEach получит дубль Identifiable id.
        let perPhrase = countMarkerHitsPerPhrase(in: metrics.map { $0.text }, phrases: target.markerPhrases)
        var seenPhrases = Set<String>()
        let markerUsage: [MarkerPhraseUsage] = target.markerPhrases.compactMap { phrase in
            let key = phrase.lowercased()
            guard seenPhrases.insert(key).inserted else { return nil }
            return MarkerPhraseUsage(
                phrase: phrase,
                count: perPhrase[key] ?? 0,
                isAmbiguousSingleToken: !phrase.contains(" ")
            )
        }

        return MatchResult(
            totalScore: total,
            wpmScore: wpmS,
            sentenceLengthScore: sentenceS,
            complexityScore: complexityS,
            fillerScore: fillerS,
            markerScore: markerS,
            actualWPM: actualWPM,
            actualSentenceLength: actualSentenceLength,
            actualComplexity: actualComplexity,
            actualFillerRate: actualFillerRate,
            actualMarkerRatePer100Words: actualMarkerRate,
            axesByGain: breakdowns,
            markerUsage: markerUsage,
            sampleSize: metrics.count
        )
    }

    /// Направление коррекции для proximity-оси с 5% допуском (чтобы стрелка не мигала у цели).
    private static func proximityDirection(actual: Double, target: Double) -> AxisDirection {
        guard target > 0 else { return .onTarget }
        if abs(actual - target) / target <= 0.05 { return .onTarget }
        return actual < target ? .increase : .decrease
    }

    // MARK: - Scoring helpers

    /// Близость к target. 100 при равенстве, постепенно убывает.
    /// При actual в 2× target = score 0.
    private static func proximityScore(actual: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        let ratio = abs(actual - target) / target
        return max(0, min(100, (1 - ratio) * 100))
    }

    /// Инвертированный score — чем меньше actual тем лучше.
    /// 100 при actual ≤ threshold, дальше падает.
    private static func inverseScore(actual: Double, threshold: Double) -> Double {
        guard threshold > 0 else { return actual == 0 ? 100 : 0 }
        if actual <= threshold { return 100 }
        let excessRatio = (actual - threshold) / threshold
        return max(0, 100 - excessRatio * 50)  // 50% penalty при удвоении threshold
    }

    /// Линейная шкала — чем больше actual тем лучше (до target).
    /// 100 при actual ≥ target, линейно растёт от 0.
    private static func upToScore(actual: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(100, actual / target * 100)
    }

    // MARK: - Marker counting

    /// Считает вхождения КАЖДОЙ marker phrase отдельно: [phrase.lowercased(): count].
    /// substring-матч без границ слов (поведение сохранено намеренно — иначе total score поедет).
    static func countMarkerHitsPerPhrase(in texts: [String], phrases: [String]) -> [String: Int] {
        guard !phrases.isEmpty else { return [:] }
        let lowerTexts = texts.map { $0.lowercased() }
        var result: [String: Int] = [:]
        for phrase in phrases {
            let p = phrase.lowercased()
            var count = 0
            for lower in lowerTexts {
                var searchRange = lower.startIndex..<lower.endIndex
                while let range = lower.range(of: p, range: searchRange) {
                    count += 1
                    searchRange = range.upperBound..<lower.endIndex
                }
            }
            result[p] = count
        }
        return result
    }

    /// Суммарное число вхождений всех marker phrases — обёртка над per-phrase подсчётом.
    private static func countMarkerHits(in texts: [String], phrases: [String]) -> Int {
        countMarkerHitsPerPhrase(in: texts, phrases: phrases).values.reduce(0, +)
    }
}
