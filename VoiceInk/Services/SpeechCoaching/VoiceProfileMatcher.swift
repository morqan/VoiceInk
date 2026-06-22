//
//  VoiceProfileMatcher.swift
//  VoiceInk
//
//  Computes a Match Score — how close the actual speech (over a period) is to the target style.
//  Local, no AI. Each metric yields a partial score 0..100; total is the weighted sum.
//
//  Weights:
//    WPM             15%
//    Sentence length 20%
//    Complexity      20%
//    Filler rate     15%
//    Marker rate     30%  (the main one — it distinguishes styles from each other)
//

import Foundation
import OSLog

enum VoiceProfileMatcher {

    private static let logger = Logger(
        subsystem: "com.morqan.voiceink",
        category: "VoiceProfileMatcher"
    )

    /// Scoring axis. The UI localizes the names itself — only the keys live here.
    enum Axis {
        case wpm
        case sentenceLength
        case complexity
        case fillers
        case markers
    }

    /// The direction to push an axis in order to get closer to the target.
    /// proximity axes (WPM/length/complexity) may require either + or −;
    /// fillers — always .decrease; markers — always .increase.
    enum AxisDirection {
        case increase   // actual < target → lengthen / speed up / make more complex / more markers
        case decrease   // actual > target → shorten / slow down / simplify / fewer filler words
        case onTarget   // within tolerance — don't show the arrow
    }

    /// The full card for a single axis used by the coach. Computed once in compute().
    struct AxisBreakdown: Identifiable {
        let axis: Axis
        var id: Int { axisOrder }
        let axisOrder: Int          // stable id for ForEach
        let score: Double           // 0..100, the sub-score for this axis
        let weight: Double          // 0.15 / 0.20 / 0.20 / 0.15 / 0.30
        let weightedGain: Double    // weight × (100 − score) — the potential gain to total
        let actual: Double
        let target: Double          // for fillers — this is maxFillerRate (the threshold)
        let direction: AxisDirection
    }

    /// Breakdown of a single marker phrase: appeared at least once = used.
    /// Counted on word boundaries (PhraseOccurrenceScanner) — no false
    /// matches inside other words.
    struct MarkerPhraseUsage: Identifiable {
        let phrase: String
        var id: String { phrase }
        let count: Int              // total across all texts in the period
        var isUsed: Bool { count > 0 }
    }

    /// The expanded comparison result. Each sub-score is 0..100.
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

        /// All 5 axes, ALREADY sorted by weightedGain descending (tie-break — lower score).
        /// The UI takes prefix(2..3) for the coach cards.
        let axesByGain: [AxisBreakdown]

        /// Per-phrase marker breakdown for the active profile (empty if there are no phrases).
        let markerUsage: [MarkerPhraseUsage]

        /// How many dictations took part in the calculation — for gating the coach.
        let sampleSize: Int

