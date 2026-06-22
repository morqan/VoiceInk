//
//  AudioRetentionService.swift
//  VoiceInk
//
//  Reclaims disk space by deleting recording .wav files older than a grace period
//  (default 14 days), while KEEPING the transcription record and every speech metric
//  (prosody numbers are already stored). By the grace period prosody analysis is long
//  done, so there is no race with ProsodyAnalysisService — and the window leaves time
//  for playback / future re-analysis before a clip is removed.
//
//  Only the audio FILE is deleted; the Transcription row stays (its audioFileURL is
//  cleared so the History view shows "no audio" instead of a dead link).
//

import Foundation
import SwiftData
import OSLog

@MainActor
final class AudioRetentionService {
    static let shared = AudioRetentionService()

    private let logger = Logger(subsystem: "com.morqan.voiceink", category: "AudioRetentionService")
    private let retentionDaysKey = "AudioRetentionDays"
    private let defaultRetentionDays = 14
    private var isSweeping = false

    private init() {}

    /// Days to keep recordings. Unset → default; a value ≤ 0 means "keep forever".
    private var retentionDays: Int {
        guard UserDefaults.standard.object(forKey: retentionDaysKey) != nil else { return defaultRetentionDays }
        return UserDefaults.standard.integer(forKey: retentionDaysKey)
    }

    @discardableResult
    func sweepIfNeeded(container: ModelContainer) -> Task<Void, Never>? {
        let days = retentionDays
        guard days > 0, !isSweeping else { return nil }
        isSweeping = true

        let logger = self.logger
        return Task.detached(priority: .background) {
            let context = ModelContext(container)
            let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
            var freed = 0
            do {
                let descriptor = FetchDescriptor<Transcription>(
                    predicate: #Predicate { $0.timestamp < cutoff && $0.audioFileURL != nil }
                )
                let old = try context.fetch(descriptor)
                for transcription in old {
                    if let path = transcription.audioFileURL,
                       let url = URL(string: path),
                       FileManager.default.fileExists(atPath: url.path) {
                        try? FileManager.default.removeItem(at: url)
                        freed += 1
                    }
                    transcription.audioFileURL = nil
                }
                try context.save()
                logger.notice("Audio retention sweep: removed \(freed, privacy: .public) recordings older than \(days, privacy: .public)d")
            } catch {
                logger.error("Audio retention sweep failed: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run { AudioRetentionService.shared.isSweeping = false }
        }
    }
}
