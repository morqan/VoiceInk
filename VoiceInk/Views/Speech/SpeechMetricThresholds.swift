//
//  SpeechMetricThresholds.swift
//  VoiceInk
//
//  Single source of truth for the green/orange/red bands of the speech metrics.
//  Previously these thresholds were copy-pasted across the Overview tab and the
//  Dashboard "Speech Today" card. Kept out of the @Model SpeechMetric to avoid
//  SwiftData schema churn.
//

import SwiftUI

enum SpeechMetricThresholds {
    /// Grey when there are no words yet, else green ≤2 / orange ≤4 / red.
    static func fillerBand(rate: Double, wordCount: Int) -> Color {
        if wordCount == 0 { return .secondary }
        if rate <= 2 { return .green }
        if rate <= 4 { return .orange }
        return .red
    }

    /// Green ≤18 / orange ≤25 / red words per sentence.
    static func sentenceBand(length: Double, wordCount: Int) -> Color {
        if wordCount == 0 { return .secondary }
        if length <= 18 { return .green }
        if length <= 25 { return .orange }
        return .red
    }

    /// Green ≤1 / orange ≤3 / red anglicisms per 100 words.
    static func anglicismBand(rate: Double, wordCount: Int) -> Color {
        if wordCount == 0 { return .secondary }
        if rate <= 1 { return .green }
        if rate <= 3 { return .orange }
        return .red
    }

    /// Smoothness: green ≤1 / orange ≤3 / red self-corrections per 100 words.
    static func smoothnessBand(rate: Double, wordCount: Int) -> Color {
        if wordCount == 0 { return .secondary }
        if rate <= 1 { return .green }
        if rate <= 3 { return .orange }
        return .red
    }
}
