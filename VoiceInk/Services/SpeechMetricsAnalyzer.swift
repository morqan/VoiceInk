//
//  SpeechMetricsAnalyzer.swift
//  VoiceInk
//
//  анализирует текст транскрипции и считает:
//  - filler words (паразиты)
//  - англицизмы
//  - среднюю длину предложения
//  - WPM
//  - EN/RU ratio
//
//  Список паразитов взят из speech-tracker.md (99 - Claude Context/).
//

import Foundation
import OSLog

enum SpeechMetricsAnalyzer {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "SpeechMetricsAnalyzer"
    )

    /// Список слов-паразитов Моргана из speech-tracker.md.
    /// Хранится в lowercase для регистронезависимого матчинга.
    /// Многословные ("как бы", "это самое", "в общем") — через PhraseOccurrenceScanner (границы слов).
    static let singleWordFillers: Set<String> = [
        "короче", "типа", "ну", "вот",
        "блин", "значит", "собственно", "понимаешь",
        "допустим", "окей", "ок", "эээ", "эм", "ммм"
    ]

    static let multiWordFillers: [String] = [
        "как бы", "это самое", "в общем",
        "то есть", "так сказать"
    ]

    /// Минимальная длина транскрипции (в словах) для записи метрики.
    /// Меньше — статистически незначимо (см. speech-tracker.md правило ≥15 слов).
    static let minWordsThreshold = 15

    /// Анализирует транскрипцию и возвращает заполненный SpeechMetric.
    /// Не сохраняет в базу — это делает caller.
    /// Возвращает nil если транскрипция короче threshold (статистически незначимо).
    static func analyze(text: String, durationSeconds: Double) -> SpeechMetric? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }

        let words = extractWords(from: cleanText)
        guard words.count >= minWordsThreshold else {
            logger.debug("Speech too short (\(words.count) words), skipping metric")
            return nil
        }

        let sentenceCount = countSentences(in: cleanText)
        let avgSentenceLength = sentenceCount > 0
            ? Double(words.count) / Double(sentenceCount)
            : Double(words.count)

        let avgSentenceComplexity = calculateComplexity(text: cleanText, sentenceCount: sentenceCount)

        let wpm = durationSeconds > 0
            ? Double(words.count) / (durationSeconds / 60.0)
            : 0

        let fillersByWord = countFillers(text: cleanText, words: words)
        let fillerCount = fillersByWord.values.reduce(0, +)

        let anglicismsByWord = countAnglicisms(words: words)
        let anglicismCount = anglicismsByWord.values.reduce(0, +)

        let enRuRatio = calculateEnRuRatio(text: cleanText)

        let repetitionsByWord = countRepetitions(
            words: words,
            fillers: Set(fillersByWord.keys),
            anglicisms: Set(anglicismsByWord.keys)
        )

        let metric = SpeechMetric(
            timestamp: Date(),
            durationSeconds: durationSeconds,
            wordCount: words.count,
            sentenceCount: sentenceCount,
            avgSentenceLength: avgSentenceLength,
            avgSentenceComplexity: avgSentenceComplexity,
            wpm: wpm,
            fillerCount: fillerCount,
            fillersByWordJSON: encodeJSON(fillersByWord),
            anglicismCount: anglicismCount,
            anglicismsByWordJSON: encodeJSON(anglicismsByWord),
            enRuRatio: enRuRatio,
            repetitionsByWordJSON: encodeJSON(repetitionsByWord),
            text: cleanText
        )

        logger.info("""
            Analyzed: \(words.count) words, \(sentenceCount) sentences, \
            avg sentence \(String(format: "%.1f", avgSentenceLength)) words, \
            WPM \(String(format: "%.1f", wpm)), \
            \(fillerCount) fillers, \(anglicismCount) anglicisms, \
            \(repetitionsByWord.count) repetitions
            """)

        return metric
    }

    // MARK: - Word extraction

    /// Разбивает текст на слова. Игнорирует знаки препинания.
    static func extractWords(from text: String) -> [String] {
        let allowedChars = CharacterSet.letters.union(.init(charactersIn: "-'"))
        return text
            .components(separatedBy: allowedChars.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    // MARK: - Sentence counting

    /// Считает количество предложений по терминаторам . ? ! и многоточиям.
    /// Многоточие = одно предложение, не три.
    static func countSentences(in text: String) -> Int {
        // Сначала схлопнуть "..." и "?!" и "!?" в один символ — чтобы не считать как несколько
        var normalized = text
        normalized = normalized.replacingOccurrences(of: "...", with: ".")
        normalized = normalized.replacingOccurrences(of: "?!", with: "?")
        normalized = normalized.replacingOccurrences(of: "!?", with: "!")

        let terminators: Set<Character> = [".", "?", "!"]
        let count = normalized.filter { terminators.contains($0) }.count

        // Если нет терминаторов — считаем как 1 предложение (если текст не пустой)
        return max(count, 1)
    }

    // MARK: - Fillers

    /// Считает паразитов в тексте.
    /// Single-word — по точному матчу слова в массиве слов.
    /// Multi-word — через PhraseOccurrenceScanner: границы слов, чтобы «то есть»
    /// не матчился внутри «прос[то есть]ь».
    static func countFillers(text: String, words: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]

        // Single-word fillers
        for word in words {
            if singleWordFillers.contains(word) {
                counts[word, default: 0] += 1
            }
        }

        // Multi-word fillers
        for (phrase, count) in PhraseOccurrenceScanner.counts(of: multiWordFillers, in: text) where count > 0 {
            counts[phrase] = count
        }

        return counts
    }

    // MARK: - Anglicisms

    /// Считает англицизмы — слова содержащие латинские буквы в основном русском тексте.
    /// Слова из 1-2 латинских букв игнорируются (могут быть аббревиатурами в кириллическом контексте).
    /// Если общая доля латинских букв > 50% — текст считается английским, англицизмы не маркируются.
    static func countAnglicisms(words: [String]) -> [String: Int] {
        let latinChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")

        // Подсчитываем сколько слов чисто-латинских
        var counts: [String: Int] = [:]

        // Прежде чем считать — оценим общий контекст. Если >50% слов латинские — это английский текст
        let latinWords = words.filter { isAllLatin($0, allowedSet: latinChars) }
        let latinRatio = words.isEmpty ? 0 : Double(latinWords.count) / Double(words.count)

        // Если текст преимущественно английский — англицизмы не считаем (это сам по себе английский)
        guard latinRatio < 0.5 else {
            return [:]
        }

        // Иначе — каждое латинское слово ≥ 3 символов считается англицизмом
        for word in words {
            if word.count >= 3 && isAllLatin(word, allowedSet: latinChars) {
                counts[word, default: 0] += 1
            }
        }

        return counts
    }

    private static func isAllLatin(_ word: String, allowedSet: CharacterSet) -> Bool {
        let stripped = word.lowercased().unicodeScalars.filter { $0.value < 128 } // basic ASCII filter
        guard !stripped.isEmpty else { return false }
        return stripped.allSatisfy { allowedSet.contains($0) }
    }

    // MARK: - EN/RU ratio

    /// Считает долю латинских букв среди всех букв (0..1).
    static func calculateEnRuRatio(text: String) -> Double {
        var latinCount = 0
        var totalLetters = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                totalLetters += 1
                if scalar.value < 128 && CharacterSet.letters.contains(scalar) {
                    latinCount += 1
                }
            }
        }

        guard totalLetters > 0 else { return 0 }
        return Double(latinCount) / Double(totalLetters)
    }

    // MARK: - Sentence complexity

    /// Маркеры подчинения для русского — союзы и относительные местоимения.
    /// Каждое вхождение в текст = +1 к сложности (per sentence average).
    /// Стоявшее здесь голое «что» убрано: это сверхчастотное слово («что делать?»,
    /// «а что по срокам») давало львиную долю балла без всякого подчинения.
    static let subordinationMarkers: [String] = [
        "который", "которая", "которое", "которые", "которых", "которым", "которой",
        "чтобы",
        "если", "когда", "пока", "хотя",
        "потому что", "так как", "несмотря на",
        "поскольку", "ибо",
        "будто", "словно", "как будто"
    ]

    /// Считает среднюю сложность предложения. Чем выше — тем больше подчинённых
    /// конструкций (длинные обволакивающие предложения, как у Эриксона).
    ///
    /// Формула: (маркеры_подчинения + 0.3 × запятые) / sentenceCount
    /// Маркеры — через PhraseOccurrenceScanner: границы слов + без двойного счёта
    /// вложений («как будто» больше не даёт ещё и «будто»).
    static func calculateComplexity(text: String, sentenceCount: Int) -> Double {
        guard sentenceCount > 0 else { return 0 }

        let markerHits = PhraseOccurrenceScanner.totalCount(of: subordinationMarkers, in: text)
        let commaCount = text.filter { $0 == "," }.count
        let totalScore = Double(markerHits) + 0.3 * Double(commaCount)
        return totalScore / Double(sentenceCount)
    }

    // MARK: - Repetitions

    /// Минимальная частота для маркировки слова как «повтор».
    /// 5 — баланс между «нормально повторил» и «зациклился».
    static let repetitionThreshold = 5

    /// Минимальная длина слова для учёта в повторах.
    /// Короткие («что», «как», «но», «то») — высокочастотные служебные, не маркер.
    static let repetitionMinWordLength = 4

    /// Считает слова которые повторены ≥ 5 раз в одной диктовке.
    /// Исключает: паразитов (они в counts отдельно), англицизмы, короткие слова.
    static func countRepetitions(
        words: [String],
        fillers: Set<String>,
        anglicisms: Set<String>
    ) -> [String: Int] {
        var totals: [String: Int] = [:]
        for word in words {
            guard word.count >= repetitionMinWordLength else { continue }
            guard !fillers.contains(word) else { continue }
            guard !anglicisms.contains(word) else { continue }
            totals[word, default: 0] += 1
        }
        return totals.filter { $0.value >= repetitionThreshold }
    }

    // MARK: - JSON helper

    private static func encodeJSON(_ dict: [String: Int]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
