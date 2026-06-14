//
//  DailyExercise.swift
//  VoiceInk
//
//  "Exercise of the day" for the speech trainer: a speaking prompt + a few target
//  marker phrases (the ones the user under-uses) + the profile's target pace.
//  The user dictates on the topic with their normal hotkey; the training card then
//  scores that latest dictation against these targets. Pure generation, no recording.
//

import Foundation

struct DailyExercise {
    /// Localized speaking prompt for today.
    let topic: String
    /// Marker phrases from the active profile the user has been using the least.
    let targetPhrases: [String]
    /// Target speaking pace (WPM) from the active profile.
    let targetWPM: Double
    /// Whether there is an active style profile backing the targets.
    var hasProfile: Bool
}

enum DailyExerciseGenerator {

    /// Built-in speaking prompts, rotated by day so the exercise changes daily.
    private static let topics: [(en: String, ru: String)] = [
        (en: "Describe your current project in 60 seconds",
         ru: "Опиши свой текущий проект за 60 секунд"),
        (en: "Convince me to try something you love",
         ru: "Убеди меня попробовать то, что ты любишь"),
        (en: "Explain something complex in simple words",
         ru: "Объясни что-то сложное простыми словами"),
        (en: "Tell the story of your best decision this year",
         ru: "Расскажи историю своего лучшего решения в этом году"),
        (en: "Pitch yourself to a stranger in 30 seconds",
         ru: "Представь себя незнакомцу за 30 секунд"),
        (en: "Argue the opposite of what you believe",
         ru: "Поспорь против того, во что веришь"),
        (en: "Describe your morning as if it were an adventure",
         ru: "Опиши своё утро так, будто это приключение"),
        (en: "Give advice to yourself five years ago",
         ru: "Дай совет себе пятилетней давности")
    ]

    /// Build today's exercise from the active profile and recent history.
    static func forToday(profile: VoiceProfileTarget?, metrics: [SpeechMetric], date: Date = Date()) -> DailyExercise {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let pair = topics[(dayOfYear - 1 + topics.count) % topics.count]
        let topic = L10n.t(en: pair.en, ru: pair.ru)

        let phrases = profile.map { underusedPhrases($0, in: metrics) } ?? []
        let wpm = profile?.targetWPM ?? 130
        return DailyExercise(topic: topic, targetPhrases: phrases, targetWPM: wpm, hasProfile: profile != nil)
    }

    /// Pick the profile marker phrases that appear least in recent dictations —
    /// the ones worth practicing today. Ties keep the profile's own order.
    static func underusedPhrases(_ profile: VoiceProfileTarget, in metrics: [SpeechMetric], limit: Int = 3) -> [String] {
        let phrases = profile.markerPhrases
        guard !phrases.isEmpty else { return [] }

        var counts: [String: Int] = [:]
        for metric in metrics.prefix(30) {
            let source = metric.rawText.isEmpty ? metric.text : metric.rawText
            for (phrase, count) in PhraseOccurrenceScanner.counts(of: phrases, in: source) {
                counts[phrase, default: 0] += count
            }
        }

        return Array(
            phrases
                .enumerated()
                .sorted { lhs, rhs in
                    let lc = counts[lhs.element.lowercased()] ?? 0
                    let rc = counts[rhs.element.lowercased()] ?? 0
                    return lc == rc ? lhs.offset < rhs.offset : lc < rc
                }
                .map { $0.element }
                .prefix(limit)
        )
    }
}
