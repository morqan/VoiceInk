//
//  AutoFillerDetector.swift
//  VoiceInk
//
//  Auto-detection of the user's filler words from the history of RAW texts.
//  No manual lists: a word is flagged as an "active filler" if in speech it is
//  both FREQUENT and UBIQUITOUS at the same time (appears in a large share of
//  dictations regardless of topic) — a topical word is never ubiquitous.
//
//  A new word outside the lexicon is first "under observation" (not counted) and
//  is promoted to counting only if it holds steadily for >= 10 days across >= 6 dictations.
//
//  Perf: the heavy history scan is NOT run in the pipeline on every dictation —
//  the active list is kept in a cache (UserDefaults), refreshed from UI/recalc.
//  Marker phrases of the active style are excluded (otherwise they conflict with
//  the coach: "слушайте", "значит" are both filler candidates and rhetorical markers).
//

import Foundation

enum AutoFillerDetector {

    // MARK: - Parameters (rate is per 100 words)

    private static let windowDays = 90
    private static let minDocs = 8
    private static let minWords = 1000

    private static let lexiconRate = 0.5            // >= 0.5/100 = 1 per 200 words
    private static let lexiconUbiquity = 0.25       // appears in >= 25% of dictations

    private static let noveltyActiveRate = 0.4
    private static let noveltyActiveUbiquity = 0.25
    private static let noveltyActiveDocs = 6
    private static let noveltyActiveSpanDays = 10.0

    private static let noveltyObserveRate = 0.3
    private static let noveltyObserveUbiquity = 0.15
    private static let noveltyObserveDocs = 4

    private static let multiRate = 0.15
    private static let multiUbiquity = 0.20

    private static let cacheKey = "AutoFillerActiveCache"

    // MARK: - Types

    struct FillerEntry: Identifiable {
        let phrase: String
        var id: String { phrase }
        let ratePer100: Double
        let occurrences: Int
        let docs: Int
    }

    struct FillerChange: Identifiable {
        let phrase: String
        var id: String { phrase }
        let rateNow: Double
        let ratePrev: Double
        var delta: Double { rateNow - ratePrev }
    }

    struct Dynamics {
        var active: [FillerEntry] = []
        var observing: [FillerEntry] = []
        var appeared: [FillerChange] = []
        var disappeared: [FillerChange] = []
        var grew: [FillerChange] = []
        var dropped: [FillerChange] = []
        var hasHistory: Bool = false   // analyze ran (enough history)
        var enoughData: Bool = false   // enough to compare two windows (dynamics)
    }

    /// A prepared window document: tokens and counts are computed once.
    private struct Doc {
        let date: Date
        let source: String
        let tokens: [String]
        var wordCount: Int { tokens.count }
    }

    // MARK: - Active set for counting

    private static let coreFillers: Set<String> = Set(SpeechMetricsAnalyzer.singleWordFillers)
        .union(SpeechMetricsAnalyzer.multiWordFillers)

    /// Instant: core ∪ cache. Used in the pipeline (no history scan).
    static func cachedActiveFillers() -> Set<String> {
        var set = coreFillers
        set.formUnion(UserDefaults.standard.stringArray(forKey: cacheKey) ?? [])
        return set
    }

    /// Recompute the active list and store it in the cache (call from UI/recalc, not from the pipeline).
    @discardableResult
    static func refreshCache(history: [SpeechMetric], excluding: Set<String> = [], now: Date = Date()) -> Set<String> {
        let dyn = analyze(history: history, excluding: excluding, now: now)
        let auto = dyn.active.map { $0.phrase }
        UserDefaults.standard.set(auto, forKey: cacheKey)
        return coreFillers.union(auto)
    }

    /// Write the active list to the cache directly — when dynamics is already computed,
    /// to avoid scanning the history a second time (refreshCache runs analyze again).
    static func writeCache(active phrases: [String]) {
        UserDefaults.standard.set(phrases, forKey: cacheKey)
    }

    /// Full recompute of the active list from history (for recalc).
    static func activeFillers(history: [SpeechMetric], excluding: Set<String> = [], now: Date = Date()) -> Set<String> {
        let dyn = analyze(history: history, excluding: excluding, now: now)
        return coreFillers.union(dyn.active.map { $0.phrase })
    }

    // MARK: - Full picture for the UI

