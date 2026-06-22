//
//  VoiceProfileSeed.swift
//  VoiceInk
//
//  Seeds 4 preset profiles on first launch.
//  Does not duplicate if they already exist — silent skip.
//

import Foundation
import SwiftData
import OSLog

enum VoiceProfileSeed {

    private static let logger = Logger(
        subsystem: "com.morqan.voiceink",
        category: "VoiceProfileSeed"
    )

    /// Seeds preset profiles if they don't yet exist in the database.
    /// Activates the Ericksonian profile by default (the most interesting one for NLP training).
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<VoiceProfileTarget>())) ?? []
        guard existing.isEmpty else {
            logger.debug("Voice profiles already exist (\(existing.count)), skipping seed")
            return
        }

        let presets = makePresets()
        for preset in presets {
            context.insert(preset)
        }

        do {
            try context.save()
            logger.info("Seeded \(presets.count) voice profile presets")
        } catch {
            logger.error("Failed to seed voice profiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Presets

    private static func makePresets() -> [VoiceProfileTarget] {
        [
            ericksonianHypnotist,
            tacticalNegotiator,
            calmLeader,
            charismaticSpeaker
        ]
    }

    /// 🔮 Ericksonian hypnotist — long, enveloping sentences, slow pace
    private static var ericksonianHypnotist: VoiceProfileTarget {
        let markers = [
            "и пока", "и сейчас", "возможно",
            "может быть", "ты можешь", "и ты",
            "представь себе", "если бы", "по мере того как",
            "и когда", "это значит что", "так что"
        ]
        return VoiceProfileTarget(
            name: "Эриксоновский гипнотизёр",
            summary: "Медленный темп, длинные подчинённые предложения, embedded commands. Обходит критическое мышление через обволакивание.",
            iconName: "moon.stars.fill",
            targetWPM: 105,
            targetSentenceLength: 30,
            targetComplexity: 5,
            maxFillerRate: 1,
            targetMarkerRatePer100Words: 5,
            markerPhrasesJSON: encodePhrases(markers),
            isPreset: true,
            isActive: true
        )
    }

    /// ⚔️ Tactical negotiator — short sentences, directness, framing constructions
    private static var tacticalNegotiator: VoiceProfileTarget {
        let markers = [
            "цель", "результат", "вопрос",
            "что если", "поэтому", "именно поэтому",
            "и значит", "первое", "второе",
            "решение", "выбор", "позиция"
        ]
        return VoiceProfileTarget(
            name: "Жёсткий переговорщик",
            summary: "Короткие прямые предложения, framing-конструкции, минимум воды. Контролирует темп разговора через ясность.",
            iconName: "target",
            targetWPM: 130,
            targetSentenceLength: 10,
            targetComplexity: 1,
            maxFillerRate: 1,
            targetMarkerRatePer100Words: 4,
            markerPhrasesJSON: encodePhrases(markers),
            isPreset: true,
            isActive: false
        )
    }

    /// 🧘 Calm leader — medium sentence length, structured, few filler words
    private static var calmLeader: VoiceProfileTarget {
        let markers = [
            "план", "цель", "приоритет",
            "первое", "второе", "третье",
            "результат", "следующий шаг", "решение",
            "ответственность", "сроки", "качество"
        ]
        return VoiceProfileTarget(
            name: "Спокойный лидер",
            summary: "Средний темп, структурированно. Список перед действием, ясные приоритеты, ноль воды.",
            iconName: "person.fill.checkmark",
            targetWPM: 120,
            targetSentenceLength: 18,
            targetComplexity: 2,
            maxFillerRate: 1,
            targetMarkerRatePer100Words: 3,
            markerPhrasesJSON: encodePhrases(markers),
            isPreset: true,
            isActive: false
        )
    }

    /// 🎤 Charismatic speaker — varied pace, emotional words
    private static var charismaticSpeaker: VoiceProfileTarget {
        let markers = [
            "слушайте", "давайте", "представьте",
            "именно", "точно", "именно поэтому",
            "почувствуйте", "увидите", "поймёте",
            "история", "момент", "представь"
        ]
        return VoiceProfileTarget(
            name: "Харизматичный спикер",
            summary: "Быстрый разнообразный темп, обращения к слушателю, мало повторов, эмоциональные образы.",
            iconName: "megaphone.fill",
            targetWPM: 160,
            targetSentenceLength: 15,
            targetComplexity: 2,
            maxFillerRate: 2,
            targetMarkerRatePer100Words: 4,
            markerPhrasesJSON: encodePhrases(markers),
            isPreset: true,
            isActive: false
        )
    }

    private static func encodePhrases(_ phrases: [String]) -> String {
        guard let data = try? JSONEncoder().encode(phrases),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
