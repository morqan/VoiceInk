//
//  VoiceProfileTarget.swift
//  VoiceInk
//
//  Target speech style — a preset or a custom one.
//  Consists of target metric values plus a list of marker phrases characteristic of the style.
//  The VoiceProfileMatcher analyzer compares real speech against this reference
//  and produces a Match Score 0..100.
//

import Foundation
import SwiftData

@Model
final class VoiceProfileTarget {
    var id: UUID = UUID()

    /// Style name: "Ericksonian Hypnotist" / "Tactical Negotiator" / etc.
    var name: String = ""

    /// Style description — what is characteristic
    var summary: String = ""

    /// SF Symbols icon
    var iconName: String = "person.fill"

    // MARK: - Target metric values

    /// Target speed in WPM
    var targetWPM: Double = 130

    /// Target average sentence length (words)
    var targetSentenceLength: Double = 15

    /// Target sentence complexity
    var targetComplexity: Double = 2

    /// Maximum allowed filler rate per 100 words
    var maxFillerRate: Double = 2

    /// Desired number of marker phrases per 100 words
    var targetMarkerRatePer100Words: Double = 3

    /// JSON array of the style's marker phrases: ["и пока ты", "возможно", ...]
    var markerPhrasesJSON: String = "[]"

    // MARK: - State

    /// Whether this is a preset (built-in) — cannot be deleted
    var isPreset: Bool = false

    /// Currently active as the comparison target (only one of all can be active)
    var isActive: Bool = false

    init(
        id: UUID = UUID(),
        name: String = "",
        summary: String = "",
        iconName: String = "person.fill",
        targetWPM: Double = 130,
        targetSentenceLength: Double = 15,
        targetComplexity: Double = 2,
        maxFillerRate: Double = 2,
        targetMarkerRatePer100Words: Double = 3,
        markerPhrasesJSON: String = "[]",
        isPreset: Bool = false,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.iconName = iconName
        self.targetWPM = targetWPM
        self.targetSentenceLength = targetSentenceLength
        self.targetComplexity = targetComplexity
        self.maxFillerRate = maxFillerRate
        self.targetMarkerRatePer100Words = targetMarkerRatePer100Words
        self.markerPhrasesJSON = markerPhrasesJSON
        self.isPreset = isPreset
        self.isActive = isActive
    }

    /// Decoded list of marker phrases.
    var markerPhrases: [String] {
        guard let data = markerPhrasesJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }
}
