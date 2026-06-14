//
//  VoiceProfileTarget.swift
//  VoiceInk
//
//  Целевой стиль речи — пресет или кастомный.
//  Состоит из целевых значений метрик + списка фраз-маркеров характерных для стиля.
//  Анализатор VoiceProfileMatcher сравнивает реальную речь с этим эталоном
//  и выдаёт Match Score 0..100.
//

import Foundation
import SwiftData

@Model
final class VoiceProfileTarget {
    var id: UUID = UUID()

    /// Название стиля: "Эриксоновский гипнотизёр" / "Tactical Negotiator" / etc.
    var name: String = ""

    /// Описание стиля — что характерно
    var summary: String = ""

    /// Иконка SF Symbols
    var iconName: String = "person.fill"

    // MARK: - Target metric values

    /// Целевая скорость WPM
    var targetWPM: Double = 130

    /// Целевая средняя длина предложения (слова)
    var targetSentenceLength: Double = 15

    /// Целевая сложность предложения
    var targetComplexity: Double = 2

    /// Максимально допустимый filler rate per 100 words
    var maxFillerRate: Double = 2

    /// Желаемое количество marker phrases на 100 слов
    var targetMarkerRatePer100Words: Double = 3

    /// JSON-массив фраз-маркеров стиля: ["и пока ты", "возможно", ...]
    var markerPhrasesJSON: String = "[]"

    // MARK: - State

    /// Является ли preset (из коробки) — нельзя удалить
    var isPreset: Bool = false

    /// Активен сейчас как цель сравнения (только один из всех может быть активным)
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

    /// Декодированный список маркеров.
    var markerPhrases: [String] {
        guard let data = markerPhrasesJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }
}
