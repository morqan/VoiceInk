//
//  ProsodyAnalyzer.swift
//  VoiceInk
//
//  Phase 1 of voice-prosody analysis. Pure, local, time-domain DSP over mono Float
//  samples:
//    • pause ratio  — energy-based voice-activity detection (adaptive threshold)
//    • pitch (F0)   — YIN estimator on voiced frames → mean + range (monotone↔expressive)
//    • loudness     — per-frame dB spread during speech (dynamics)
//
//  Honesty notes (surfaced in the UI tips):
//    – loudness is in dBFS (relative to the recording), not calibrated SPL → reported
//      as DYNAMICS (spread), never as an absolute "how loud you are".
//    – thresholds are adaptive but still depend on mic/noise.
//

import Foundation

struct ProsodyResult {
    /// Share of the speaking span (first→last speech) spent in silence, %.
    let pauseRatioPercent: Double
    /// Median fundamental frequency over voiced frames, Hz.
    let pitchMeanHz: Double
    /// p90−p10 of F0 in semitones — low = monotone, high = expressive.
    let pitchRangeSemitones: Double
    /// p90−p10 of frame loudness (dBFS) during speech — vocal dynamics.
    let loudnessRangeDb: Double
    /// Number of voiced frames found — confidence proxy for the pitch numbers.
    let voicedFrameCount: Int
}

enum ProsodyAnalyzer {

    /// Human voice F0 search range (Hz).
    private static let minF0: Double = 70
    private static let maxF0: Double = 400
    /// YIN voicing threshold on the cumulative-mean-normalized difference.
    private static let yinThreshold: Double = 0.15
    /// Cap analysed pitch frames so very long clips stay fast.
    private static let maxPitchFrames = 2000

    static func analyze(samples: [Float], sampleRate: Double) -> ProsodyResult? {
        guard sampleRate > 0, samples.count >= Int(sampleRate * 0.3) else { return nil }

        // 1. Frame energies (25 ms window, 10 ms hop) → dBFS, for VAD + loudness.
        let energyWin = max(1, Int(sampleRate * 0.025))
        let energyHop = max(1, Int(sampleRate * 0.010))
        var frameDb: [Double] = []
        var f = 0
        while f + energyWin <= samples.count {
            var sumSq: Double = 0
            var j = 0
            while j < energyWin {
                let v = Double(samples[f + j])
                sumSq += v * v
                j += 1
            }
            let rms = (sumSq / Double(energyWin)).squareRoot()
            frameDb.append(20.0 * log10(max(rms, 1e-7)))
            f += energyHop
        }
        guard frameDb.count >= 4 else { return nil }

        // 2. Adaptive speech/silence threshold between the quiet floor and loud peaks.
        let sorted = frameDb.sorted()
        let noiseFloor = percentile(sorted, 0.15)
        let loudLevel = percentile(sorted, 0.95)
        let threshold = max(noiseFloor + 8.0, loudLevel - 35.0)
        let isSpeech = frameDb.map { $0 >= threshold }

        // 3. Pause ratio over the speaking span (ignore leading/trailing silence).
        let pauseRatio = computePauseRatio(isSpeech: isSpeech)

        // 4. Loudness dynamics over speech frames only.
        let speechDb = zip(frameDb, isSpeech).filter { $0.1 }.map { $0.0 }.sorted()
        let loudnessRange = speechDb.count >= 4
            ? percentile(speechDb, 0.90) - percentile(speechDb, 0.10)
            : 0

        // 5. Pitch via YIN on voiced frames.
        let pitch = computePitch(samples: samples, sampleRate: sampleRate, isSpeech: isSpeech, energyHop: energyHop)

        return ProsodyResult(
            pauseRatioPercent: pauseRatio,
            pitchMeanHz: pitch.mean,
            pitchRangeSemitones: pitch.rangeSemitones,
            loudnessRangeDb: loudnessRange,
            voicedFrameCount: pitch.count
        )
    }

    // MARK: - Pause ratio

