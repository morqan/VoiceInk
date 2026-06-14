//
//  SpeechAggregates.swift
//  VoiceInk
//
//  Pure period aggregations over [SpeechMetric] — pulled out of SpeechAnalyticsView so
//  the analytics tabs can compute their numbers without depending on the parent view.
//  All weighting/pooling rules live here (single source of truth).
//

import Foundation

enum SpeechAggregates {

    static func wordCount(_ ms: [SpeechMetric]) -> Int {
        ms.reduce(0) { $0 + $1.wordCount }
    }

    /// Fillers per 100 words — pooled over the period.
    static func fillerRate(_ ms: [SpeechMetric]) -> Double {
        let words = wordCount(ms)
        guard words > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.fillerCount }) / Double(words) * 100
    }

    static func anglicismRate(_ ms: [SpeechMetric]) -> Double {
        let words = wordCount(ms)
        guard words > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.anglicismCount }) / Double(words) * 100
    }

    /// Self-corrections per 100 words (inverse smoothness) — pooled.
    static func selfCorrectionRate(_ ms: [SpeechMetric]) -> Double {
        let words = wordCount(ms)
        guard words > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.selfCorrectionCount }) / Double(words) * 100
    }

    static func sentenceLength(_ ms: [SpeechMetric]) -> Double {
        let sentences = ms.reduce(0) { $0 + $1.sentenceCount }
        guard sentences > 0 else { return 0 }
        return Double(wordCount(ms)) / Double(sentences)
    }

    /// WPM — pooled: all words ÷ total recording time (not an unweighted per-session mean).
    static func wpm(_ ms: [SpeechMetric]) -> Double {
        let timed = ms.filter { $0.durationSeconds > 0 && $0.wordCount > 0 }
        let minutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        guard minutes > 0 else { return 0 }
        return Double(timed.reduce(0) { $0 + $1.wordCount }) / minutes
    }

    /// EN/RU — weighted by session word count (a long session weighs more).
    static func enRatio(_ ms: [SpeechMetric]) -> Double {
        let words = wordCount(ms)
        guard words > 0 else { return 0 }
        return ms.reduce(0.0) { $0 + $1.enRuRatio * Double($1.wordCount) } / Double(words)
    }

    /// Complexity — weighted by words, zero sessions included (excluding them biased it up).
    static func complexity(_ ms: [SpeechMetric]) -> Double {
        let words = wordCount(ms)
        guard words > 0 else { return 0 }
        return ms.reduce(0.0) { $0 + $1.avgSentenceComplexity * Double($1.wordCount) } / Double(words)
    }

    /// Aggregate a per-metric word→count dictionary across the period, sorted desc.
    static func topWords(_ ms: [SpeechMetric], _ extract: (SpeechMetric) -> [String: Int]) -> [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in ms {
            for (word, count) in extract(metric) {
                totals[word, default: 0] += count
            }
        }
        return totals.map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}
