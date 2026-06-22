//
//  SpeechMetricRecalcService.swift
//  VoiceInk
//
//  One-time migration: recompute historical SpeechMetric records under the honest formulas
//  (PhraseOccurrenceScanner with word boundaries, complexity without bare "что").
//
//  Without recomputing, the trends/deltas/Match Score would mix two scales: old records
//  were scored by substring match and inflated complexity — the chart would show a "step"
//  on the deploy date, passing off a formula change as a change in speech.
//
//  The transcription text is stored in each record — so we recompute filler words,
//  complexity, repetitions and sentences from scratch. We leave WPM/anglicisms alone (their
//  algorithms haven't changed). The pattern mirrors SessionMetricMigrationService:
//  a background context + a UserDefaults completion flag.
//

import Foundation
import SwiftData
import OSLog

@MainActor
final class SpeechMetricRecalcService {
    static let shared = SpeechMetricRecalcService()

    private let logger = Logger(
        subsystem: "com.morqan.voiceink",
        category: "SpeechMetricRecalcService"
    )

    /// Version in the key: on the next formula change it's enough to bump v.
    /// v3 — backfill rawText + recompute filler words with the auto-detector.
    /// v4 — added the "smoothness" metric (self-corrections) across all history.
    /// v5 — recompute sentences (numbers with a period and "…" no longer split them).
    private let completionKey = "SpeechMetricRecalc_v5_done"
    private(set) var isRunning = false

    private init() {}

    @discardableResult
    func runIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: completionKey), !isRunning else { return nil }
        isRunning = true

        let logger = self.logger
        let completionKey = self.completionKey

        return Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            do {
                let metrics = try context.fetch(FetchDescriptor<SpeechMetric>())

                // Step A: backfill rawText for old records. The real raw ASR text
                // wasn't saved back then — the best available approximation is the cleaned text.
                for metric in metrics where metric.rawText.isEmpty {
                    metric.rawText = metric.text
                }
                try context.save()

                // Step B: a personal active list of filler words across ALL history.
                // We exclude style marker phrases — otherwise "слушайте"/"значит" would land
                // both in filler words and in the trainer (a conflict).
                let profiles = (try? context.fetch(FetchDescriptor<VoiceProfileTarget>())) ?? []
                let markerExclude = Set(profiles.flatMap { $0.markerPhrases }.map { $0.lowercased() })
                let activeFillers = AutoFillerDetector.activeFillers(history: metrics, excluding: markerExclude)
                AutoFillerDetector.refreshCache(history: metrics, excluding: markerExclude)

                // Step C: recompute from the raw text using the auto-list.
                var updated = 0
                for metric in metrics {
                    let source = AutoFillerDetector.sourceText(metric)
                    guard !source.isEmpty else { continue }
                    let words = SpeechMetricsAnalyzer.extractWords(from: source)
                    guard !words.isEmpty else { continue }

                    let sentenceCount = SpeechMetricsAnalyzer.countSentences(in: source)
                    let fillers = SpeechMetricsAnalyzer.countFillers(text: source, activeFillers: activeFillers)
                    let complexity = SpeechMetricsAnalyzer.calculateComplexity(
                        text: source,
                        sentenceCount: sentenceCount
                    )
                    let repetitions = SpeechMetricsAnalyzer.countRepetitions(
                        words: words,
                        fillers: Set(fillers.keys),
                        anglicisms: Set(metric.anglicismsByWord.keys)
                    )
                    let selfCorrections = SpeechMetricsAnalyzer.countSelfCorrections(text: source, words: words)

                    metric.fillerCount = fillers.values.reduce(0, +)
                    metric.fillersByWordJSON = Self.encodeJSON(fillers)
                    metric.sentenceCount = sentenceCount
                    metric.avgSentenceComplexity = complexity
                    metric.repetitionsByWordJSON = Self.encodeJSON(repetitions)
                    metric.selfCorrectionCount = selfCorrections.total
                    metric.selfCorrectionsByWordJSON = Self.encodeJSON(selfCorrections.byMarker)
                    updated += 1
                }

                try context.save()
                UserDefaults.standard.set(true, forKey: completionKey)
                logger.info("Speech metric recalc v5 done: \(updated) records (auto-filler + rawText + smoothness + sentences)")
            } catch {
                logger.error("Speech metric recalc failed: \(error.localizedDescription, privacy: .public)")
                // Don't set the flag — we'll retry on the next launch
            }

            await MainActor.run {
                SpeechMetricRecalcService.shared.isRunning = false
            }
        }
    }

    private nonisolated static func encodeJSON(_ dict: [String: Int]) -> String {
        JSONCoding.encode(dict)
    }
}
