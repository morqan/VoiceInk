//
//  PhraseOccurrenceScanner.swift
//  VoiceInk
//
//  Shared scanning of phrase occurrences in text: case-insensitive, on word
//  boundaries, longest phrases first, with no double-counting of overlaps (a single
//  spot in the text is counted once — «именно поэтому» does not also yield «поэтому»).
//
//  Used by: VoiceProfileMatcher (style marker phrases), SpeechMetricsAnalyzer
//  (multi-word filler words, subordination markers), session drill-down highlighting.
//

import Foundation

enum PhraseOccurrenceScanner {

    /// Normalized phrase order for scanning: lowercase, deduplicated, longest first
    /// (so a nested short phrase does not take the spot of a longer one). Compute it once —
    /// call before looping over many texts and pass it into `*ofOrdered`.
    static func normalizedOrdered(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        return phrases
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// Occurrences of each phrase in the text. Ranges are in the original string (for highlighting).
    /// The result key is the phrase in lowercase.
    static func occurrences(of phrases: [String], in text: String) -> [String: [Range<String.Index>]] {
        guard !phrases.isEmpty, !text.isEmpty else { return [:] }
        return occurrences(ofOrdered: normalizedOrdered(phrases), in: text)
    }

    /// Like `occurrences(of:in:)`, but takes an already-normalized list (see
    /// `normalizedOrdered`) — to avoid recomputing it for every text in a loop.
    static func occurrences(ofOrdered ordered: [String], in text: String) -> [String: [Range<String.Index>]] {
        guard !ordered.isEmpty, !text.isEmpty else { return [:] }

        var result: [String: [Range<String.Index>]] = [:]
        var consumed: [Range<String.Index>] = []

        for phrase in ordered {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(of: phrase, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                // Advance by one character, not to upperBound: a rejection on a word
                // boundary must not hide a valid occurrence just to the right.
                searchStart = text.index(after: range.lowerBound)

                guard isWordBounded(range, in: text) else { continue }
                guard !consumed.contains(where: { $0.overlaps(range) }) else { continue }

                consumed.append(range)
                result[phrase, default: []].append(range)
            }
        }
        return result
    }

    /// Number of occurrences of each phrase (word boundaries, no overlaps).
    static func counts(of phrases: [String], in text: String) -> [String: Int] {
        occurrences(of: phrases, in: text).mapValues { $0.count }
    }

    /// Like `counts(of:in:)`, but for an already-normalized list of phrases (see
    /// `normalizedOrdered`) — for hot loops over many texts.
    static func counts(ofOrdered ordered: [String], in text: String) -> [String: Int] {
        occurrences(ofOrdered: ordered, in: text).mapValues { $0.count }
    }

    /// Total number of occurrences of all phrases.
    static func totalCount(of phrases: [String], in text: String) -> Int {
        counts(of: phrases, in: text).values.reduce(0, +)
    }

    /// An occurrence is valid only if neither the character to its left nor right is a "word" character.
    /// «возможно» does not match inside «невозможно», nor «цель» inside «прицельный».
    /// Hyphen and apostrophe count as part of a word — as in SpeechMetricsAnalyzer.extractWords:
    /// «ну» inside «ну-ка» is neither highlighted nor counted.
    private static func isWordBounded(_ range: Range<String.Index>, in text: String) -> Bool {
        let startOK = range.lowerBound == text.startIndex
            || !isWordChar(text[text.index(before: range.lowerBound)])
        let endOK = range.upperBound == text.endIndex
            || !isWordChar(text[range.upperBound])
        return startOK && endOK
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch == "-" || ch == "'"
    }
}
