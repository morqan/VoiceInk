//
//  SpeechStreaks.swift
//  VoiceInk
//
//  Consecutive-days-on-target streaks for the Coach tab. Pure value logic over a
//  SpeechMetric array so it can run off the main thread — the view computes it in a
//  background ModelContext (same pattern as the Words tab) and only the Int triple
//  crosses back to the main actor.
//

import Foundation

enum SpeechStreaks {
    /// All three streaks (filler-free / anglicism-free / short-sentence), in days.
    static func compute(_ metrics: [SpeechMetric], now: Date = Date()) -> (filler: Int, anglicism: Int, sentence: Int) {
        let filler = streak(metrics, now: now) { fillers, _, words, _ in
            guard words > 0 else { return false }
            return Double(fillers) / Double(words) * 100 <= 2.0
        }
        let anglicism = streak(metrics, now: now) { _, anglicisms, words, _ in
            guard words > 0 else { return false }
            return Double(anglicisms) / Double(words) * 100 <= 1.0
        }
        let sentence = streak(metrics, now: now) { _, _, words, sentences in
            guard words > 0, sentences > 0 else { return false }
            // Daily aggregate: day words ÷ day sentences (weighted, as on the card).
            return Double(words) / Double(sentences) <= 18.0
        }
        return (filler, anglicism, sentence)
    }

    /// Groups metrics by day and counts consecutive on-target days back from today.
    /// Days with no data are skipped (they don't break the streak); the first day
    /// with data that fails the check ends it.
    private static func streak(
        _ metrics: [SpeechMetric],
        now: Date,
        passedCheck: (Int /* fillers */, Int /* anglicisms */, Int /* words */, Int /* sentences */) -> Bool
    ) -> Int {
        let cal = Calendar.current
        var byDay: [Date: (fillers: Int, anglicisms: Int, words: Int, sentences: Int)] = [:]
        for m in metrics {
            let day = cal.startOfDay(for: m.timestamp)
            var d = byDay[day, default: (0, 0, 0, 0)]
            d.fillers += m.fillerCount
            d.anglicisms += m.anglicismCount
            d.words += m.wordCount
            d.sentences += m.sentenceCount
            byDay[day] = d
        }
        guard !byDay.isEmpty else { return 0 }

        var count = 0
        var cursor = cal.startOfDay(for: now)
        let earliest = byDay.keys.min() ?? cursor

        while cursor >= earliest {
            if let d = byDay[cursor] {
                if passedCheck(d.fillers, d.anglicisms, d.words, d.sentences) {
                    count += 1
                } else {
                    break
                }
            }
            // No data that day — skip without breaking the streak. If date math ever
            // fails, terminate the walk rather than resetting to `earliest` (which
            // would spin forever).
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }
}
