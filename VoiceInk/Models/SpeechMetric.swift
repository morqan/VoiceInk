//
//  SpeechMetric.swift
//  VoiceInk
//
//  метрики речи на каждую транскрипцию.
//  Записывается после каждой завершённой диктовки в saveTranscriptionAndPostCompletion.
//
//  Считает: filler words (паразиты), англицизмы, среднюю длину предложения, WPM, EN/RU ratio.
//

import Foundation
import SwiftData

@Model
final class SpeechMetric {
    /// Уникальный ID записи
    var id: UUID = UUID()

    /// Когда диктовка была завершена
    var timestamp: Date = Date()

    /// Длительность аудио в секундах
    var durationSeconds: Double = 0

    /// Общий счётчик слов в тексте
    var wordCount: Int = 0

    /// Количество предложений (разбито по .?!)
    var sentenceCount: Int = 0

    /// Средняя длина предложения в словах
    var avgSentenceLength: Double = 0

    /// Средняя сложность предложения. Считается по маркерам подчинения
    /// («который», «что», «потому что», «если», «когда», «пока», «чтобы» и т.д.)
    /// плюс по запятым (как proxy для сложных конструкций).
    /// 0 = чистая простая речь. 5+ = подчинительные конструкции каждый раз.
    var avgSentenceComplexity: Double = 0

    /// WPM = wordCount / (durationSeconds / 60)
    var wpm: Double = 0

    /// Общее число слов-паразитов в этой диктовке
    var fillerCount: Int = 0

    /// JSON-сериализация {"короче": 3, "типа": 1, ...}
    /// SwiftData плохо дружит с [String: Int], поэтому через JSON.
    var fillersByWordJSON: String = "{}"

    /// Общее число англицизмов
    var anglicismCount: Int = 0

    /// JSON-сериализация {"deadline": 2, "meeting": 1, ...}
    var anglicismsByWordJSON: String = "{}"

    /// Отношение латинских символов к общему числу букв (0..1)
    /// 0 = чистый русский, 1 = чистый английский
    var enRuRatio: Double = 0

    /// Повторы — слова которые встретились ≥ 5 раз в одной диктовке (исключая паразитов/англицизмов).
    /// JSON-сериализация {"проект": 7, "задача": 5, ...}
    var repetitionsByWordJSON: String = "{}"

    /// Полный текст транскрипции (для возможности peek в UI)
    var text: String = ""

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        durationSeconds: Double = 0,
        wordCount: Int = 0,
        sentenceCount: Int = 0,
        avgSentenceLength: Double = 0,
        avgSentenceComplexity: Double = 0,
        wpm: Double = 0,
        fillerCount: Int = 0,
        fillersByWordJSON: String = "{}",
        anglicismCount: Int = 0,
        anglicismsByWordJSON: String = "{}",
        enRuRatio: Double = 0,
        repetitionsByWordJSON: String = "{}",
        text: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.sentenceCount = sentenceCount
        self.avgSentenceLength = avgSentenceLength
        self.avgSentenceComplexity = avgSentenceComplexity
        self.wpm = wpm
        self.fillerCount = fillerCount
        self.fillersByWordJSON = fillersByWordJSON
        self.anglicismCount = anglicismCount
        self.anglicismsByWordJSON = anglicismsByWordJSON
        self.enRuRatio = enRuRatio
        self.repetitionsByWordJSON = repetitionsByWordJSON
        self.text = text
    }

    // MARK: - Computed

    /// Filler rate per 100 words. Цель Моргана: ≤ 2.
    var fillerRatePer100Words: Double {
        guard wordCount > 0 else { return 0 }
        return Double(fillerCount) / Double(wordCount) * 100
    }

    /// Anglicism rate per 100 words.
    var anglicismRatePer100Words: Double {
        guard wordCount > 0 else { return 0 }
        return Double(anglicismCount) / Double(wordCount) * 100
    }

    /// Десериализованный словарь паразитов с count.
    var fillersByWord: [String: Int] {
        decodeJSON(fillersByWordJSON)
    }

    /// Десериализованный словарь англицизмов с count.
    var anglicismsByWord: [String: Int] {
        decodeJSON(anglicismsByWordJSON)
    }

    /// Десериализованный словарь повторов с count.
    var repetitionsByWord: [String: Int] {
        decodeJSON(repetitionsByWordJSON)
    }

    /// Общее число повторяющихся уникальных слов (≥5 раз) в этой диктовке.
    var repetitionCount: Int {
        repetitionsByWord.count
    }

    private func decodeJSON(_ json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return dict
    }
}
