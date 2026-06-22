//
//  SpeechMetricsAnalyzer.swift
//  VoiceInk
//
//  Analyzes transcription text and computes:
//  - filler words
//  - anglicisms
//  - average sentence length
//  - WPM
//  - EN/RU ratio
//
//  The filler-word list comes from speech-tracker.md (99 - Claude Context/).
//

import Foundation
import OSLog

enum SpeechMetricsAnalyzer {

    private static let logger = Logger(
        subsystem: "com.morqan.voiceink",
        category: "SpeechMetricsAnalyzer"
    )

    /// The user's filler-word list from speech-tracker.md.
    /// Stored in lowercase for case-insensitive matching.
    /// Multi-word ones ("как бы", "это самое", "в общем") go through PhraseOccurrenceScanner (word boundaries).
    static let singleWordFillers: Set<String> = [
        "короче", "типа", "ну", "вот",
        "блин", "значит", "собственно", "понимаешь",
        "допустим", "окей", "ок", "эээ", "эм", "ммм"
    ]

    static let multiWordFillers: [String] = [
        "как бы", "это самое", "в общем",
        "то есть", "так сказать"
    ]

    /// Minimum transcription length (in words) required to record a metric.
    /// Anything shorter is statistically insignificant (see speech-tracker.md rule: >=15 words).
    static let minWordsThreshold = 15