    static func computeDynamics(
        history: [SpeechMetric],
        current: [SpeechMetric],
        previous: [SpeechMetric],
        excluding: Set<String> = [],
        now: Date = Date()
    ) -> Dynamics {
        var dyn = analyze(history: history, excluding: excluding, now: now)

        let phrases = Set(dyn.active.map { $0.phrase }).union(coreFillers).subtracting(excluding)
        let cur = occAndWords(Array(phrases), in: current)
        let prev = occAndWords(Array(phrases), in: previous)
        let enough = cur.words >= 600 && prev.words >= 600 && current.count >= 5 && previous.count >= 5
        dyn.enoughData = enough
        guard enough else { return dyn }

        for phrase in phrases {
            let occNow = cur.occ[phrase] ?? 0
            let occPrev = prev.occ[phrase] ?? 0
            let rNow = Double(occNow) / Double(cur.words) * 100
            let rPrev = Double(occPrev) / Double(prev.words) * 100
            let change = FillerChange(phrase: phrase, rateNow: rNow, ratePrev: rPrev)
            let significant = abs(rNow - rPrev) >= max(0.15, 0.30 * rPrev)

            if occPrev == 0 && occNow >= 3 {
                dyn.appeared.append(change)
            } else if occNow == 0 && occPrev >= 3 {
                dyn.disappeared.append(change)
            } else if occNow >= 3 && rNow > rPrev && significant {
                dyn.grew.append(change)
            } else if occPrev >= 3 && rNow < rPrev && significant {
                dyn.dropped.append(change)
            }
        }
        dyn.appeared.sort { $0.rateNow > $1.rateNow }
        dyn.disappeared.sort { $0.ratePrev > $1.ratePrev }
        dyn.grew.sort { $0.delta > $1.delta }
        dyn.dropped.sort { $0.delta < $1.delta }
        return dyn
    }

    /// Daily rate series (per 100 words) for a set of words — for the sparkline.
    /// Computed once in .task, not in body.
    static func dailyRateSeries(phrases: [String], in metrics: [SpeechMetric]) -> [String: [(date: Date, value: Double)]] {
        guard !phrases.isEmpty else { return [:] }
        let ordered = PhraseOccurrenceScanner.normalizedOrdered(phrases)
        let cal = Calendar.current
        var byDay: [Date: (occ: [String: Int], words: Int)] = [:]
        for m in metrics {
            let day = cal.startOfDay(for: m.timestamp)
            let src = sourceText(m)
            let counts = PhraseOccurrenceScanner.counts(ofOrdered: ordered, in: src)
            var entry = byDay[day, default: (occ: [:], words: 0)]
            for (p, c) in counts { entry.occ[p, default: 0] += c }
            entry.words += SpeechMetricsAnalyzer.wordCount(in: src)
            byDay[day] = entry
        }
        var result: [String: [(date: Date, value: Double)]] = [:]
        for phrase in phrases {
            let series = byDay
                .map { (date: $0.key, value: $0.value.words > 0 ? Double($0.value.occ[phrase] ?? 0) / Double($0.value.words) * 100 : 0) }
                .sorted { $0.date < $1.date }
            result[phrase] = series
        }
        return result
    }

    // MARK: - Analysis core