    private static func computePauseRatio(isSpeech: [Bool]) -> Double {
        guard let first = isSpeech.firstIndex(of: true),
              let last = isSpeech.lastIndex(of: true), last > first else { return 0 }
        let span = isSpeech[first...last]
        let silent = span.filter { !$0 }.count
        return Double(silent) / Double(span.count) * 100.0
    }

    // MARK: - Pitch (YIN)

    private static func computePitch(samples: [Float], sampleRate: Double, isSpeech: [Bool], energyHop: Int) -> (mean: Double, rangeSemitones: Double, count: Int) {
        let tauMin = max(2, Int(sampleRate / maxF0))
        let tauMax = Int(sampleRate / minF0)
        let window = max(1024, tauMax * 2)
        let pitchHop = max(1, Int(sampleRate * 0.020))

        // Reusable YIN scratch buffers — allocated once, not per frame.
        var diff = [Double](repeating: 0, count: tauMax + 1)
        var cmnd = [Double](repeating: 1, count: tauMax + 1)

        var f0s: [Double] = []
        var start = 0
        var analysed = 0
        while start + window + tauMax <= samples.count && analysed < maxPitchFrames {
            let energyIndex = start / energyHop
            let speechHere = energyIndex < isSpeech.count ? isSpeech[energyIndex] : false
            if speechHere {
                if let f0 = yinF0(samples: samples, start: start, window: window, tauMin: tauMin, tauMax: tauMax, sampleRate: sampleRate, diff: &diff, cmnd: &cmnd) {
                    f0s.append(f0)
                }
                analysed += 1
            }
            start += pitchHop
        }

        guard f0s.count >= 5 else { return (0, 0, f0s.count) }
        let sorted = f0s.sorted()
        let mean = median(sorted)
        let p10 = percentile(sorted, 0.10)
        let p90 = percentile(sorted, 0.90)
        let rangeSemitones = (p10 > 0 && p90 > 0) ? 12.0 * log2(p90 / p10) : 0
        return (mean, rangeSemitones, f0s.count)
    }

    /// YIN pitch estimate for one frame, or nil if the frame is unvoiced.
    /// `diff`/`cmnd` are caller-owned scratch buffers (size tauMax+1), reused per frame.
    private static func yinF0(samples: [Float], start: Int, window: Int, tauMin: Int, tauMax: Int, sampleRate: Double, diff: inout [Double], cmnd: inout [Double]) -> Double? {
        // Difference function d(tau) for all lags up to tauMax.
        for tau in 1...tauMax {
            var sum: Double = 0
            var j = 0
            while j < window {
                let delta = Double(samples[start + j] - samples[start + j + tau])
                sum += delta * delta
                j += 1
            }
            diff[tau] = sum
        }
        // Cumulative mean normalized difference d'(tau).
        var runningSum: Double = 0
        for tau in 1...tauMax {
            runningSum += diff[tau]
            cmnd[tau] = runningSum > 0 ? diff[tau] * Double(tau) / runningSum : 1
        }
        // Absolute threshold: first dip below threshold, walked to its local minimum.
        var bestTau = -1
        var tau = tauMin
        while tau <= tauMax {
            if cmnd[tau] < yinThreshold {
                while tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                bestTau = tau
                break
            }
            tau += 1
        }
        guard bestTau != -1 else { return nil }   // unvoiced

        // Parabolic interpolation around the minimum for sub-sample accuracy.
        var refined = Double(bestTau)
        if bestTau > tauMin, bestTau < tauMax {
            let s0 = cmnd[bestTau - 1], s1 = cmnd[bestTau], s2 = cmnd[bestTau + 1]
            let denom = 2 * (s0 - 2 * s1 + s2)
            if denom != 0 { refined = Double(bestTau) + (s0 - s2) / denom }
        }
        let f0 = sampleRate / refined
        return (f0 >= minF0 && f0 <= maxF0) ? f0 : nil
    }

    // MARK: - Stats

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }
}