        /// What to push first — the top axis by gain to the total.
        var weakestMetric: (axis: Axis, score: Double, gain: Double) {
            guard let top = axesByGain.first else { return (.markers, 0, 0) }
            return (top.axis, top.score, top.weightedGain)
        }
    }

    // MARK: - Weights

    private static let wpmWeight: Double = 0.15
    private static let sentenceWeight: Double = 0.20
    private static let complexityWeight: Double = 0.20
    private static let fillerWeight: Double = 0.15
    private static let markerWeight: Double = 0.30

    // MARK: - Public

    /// Computes the Match Score between a list of speech metrics and the target profile.
    static func compute(target: VoiceProfileTarget, metrics: [SpeechMetric]) -> MatchResult? {
        guard !metrics.isEmpty else { return nil }

        // Aggregates
        let totalWords = metrics.reduce(0) { $0 + $1.wordCount }
        guard totalWords > 0 else { return nil }

        let totalFillers = metrics.reduce(0) { $0 + $1.fillerCount }
        let totalSentences = metrics.reduce(0) { $0 + $1.sentenceCount }

        // WPM — pooled: all words in the period ÷ total recording time.
        // An unweighted average across sessions gave a 16-word remark the same weight as a 10-minute dictation.
        let timed = metrics.filter { $0.durationSeconds > 0 && $0.wordCount > 0 }
        let timedWords = timed.reduce(0) { $0 + $1.wordCount }
        let timedMinutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        let actualWPM = timedMinutes > 0 ? Double(timedWords) / timedMinutes : 0

        let actualSentenceLength = totalSentences > 0
            ? Double(totalWords) / Double(totalSentences)
            : 0

        // Complexity — weighted by words, including zero sessions
        // (excluding zeros biased the average upward — survivorship bias).
        let actualComplexity = metrics.reduce(0.0) {
            $0 + $1.avgSentenceComplexity * Double($1.wordCount)
        } / Double(totalWords)

        let actualFillerRate = Double(totalFillers) / Double(totalWords) * 100

        // Markers: per-phrase count on word boundaries. For scoring — anti-gaming:
        // a single phrase covers at most 40% of the target occurrences; a style needs a repertoire,
        // not one phrase like "maybe" repeated a hundred times in a row. The cap only applies with ≥ 3 phrases in
        // the profile — otherwise 100% on the axis would be mathematically unreachable.
        let perPhrase = countMarkerHitsPerPhrase(in: metrics.map { $0.text }, phrases: target.markerPhrases)
        let targetHits = target.targetMarkerRatePer100Words * Double(totalWords) / 100.0
        let perPhraseCap = target.markerPhrases.count >= 3
            ? max(1, Int((targetHits * 0.4).rounded(.up)))
            : Int.max
        let scoredMarkerHits = perPhrase.values.reduce(0) { $0 + min($1, perPhraseCap) }
        let actualMarkerRate = Double(scoredMarkerHits) / Double(totalWords) * 100

        // Sub-scores
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

        // Axis breakdown for the coach, sorted by gain to the total.
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

        // Per-phrase marker usage (for the coach chips) — raw counts,
        // without the anti-gaming cap. Deduplicated by lowercased: custom profiles
        // may contain duplicates, otherwise ForEach would get a duplicate Identifiable id.
        var seenPhrases = Set<String>()
        let markerUsage: [MarkerPhraseUsage] = target.markerPhrases.compactMap { phrase in
            let key = phrase.lowercased()
            guard seenPhrases.insert(key).inserted else { return nil }
            return MarkerPhraseUsage(phrase: phrase, count: perPhrase[key] ?? 0)
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

    /// Correction direction for a proximity axis with a 5% tolerance (so the arrow doesn't flicker near the target).
    private static func proximityDirection(actual: Double, target: Double) -> AxisDirection {
        guard target > 0 else { return .onTarget }
        if abs(actual - target) / target <= 0.05 { return .onTarget }
        return actual < target ? .increase : .decrease
    }

    // MARK: - Scoring helpers

    /// Closeness to the target. 100 when equal, decreasing gradually.
    /// When actual is 2× target = score 0.
    private static func proximityScore(actual: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        let ratio = abs(actual - target) / target
        return max(0, min(100, (1 - ratio) * 100))
    }

    /// Inverted score — the lower the actual, the better.
    /// 100 when actual ≤ threshold, then drops.
    private static func inverseScore(actual: Double, threshold: Double) -> Double {
        guard threshold > 0 else { return actual == 0 ? 100 : 0 }
        if actual <= threshold { return 100 }
        let excessRatio = (actual - threshold) / threshold
        return max(0, 100 - excessRatio * 50)  // 50% penalty when the threshold is doubled
    }

    /// Linear scale — the higher the actual, the better (up to target).
    /// 100 when actual ≥ target, grows linearly from 0.
    private static func upToScore(actual: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(100, actual / target * 100)
    }

    // MARK: - Marker counting

    /// Counts the occurrences of EACH marker phrase separately: [phrase.lowercased(): count].
    /// Honest matching: word boundaries, longer phrases first, no double-counting of
    /// overlaps (e.g. "exactly because" doesn't also yield "because").
    static func countMarkerHitsPerPhrase(in texts: [String], phrases: [String]) -> [String: Int] {
        guard !phrases.isEmpty else { return [:] }
        let ordered = PhraseOccurrenceScanner.normalizedOrdered(phrases)
        var result: [String: Int] = [:]
        for text in texts {
            for (phrase, count) in PhraseOccurrenceScanner.counts(ofOrdered: ordered, in: text) {
                result[phrase, default: 0] += count
            }
        }
        return result
    }
}
