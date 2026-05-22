//
//  VaultDictionarySync.swift
//  VoiceInk
//
//  автоматическая синхронизация словаря с markdown-файлом.
//  Источник пути — UserDefaults (можно изменить в Dictionary Settings → Vault Sync).
//
//  При каждом запуске приложения читает markdown-файл и подсасывает новые слова
//  в VocabularyWord (через DictionaryService). Существующие слова не дублируются.
//  Если файл не найден или sync выключен — silent skip, не падаем.
//

import Foundation
import SwiftData
import OSLog

enum VaultDictionarySync {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "VaultDictionarySync"
    )

    /// Результат синхронизации.
    struct Result {
        let added: Int       // сколько слов добавлено в этот раз
        let totalParsed: Int // сколько всего слов извлечено из файла
        let skipped: Bool    // true если sync был пропущен (выключен / файла нет)
        let error: String?   // текст ошибки если что-то пошло не так

        var summary: String {
            if let error = error { return "Error: \(error)" }
            if skipped { return "Skipped" }
            if added == 0 { return "All \(totalParsed) words already in dictionary" }
            return "Added \(added) of \(totalParsed) words"
        }
    }

    /// Главная точка входа. Читает настройки, парсит markdown, добавляет слова.
    @discardableResult
    static func syncFromVault(context: ModelContext) -> Result {
        // 1. Проверить что sync включён
        let enabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.vaultSyncEnabled)
        guard enabled else {
            logger.info("Vault sync disabled in settings")
            return Result(added: 0, totalParsed: 0, skipped: true, error: nil)
        }

        // 2. Получить путь из настроек, развернуть ~
        let rawPath = UserDefaults.standard.string(forKey: UserDefaults.Keys.vaultDictionaryPath) ?? ""
        let path = NSString(string: rawPath).expandingTildeInPath
        guard !path.isEmpty else {
            logger.info("Vault dictionary path is empty")
            return Result(added: 0, totalParsed: 0, skipped: true, error: nil)
        }

        // 3. Проверить что файл существует
        guard FileManager.default.fileExists(atPath: path) else {
            logger.info("Vault dictionary not found at \(path, privacy: .public)")
            return Result(added: 0, totalParsed: 0, skipped: true, error: "File not found at \(path)")
        }

        do {
            // 4. Прочитать и распарсить
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let words = parseWords(from: content)

            guard !words.isEmpty else {
                logger.info("No words extracted from \(path, privacy: .public)")
                return Result(added: 0, totalParsed: 0, skipped: false, error: nil)
            }

            // 5. Дедупликация против существующих слов
            let descriptor = FetchDescriptor<VocabularyWord>()
            let existing = (try? context.fetch(descriptor)) ?? []
            let existingLower = Set(existing.map { $0.word.lowercased() })

            let newWords = words.filter { !existingLower.contains($0.lowercased()) }

            guard !newWords.isEmpty else {
                logger.info("Vault sync: all \(words.count) words already in dictionary")
                return Result(added: 0, totalParsed: words.count, skipped: false, error: nil)
            }

            // 6. Добавить через DictionaryService
            let input = newWords.joined(separator: ", ")
            let serviceError = DictionaryService.addVocabularyWords(
                input,
                existing: existing,
                context: context
            )

            logger.info("Vault sync: \(newWords.count) new words added out of \(words.count) total")
            return Result(
                added: newWords.count,
                totalParsed: words.count,
                skipped: false,
                error: serviceError
            )
        } catch {
            logger.error("Failed to read Vault dictionary: \(error.localizedDescription, privacy: .public)")
            return Result(added: 0, totalParsed: 0, skipped: false, error: error.localizedDescription)
        }
    }

    // MARK: - Markdown parsing

    /// Парсит markdown-таблицу и извлекает слова из колонки «Правильное написание».
    ///
    /// Ожидаемый формат таблицы:
    /// ```
    /// | Что сказал Морган | Как услышал Whisper | Правильное написание | Дата | Перенесено? |
    /// |---|---|---|---|---|
    /// | Option | общин | `Option` | 2026-05-05 | — |
    /// ```
    ///
    /// Backtick-обрамление снимается: `Option` → Option.
    /// Пустые ячейки (—, --, пустая строка) пропускаются.
    static func parseWords(from content: String) -> [String] {
        var words: [String] = []
        let lines = content.components(separatedBy: .newlines)

        var inTable = false
        var headerSkipped = false
        var correctWritingColumnIndex: Int?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Header строка с колонкой «Правильное написание»
            if !inTable && trimmed.hasPrefix("|") && trimmed.contains("Правильное написание") {
                inTable = true
                let columns = splitTableRow(trimmed)
                correctWritingColumnIndex = columns.firstIndex { $0 == "Правильное написание" }
                continue
            }

            // Уже в таблице, но строка не начинается с | — таблица закончилась
            if inTable && !trimmed.hasPrefix("|") {
                inTable = false
                headerSkipped = false
                correctWritingColumnIndex = nil
                continue
            }

            // Разделитель |---|---|...
            if inTable && trimmed.contains("---") {
                headerSkipped = true
                continue
            }

            // Строка данных
            if inTable && headerSkipped, let idx = correctWritingColumnIndex {
                let columns = splitTableRow(trimmed)
                if columns.count > idx {
                    let raw = columns[idx]
                    let cleaned = cleanWord(raw)
                    if !cleaned.isEmpty {
                        words.append(cleaned)
                    }
                }
            }
        }

        return words
    }

    /// Разбивает строку таблицы по `|`, обрезает пробелы.
    /// `| a | b | c |` → ["a", "b", "c"]
    private static func splitTableRow(_ row: String) -> [String] {
        row.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Очищает ячейку: убирает backticks, проверяет на «пустые» маркеры.
    /// `Option` → Option ; — → "" ; пусто → ""
    private static func cleanWord(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)

        let emptyMarkers: Set<String> = ["", "—", "--", "-", "?", "n/a", "N/A"]
        if emptyMarkers.contains(cleaned) {
            return ""
        }
        return cleaned
    }
}
