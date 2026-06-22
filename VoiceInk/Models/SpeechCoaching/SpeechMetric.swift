//
//  SpeechMetric.swift
//  VoiceInk
//
//  Speech metrics for each transcription.
//  Written after every completed dictation in saveTranscriptionAndPostCompletion.
//
//  Computes: filler words, anglicisms, average sentence length, WPM, EN/RU ratio.
//

import Foundation
import SwiftData

@Model
final class SpeechMetric {
    /// Unique record ID
    var id: UUID = UUID()

    /// When the dictation was completed
    var timestamp: Date = Date()

    /// Audio duration in seconds
    var durationSeconds: Double = 0

    /// Total word count in the text
    var wordCount: Int = 0

    /// Number of sentences (split on .?!)
    var sentenceCount: Int = 0

    /// Average sentence length in words
    var avgSentenceLength: Double = 0

    /// Average sentence complexity. Computed from subordination marker phrases
    /// («который», «потому что», «если», «когда», «пока», «чтобы», etc.)
    /// plus commas (as a proxy for complex constructions).
    /// 0 = plain, simple speech. 5+ = subordinate constructions every time.
    var avgSentenceComplexity: Double = 0

    /// WPM = wordCount / (durationSeconds / 60)
    var wpm: Double = 0

    /// Total number of filler words in this dictation
    var fillerCount: Int = 0

    /// JSON serialization {"короче": 3, "типа": 1, ...}
    /// SwiftData doesn't play well with [String: Int], so we store it as JSON.
    var fillersByWordJSON: String = "{}"

    /// Total number of anglicisms
    var anglicismCount: Int = 0

    /// JSON serialization {"deadline": 2, "meeting": 1, ...}
    var anglicismsByWordJSON: String = "{}"

    /// Ratio of Latin characters to the total letter count (0..1)
    /// 0 = pure Russian, 1 = pure English
    var enRuRatio: Double = 0

    /// Repetitions — words that occurred ≥ 5 times in a single dictation (excluding fillers/anglicisms).
    /// JSON serialization {"проект": 7, "задача": 5, ...}
    var repetitionsByWordJSON: String = "{}"

    /// Self-corrections (the "smoothness" metric): repair markers + immediate
    /// back-to-back word repeats. Total count per dictation. Old records are 0 until the v4 migration.
    var selfCorrectionCount: Int = 0

    /// JSON serialization of repair MARKERS only {"вернее": 2, "или нет": 1, ...}
    /// (for highlighting and the list). Back-to-back repeats are not written here — otherwise it would
    /// highlight every occurrence of a frequent word. The marker sum ≤ selfCorrectionCount.
    var selfCorrectionsByWordJSON: String = "{}"

    /// Cleaned transcription text (the one that went to input/history).
    var text: String = ""

    /// The rawest ASR output (before filters/replacements/cleanup) — filler
    /// metrics are computed from it so filters don't undercount. Empty for old records
    /// (raw text wasn't saved back then) — in that case analysis falls back to text.
    var rawText: String = ""

    // MARK: - Prosody (voice) — Phase 1, computed in background from the audio file.

    /// Recording this metric was derived from (for prosody DSP). Empty for old records.
    var audioFileURL: String = ""

    /// Whether prosody DSP has run for this record (guards backfill + UI gating).
    var prosodyAnalyzed: Bool = false

    /// Share of the speaking span spent in silence, % (energy VAD).
    var pauseRatioPercent: Double = 0

    /// Median fundamental frequency, Hz.
    var pitchMeanHz: Double = 0

    /// F0 spread in semitones — low = monotone, high = expressive.
    var pitchRangeSemitones: Double = 0

    /// Loudness spread (dBFS) during speech — vocal dynamics.
    var loudnessRangeDb: Double = 0

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        durationSeconds: Double = 0,
        wordCount: Int = 0,
        sentenceCount: Int = 0,
        avgSentenceLength: Double = 0,
        avgSentenceComplexity: Double = 0,
        wpm: Double = 0,
        fillerCount: Int = 0,
        fillersByWordJSON: String = "{}",
        anglicismCount: Int = 0,
        anglicismsByWordJSON: String = "{}",
        enRuRatio: Double = 0,
        repetitionsByWordJSON: String = "{}",
        selfCorrectionCount: Int = 0,
        selfCorrectionsByWordJSON: String = "{}",
        text: String = "",
        rawText: String = "",
        audioFileURL: String = "",
        prosodyAnalyzed: Bool = false,
        pauseRatioPercent: Double = 0,
        pitchMeanHz: Double = 0,
        pitchRangeSemitones: Double = 0,
        loudnessRangeDb: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.sentenceCount = sentenceCount
        self.avgSentenceLength = avgSentenceLength
        self.avgSentenceComplexity = avgSentenceComplexity
        self.wpm = wpm
        self.fillerCount = fillerCount
        self.fillersByWordJSON = fillersByWordJSON
        self.anglicismCount = anglicismCount
        self.anglicismsByWordJSON = anglicismsByWordJSON
        self.enRuRatio = enRuRatio
        self.repetitionsByWordJSON = repetitionsByWordJSON
        self.selfCorrectionCount = selfCorrectionCount
        self.selfCorrectionsByWordJSON = selfCorrectionsByWordJSON
        self.text = text
        self.rawText = rawText
        self.audioFileURL = audioFileURL
        self.prosodyAnalyzed = prosodyAnalyzed
        self.pauseRatioPercent = pauseRatioPercent
        self.pitchMeanHz = pitchMeanHz
        self.pitchRangeSemitones = pitchRangeSemitones
        self.loudnessRangeDb = loudnessRangeDb
    }

    // MARK: - Computed

    /// Filler rate per 100 words. Target: ≤ 2.
    var fillerRatePer100Words: Double {
        guard wordCount > 0 else { return 0 }
        return Double(fillerCount) / Double(wordCount) * 100
    }

    /// Anglicism rate per 100 words.
    var anglicismRatePer100Words: Double {
        guard wordCount > 0 else { return 0 }
        return Double(anglicismCount) / Double(wordCount) * 100
    }

    /// Self-corrections per 100 words — an inverse measure of "smoothness". Lower is smoother.
    var selfCorrectionRatePer100Words: Double {
        guard wordCount > 0 else { return 0 }
        return Double(selfCorrectionCount) / Double(wordCount) * 100
    }

    /// Deserialized dictionary of repair markers with counts (for highlighting/list).
    var selfCorrectionsByWord: [String: Int] {
        decodeJSON(selfCorrectionsByWordJSON)
    }

    /// Deserialized dictionary of filler words with counts.
    var fillersByWord: [String: Int] {
        decodeJSON(fillersByWordJSON)
    }

    /// Deserialized dictionary of anglicisms with counts.
    var anglicismsByWord: [String: Int] {
        decodeJSON(anglicismsByWordJSON)
    }

    /// Deserialized dictionary of repetitions with counts.
    var repetitionsByWord: [String: Int] {
        decodeJSON(repetitionsByWordJSON)
    }

    /// Total number of repeated unique words (≥5 times) in this dictation.
    var repetitionCount: Int {
        repetitionsByWord.count
    }

    private func decodeJSON(_ json: String) -> [String: Int] {
        JSONCoding.decode(json)
    }
}
