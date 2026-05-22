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

        /// Самый «слабый» под-score — куда тянуть в первую очередь.
        var weakestMetric: (name: String, score: Double) {
            let pairs: [(String, Double)] = [
                ("Темп (WPM)", wpmScore),
                ("Длина предложения", sentenceLengthScore),
                ("Сложность", complexityScore),
                ("Паразиты", fillerScore),
                ("Marker phrases", markerScore)
            ]
            return pairs.min(by: { $0.1 < $1.1 }) ?? ("—", 0)
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
            actualMarkerRatePer100Words: actualMarkerRate
        )
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

    /// Считает суммарное число вхождений всех marker phrases в массиве текстов.
    private static func countMarkerHits(in texts: [String], phrases: [String]) -> Int {
        guard !phrases.isEmpty else { return 0 }
        var hits = 0
        for text in texts {
            let lower = text.lowercased()
            for phrase in phrases {
                var searchRange = lower.startIndex..<lower.endIndex
                while let range = lower.range(of: phrase, range: searchRange) {
                    hits += 1
                    searchRange = range.upperBound..<lower.endIndex
                }
            }
        }
        return hits
    }
}
