//
//  ProsodyAnalysisService.swift
//  VoiceInk
//
//  Runs prosody DSP OFF the main thread and writes the result back onto the
//  SpeechMetric. Two entry points:
//    • analyzeNew(...)        — for a freshly-saved dictation (called by the pipeline
//                               AFTER paste + save, so it never touches insertion).
//    • runBackfillIfNeeded(...) — one-time best-effort pass over recent history whose
//                               audio still exists (capped + low priority).
//

import Foundation
import SwiftData
import OSLog

@MainActor
final class ProsodyAnalysisService {
    static let shared = ProsodyAnalysisService()

    private let logger = Logger(subsystem: "com.morqan.voiceink", category: "ProsodyAnalysisService")
    private let backfillKey = "ProsodyBackfill_v1_done"
    private var isBackfilling = false

    /// Most-recent N records the one-off backfill will touch (keeps the pass bounded).
    private let backfillLimit = 150

    private init() {}

    /// Analyse one freshly-saved metric off the main thread and persist the result.
    func analyzeNew(metricID: UUID, audioURL: URL, container: ModelContainer) {
        let logger = self.logger
        Task.detached(priority: .utility) {
            guard let result = Self.analyzeFile(audioURL) else { return }
            let context = ModelContext(container)
            let id = metricID
            let descriptor = FetchDescriptor<SpeechMetric>(predicate: #Predicate { $0.id == id })
            guard let metric = try? context.fetch(descriptor).first else { return }
            Self.apply(result, to: metric)
            do { try context.save() } catch {
                logger.error("Prosody save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// One-time best-effort backfill for historical dictations whose audio still exists.
    @discardableResult
    func runBackfillIfNeeded(container: ModelContainer) -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: backfillKey), !isBackfilling else { return nil }
        isBackfilling = true

        let logger = self.logger
        let backfillKey = self.backfillKey
        let limit = self.backfillLimit

        return Task.detached(priority: .background) {
            let context = ModelContext(container)
            var processed = 0
            do {
                var descriptor = FetchDescriptor<SpeechMetric>(
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = limit
                let metrics = try context.fetch(descriptor)
                // Old metrics predate `audioFileURL`; resolve them via Transcription.
                // Only fetch transcriptions that still have audio — keeps the lookup set small.
                var txDescriptor = FetchDescriptor<Transcription>(predicate: #Predicate { $0.audioFileURL != nil })
                txDescriptor.propertiesToFetch = [\.audioFileURL, \.text, \.timestamp]
                let transcriptions = (try? context.fetch(txDescriptor)) ?? []

                for metric in metrics where !metric.prosodyAnalyzed {
                    guard let url = Self.resolveAudioURL(for: metric, transcriptions: transcriptions),
                          let result = Self.analyzeFile(url) else { continue }
                    Self.apply(result, to: metric)
                    if metric.audioFileURL.isEmpty { metric.audioFileURL = url.absoluteString }
                    processed += 1
                    if processed % 10 == 0 { try? context.save() }
                }
                try context.save()
                UserDefaults.standard.set(true, forKey: backfillKey)
                logger.info("Prosody backfill done: \(processed) records")
            } catch {
                logger.error("Prosody backfill failed: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run { ProsodyAnalysisService.shared.isBackfilling = false }
        }
    }

    // MARK: - Core (nonisolated, runs off-main)

    nonisolated static func analyzeFile(_ url: URL) -> ProsodyResult? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let audio = try? AudioSampleReader.read(url: url), !audio.samples.isEmpty else { return nil }
        return ProsodyAnalyzer.analyze(samples: audio.samples, sampleRate: audio.sampleRate)
    }

    nonisolated static func apply(_ result: ProsodyResult, to metric: SpeechMetric) {
        metric.pauseRatioPercent = result.pauseRatioPercent
        metric.pitchMeanHz = result.pitchMeanHz
        metric.pitchRangeSemitones = result.pitchRangeSemitones
        metric.loudnessRangeDb = result.loudnessRangeDb
        metric.prosodyAnalyzed = true
    }

    /// Find the recording for a metric: prefer its own `audioFileURL`, else match a
    /// Transcription by near-timestamp + identical text (old metrics lack the field).
    nonisolated static func resolveAudioURL(for metric: SpeechMetric, transcriptions: [Transcription]) -> URL? {
        if !metric.audioFileURL.isEmpty, let url = URL(string: metric.audioFileURL) { return url }
        let match = transcriptions.first { t in
            guard let path = t.audioFileURL, !path.isEmpty else { return false }
            return abs(t.timestamp.timeIntervalSince(metric.timestamp)) < 2.0 && t.text == metric.text
        }
        if let path = match?.audioFileURL { return URL(string: path) }
        return nil
    }
}