    /// Analyzes a transcription and returns a populated SpeechMetric.
    /// Does not persist to the database — the caller does that.
    /// Returns nil if the transcription is shorter than the threshold (statistically insignificant).
    ///
    /// - Parameters:
    ///   - text: text to analyze (preferably the raw ASR output).
    ///   - rawText: raw text to store in SpeechMetric.rawText (defaults to text).
    ///   - activeFillers: the user's active set of filler phrases from AutoFillerDetector;
    ///     nil → built-in core only (for early history / fallback).
    static func analyze(
        text: String,
        durationSeconds: Double,
        rawText: String? = nil,
        activeFillers: Set<String>? = nil
    ) -> SpeechMetric? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }

        let words = extractWords(from: cleanText)
        guard words.count >= minWordsThreshold else {
            logger.debug("Speech too short (\(words.count) words), skipping metric")
            return nil
        }

        let sentenceCount = countSentences(in: cleanText)
        let avgSentenceLength = sentenceCount > 0
            ? Double(words.count) / Double(sentenceCount)
            : Double(words.count)

        let avgSentenceComplexity = calculateComplexity(text: cleanText, sentenceCount: sentenceCount)

        let wpm = durationSeconds > 0
            ? Double(words.count) / (durationSeconds / 60.0)
            : 0

        let fillersByWord = countFillers(text: cleanText, activeFillers: activeFillers)
        let fillerCount = fillersByWord.values.reduce(0, +)

        let anglicismsByWord = countAnglicisms(words: words)
        let anglicismCount = anglicismsByWord.values.reduce(0, +)

        let enRuRatio = calculateEnRuRatio(text: cleanText)

        let repetitionsByWord = countRepetitions(
            words: words,
            fillers: Set(fillersByWord.keys),
            anglicisms: Set(anglicismsByWord.keys)
        )

        let selfCorrections = countSelfCorrections(text: cleanText, words: words)

        let metric = SpeechMetric(
            timestamp: Date(),
            durationSeconds: durationSeconds,
            wordCount: words.count,
            sentenceCount: sentenceCount,
            avgSentenceLength: avgSentenceLength,
            avgSentenceComplexity: avgSentenceComplexity,
            wpm: wpm,
            fillerCount: fillerCount,
            fillersByWordJSON: encodeJSON(fillersByWord),
            anglicismCount: anglicismCount,
            anglicismsByWordJSON: encodeJSON(anglicismsByWord),
            enRuRatio: enRuRatio,
            repetitionsByWordJSON: encodeJSON(repetitionsByWord),
            selfCorrectionCount: selfCorrections.total,
            selfCorrectionsByWordJSON: encodeJSON(selfCorrections.byMarker),
            text: cleanText,
            rawText: rawText ?? cleanText
        )

        logger.info("""
            Analyzed: \(words.count) words, \(sentenceCount) sentences, \
            avg sentence \(String(format: "%.1f", avgSentenceLength)) words, \
            WPM \(String(format: "%.1f", wpm)), \
            \(fillerCount) fillers, \(anglicismCount) anglicisms, \
            \(repetitionsByWord.count) repetitions
            """)

        return metric
    }

    // MARK: - Word extraction

    /// Splits text into words. Ignores punctuation.
    static func extractWords(from text: String) -> [String] {
        return text
            .components(separatedBy: wordChars.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    private static let wordChars = CharacterSet.letters.union(.init(charactersIn: "-'"))

    /// Counts words the same way `extractWords` splits them (maximal runs of letters
    /// plus `-`/`'`), but without allocating the token array or lowercasing — for
    /// callers that only need the count.
    static func wordCount(in text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if wordChars.contains(scalar) {
                if !inWord { count += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return count
    }

    // MARK: - Sentence counting

    /// Counts the number of sentences by the terminators . ? ! and ellipses.
    /// An ellipsis = one sentence, not three. Numbers with a dot ("3.14", "1.000.000")
    /// and the Unicode "…" do not split a sentence.
    static func countSentences(in text: String) -> Int {
        var normalized = text
        // Unicode ellipsis → a single terminator.
        normalized = normalized.replacingOccurrences(of: "…", with: ".")
        // A dot/comma inside a number (3.14, 1.000.000) is not the end of a sentence.
        normalized = normalized.replacingOccurrences(
            of: "(?<=\\d)[.,](?=\\d)", with: "", options: .regularExpression
        )
        // Any run of terminators ("...", "?!", "!!", "....") = one.
        normalized = normalized.replacingOccurrences(
            of: "[.?!]{2,}", with: ".", options: .regularExpression
        )

        let terminators: Set<Character> = [".", "?", "!"]
        let count = normalized.filter { terminators.contains($0) }.count

        // If there are no terminators, count it as 1 sentence (if the text is not empty).
        return max(count, 1)
    }

    // MARK: - Fillers

    /// Counts filler words in the text against the active set of phrases.
    /// Everything goes through PhraseOccurrenceScanner (word boundaries, longest phrases first,
    /// no double-counting of overlaps: "ну вот" doesn't also yield "ну"+"вот").
    /// activeFillers nil → built-in core (singleWordFillers ∪ multiWordFillers).
    static func countFillers(text: String, activeFillers: Set<String>? = nil) -> [String: Int] {
        let phrases: [String]
        if let activeFillers {
            phrases = Array(activeFillers)
        } else {
            phrases = Array(singleWordFillers) + multiWordFillers
        }
        return PhraseOccurrenceScanner.counts(of: phrases, in: text).filter { $0.value > 0 }
    }

    // MARK: - Anglicisms

    /// Counts anglicisms — words containing Latin letters within predominantly Russian text.
    /// Words of 1-2 Latin letters are ignored (they may be abbreviations in a Cyrillic context).
    /// If the overall share of Latin letters > 50%, the text is treated as English and anglicisms are not flagged.
    static func countAnglicisms(words: [String]) -> [String: Int] {
        let latinChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")

        // Count how many words are purely Latin.
        var counts: [String: Int] = [:]

        // Before counting, assess the overall context. If >50% of words are Latin, this is English text.
        let latinWords = words.filter { isAllLatin($0, allowedSet: latinChars) }
        let latinRatio = words.isEmpty ? 0 : Double(latinWords.count) / Double(words.count)

        // If the text is predominantly English, don't count anglicisms (it's English itself).
        guard latinRatio < 0.5 else {
            return [:]
        }

        // Otherwise, every Latin word of >= 3 characters counts as an anglicism.
        for word in words {
            if word.count >= 3 && isAllLatin(word, allowedSet: latinChars) {
                counts[word, default: 0] += 1
            }
        }

        return counts
    }

    private static func isAllLatin(_ word: String, allowedSet: CharacterSet) -> Bool {
        let stripped = word.lowercased().unicodeScalars.filter { $0.value < 128 } // basic ASCII filter
        guard !stripped.isEmpty else { return false }
        return stripped.allSatisfy { allowedSet.contains($0) }
    }

    // MARK: - EN/RU ratio

    /// Computes the share of Latin letters among all letters (0..1).
    static func calculateEnRuRatio(text: String) -> Double {
        var latinCount = 0
        var totalLetters = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                totalLetters += 1
                if scalar.value < 128 && CharacterSet.letters.contains(scalar) {
                    latinCount += 1
                }
            }
        }

        guard totalLetters > 0 else { return 0 }
        return Double(latinCount) / Double(totalLetters)
    }

    // MARK: - Sentence complexity

    /// Subordination markers for Russian — conjunctions and relative pronouns.
    /// Each occurrence in the text = +1 to complexity (per sentence average).
    /// The bare "что" that used to be here was removed: this ultra-frequent word ("что делать?",
    /// "а что по срокам") contributed the lion's share of the score without any subordination.
    static let subordinationMarkers: [String] = [
        "который", "которая", "которое", "которые", "которых", "которым", "которой",
        "чтобы",
        "если", "когда", "пока", "хотя",
        "потому что", "так как", "несмотря на",
        "поскольку", "ибо",
        "будто", "словно", "как будто"
    ]

    /// Computes the average sentence complexity. The higher it is, the more subordinate
    /// constructions there are (long enveloping sentences, like Erickson's).
    ///
    /// Formula: (subordination_markers + 0.3 × commas) / sentenceCount
    /// Markers go through PhraseOccurrenceScanner: word boundaries + no double-counting
    /// of nesting ("как будто" no longer also yields "будто").
    static func calculateComplexity(text: String, sentenceCount: Int) -> Double {
        guard sentenceCount > 0 else { return 0 }

        let markerHits = PhraseOccurrenceScanner.totalCount(of: subordinationMarkers, in: text)
        let commaCount = text.filter { $0 == "," }.count
        let totalScore = Double(markerHits) + 0.3 * Double(commaCount)
        return totalScore / Double(sentenceCount)
    }

    // MARK: - Repetitions

    /// Minimum frequency for flagging a word as a "repetition".
    /// 5 is the balance between "repeated normally" and "got stuck in a loop".
    static let repetitionThreshold = 5

    /// Minimum word length to be considered for repetitions.
    /// Short ones ("что", "как", "но", "то") are high-frequency function words, not a marker.
    static let repetitionMinWordLength = 4

    /// Counts words that are repeated >= 5 times within a single dictation.
    /// Excludes: filler words (counted separately), anglicisms, short words.
    static func countRepetitions(
        words: [String],
        fillers: Set<String>,
        anglicisms: Set<String>
    ) -> [String: Int] {
        var totals: [String: Int] = [:]
        for word in words {
            guard word.count >= repetitionMinWordLength else { continue }
            guard !fillers.contains(word) else { continue }
            guard !anglicisms.contains(word) else { continue }
            totals[word, default: 0] += 1
        }
        return totals.filter { $0.value >= repetitionThreshold }
    }

    // MARK: - Self-corrections (smoothness)

    /// Minimum word length to be considered for an immediate consecutive repeat.
    /// Short ones ("и", "а", "по") are noise/function words, not a stumble.
    static let restartMinWordLength = 3

    /// Counts self-corrections for the "smoothness" metric:
    /// — repair markers (phrases from SelfCorrectionLexicon, scanner with word boundaries);
    /// — immediate consecutive word repeats ("это это", "надо надо") as restarts.
    /// Returns (byMarker — for highlighting/listing, phrases only; total — markers + repeats).
    static func countSelfCorrections(text: String, words: [String]) -> (byMarker: [String: Int], total: Int) {
        let byMarker = PhraseOccurrenceScanner.counts(of: SelfCorrectionLexicon.markers, in: text)
            .filter { $0.value > 0 }
        let markerTotal = byMarker.values.reduce(0, +)
        let restarts = countAdjacentRepeats(words: words)
        return (byMarker, markerTotal + restarts)
    }

    /// Immediate consecutive repeats of the same word. Emphatic doublings
    /// ("так-так", "ну-ну") and overly short words are not counted.
    static func countAdjacentRepeats(words: [String]) -> Int {
        guard words.count > 1 else { return 0 }
        var count = 0
        for i in 1..<words.count {
            let w = words[i]
            guard w == words[i - 1] else { continue }
            guard w.count >= restartMinWordLength else { continue }
            guard !SelfCorrectionLexicon.reduplicationAllowed.contains(w) else { continue }
            count += 1
        }
        return count
    }

    // MARK: - JSON helper

    private static func encodeJSON(_ dict: [String: Int]) -> String {
        JSONCoding.encode(dict)
    }
}
