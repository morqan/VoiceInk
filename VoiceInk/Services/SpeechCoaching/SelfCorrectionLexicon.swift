//
//  SelfCorrectionLexicon.swift
//  VoiceInk
//
//  SELF-CORRECTION markers — signals that the speaker is fixing what was just
//  said («вернее», «я хотел сказать», «или нет», «нет, не так»…). They feed the
//  "Smoothness" metric: the more repairs per 100 words, the lower the smoothness.
//
//  Intentionally does NOT overlap with the filler-word pool (FillerLexicon): here
//  we keep only what signals a REWORDING of a phrase, not a general hedge or
//  discourse marker. «точнее», «то есть», «в общем» are left to the filler words —
//  as single words they are more often a filler than a repair.
//
//  Multi-word entries are matched via PhraseOccurrenceScanner (word boundaries,
//  longer phrases first, no double-counting of nested matches).
//

import Foundation

enum SelfCorrectionLexicon {

    /// Repair markers. Lowercase, case-insensitive matching.
    /// Ordering long variants before short ones does not matter — the scanner handles it.
    static let markers: [String] = [
        // direct correction of a word
        "вернее", "поправлюсь", "поправка", "оговорился", "оговорилась",
        "я хотел сказать", "что я хотел сказать", "хотел сказать",
        "я имею в виду", "имею в виду", "в смысле",
        // retracting what was said and starting over
        "или нет", "хотя нет", "хотя не так", "нет не то", "нет не так",
        "нет погоди", "нет подожди", "нет стоп", "нет стой", "стоп не так",
        // assessing one's own wording
        "не то слово", "не то чтобы", "не так выразился",
        "неправильно сказал", "неверно сказал",
        "лучше сказать", "лучше так сказать", "как бы лучше сказать",
        "если точнее", "точнее говоря", "вернее говоря"
    ]

    /// Words whose back-to-back doubling is EMPHASIS / a conversational norm, not a stumble.
    /// «так-так», «ну-ну», «да-да», «чуть-чуть» — we do not count these as a restart.
    static let reduplicationAllowed: Set<String> = [
        "так", "ну", "да", "нет", "ой", "эх", "хе", "ха", "но", "вот",
        "уже", "чуть", "еле", "тихо", "тише", "давай", "хорошо", "ладно",
        "тук", "кап", "бам", "топ"
    ]
}