    private static func analyze(history: [SpeechMetric], excluding: Set<String>, now: Date) -> Dynamics {
        var dyn = Dynamics()
        let cal = Calendar.current
        let windowStart = cal.date(byAdding: .day, value: -windowDays, to: now) ?? now

        // Window documents — tokenize each once
        let docs: [Doc] = history.compactMap { m in
            guard m.timestamp >= windowStart else { return nil }
            let src = sourceText(m)
            let tokens = SpeechMetricsAnalyzer.extractWords(from: src)
            guard tokens.count >= 15 else { return nil }
            return Doc(date: m.timestamp, source: src, tokens: tokens)
        }
        let wordsTotal = docs.reduce(0) { $0 + $1.wordCount }
        guard docs.count >= minDocs, wordsTotal >= minWords else { return dyn }
        let docsTotal = Double(docs.count)
        let docMin = max(3, Int((0.20 * docsTotal).rounded(.up)))   // absolute minimum number of dictations

        // Unigram frequency profile
        var occ: [String: Int] = [:]
        var docCount: [String: Int] = [:]
        var firstDate: [String: Date] = [:]
        var lastDate: [String: Date] = [:]
        for d in docs {
            var seen = Set<String>()
            for w in d.tokens {
                occ[w, default: 0] += 1
                if seen.insert(w).inserted {
                    docCount[w, default: 0] += 1
                    if firstDate[w] == nil || d.date < firstDate[w]! { firstDate[w] = d.date }
                    if lastDate[w] == nil || d.date > lastDate[w]! { lastDate[w] = d.date }
                }
            }
        }

        let core = SpeechMetricsAnalyzer.singleWordFillers

        // 1) Single-word candidates from the lexicon
        for word in FillerLexicon.singleWordCandidates where !core.contains(word) && !excluding.contains(word) {
            let o = occ[word] ?? 0
            let dc = docCount[word] ?? 0
            guard o > 0, dc >= docMin else { continue }
            let rate = Double(o) / Double(wordsTotal) * 100
            let ubiq = Double(dc) / docsTotal
            if rate >= lexiconRate && ubiq >= lexiconUbiquity {
                dyn.active.append(FillerEntry(phrase: word, ratePer100: rate, occurrences: o, docs: dc))
            }
        }

        // 2) New words (not in the core, the lexicon, the stop list, or the markers)
        for (word, o) in occ {
            guard !core.contains(word),
                  !FillerLexicon.singleWordCandidates.contains(word),
                  !FillerLexicon.neverCount.contains(word),
                  !excluding.contains(word),
                  word.count >= 3, word.count <= 12,
                  !word.contains("-"), !word.contains("'"),
                  !isLatin(word) else { continue }
            let dc = docCount[word] ?? 0
            guard dc >= docMin else { continue }
            let rate = Double(o) / Double(wordsTotal) * 100
            let ubiq = Double(dc) / docsTotal
            let spanDays = (lastDate[word]?.timeIntervalSince(firstDate[word] ?? now) ?? 0) / 86400.0

            if rate >= noveltyActiveRate && ubiq >= noveltyActiveUbiquity
                && dc >= noveltyActiveDocs && spanDays >= noveltyActiveSpanDays {
                dyn.active.append(FillerEntry(phrase: word, ratePer100: rate, occurrences: o, docs: dc))
            } else if rate >= noveltyObserveRate && ubiq >= noveltyObserveUbiquity && dc >= noveltyObserveDocs {
                dyn.observing.append(FillerEntry(phrase: word, ratePer100: rate, occurrences: o, docs: dc))
            }
        }

        // 3) Multi-word candidates (via the scanner)
        let multiCandidates = FillerLexicon.multiWordCandidates.filter { !excluding.contains($0) }
        let multi = multiOccurrences(multiCandidates, in: docs)
        for (phrase, info) in multi {
            guard info.docs >= docMin else { continue }
            let rate = Double(info.occ) / Double(wordsTotal) * 100
            let ubiq = Double(info.docs) / docsTotal
            if rate >= multiRate && ubiq >= multiUbiquity {
                dyn.active.append(FillerEntry(phrase: phrase, ratePer100: rate, occurrences: info.occ, docs: info.docs))
            }
        }

        dyn.active.sort { $0.ratePer100 > $1.ratePer100 }
        dyn.observing.sort { $0.ratePer100 > $1.ratePer100 }
        dyn.hasHistory = true
        return dyn
    }

    // MARK: - Helpers

    /// Text for analysis: the raw ASR output if available, otherwise the cleaned text (older records).
    static func sourceText(_ m: SpeechMetric) -> String {
        m.rawText.isEmpty ? m.text : m.rawText
    }

    private static func occAndWords(_ phrases: [String], in metrics: [SpeechMetric]) -> (occ: [String: Int], words: Int) {
        let ordered = PhraseOccurrenceScanner.normalizedOrdered(phrases)
        var occ: [String: Int] = [:]
        var words = 0
        for m in metrics {
            let src = sourceText(m)
            words += SpeechMetricsAnalyzer.wordCount(in: src)
            for (p, c) in PhraseOccurrenceScanner.counts(ofOrdered: ordered, in: src) {
                occ[p, default: 0] += c
            }
        }
        return (occ, words)
    }

    private static func multiOccurrences(_ phrases: [String], in docs: [Doc]) -> [String: (occ: Int, docs: Int)] {
        var result: [String: (occ: Int, docs: Int)] = [:]
        for d in docs {
            for (p, c) in PhraseOccurrenceScanner.counts(of: phrases, in: d.source) where c > 0 {
                var entry = result[p, default: (0, 0)]
                entry.occ += c
                entry.docs += 1
                result[p] = entry
            }
        }
        return result
    }

    private static func isLatin(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { $0.value < 128 } && word.contains { $0.isLetter }
    }
}
