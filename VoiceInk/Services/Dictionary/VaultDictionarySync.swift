//
//  VaultDictionarySync.swift
//  VoiceInk
//
//  Automatic dictionary synchronization with a markdown file.
//  The path comes from UserDefaults (configurable in Dictionary Settings → Vault Sync).
//
//  On each app launch it reads the markdown file and pulls new words
//  into VocabularyWord (via DictionaryService). Existing words are not duplicated.
//  If the file is missing or sync is disabled, it silently skips without crashing.
//

import Foundation
import SwiftData
import OSLog

enum VaultDictionarySync {

    private static let logger = Logger(
        subsystem: "com.morqan.voiceink",
        category: "VaultDictionarySync"
    )

    /// The result of a synchronization run.
    struct Result {
        let added: Int       // how many words were added this time
        let totalParsed: Int // how many words were extracted from the file in total
        let skipped: Bool    // true if sync was skipped (disabled / no file)
        let error: String?   // error text if something went wrong

        var summary: String {
            if let error = error { return "Error: \(error)" }
            if skipped { return "Skipped" }
            if added == 0 { return "All \(totalParsed) words already in dictionary" }
            return "Added \(added) of \(totalParsed) words"
        }
    }

    /// Main entry point. Reads settings, parses the markdown, adds words.
    @discardableResult
    static func syncFromVault(context: ModelContext) -> Result {
        // 1. Check that sync is enabled
        let enabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.vaultSyncEnabled)
        guard enabled else {
            logger.info("Vault sync disabled in settings")
            return Result(added: 0, totalParsed: 0, skipped: true, error: nil)
        }

        // 2. Get the path from settings, expand ~
        let rawPath = UserDefaults.standard.string(forKey: UserDefaults.Keys.vaultDictionaryPath) ?? ""
        let path = NSString(string: rawPath).expandingTildeInPath
        guard !path.isEmpty else {
            logger.info("Vault dictionary path is empty")
            return Result(added: 0, totalParsed: 0, skipped: true, error: nil)
        }

        // 3. Check that the file exists
        guard FileManager.default.fileExists(atPath: path) else {
            logger.info("Vault dictionary not found at \(path, privacy: .public)")
            return Result(added: 0, totalParsed: 0, skipped: true, error: "File not found at \(path)")
        }

        do {
            // 4. Read and parse
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let words = parseWords(from: content)

            guard !words.isEmpty else {
                logger.info("No words extracted from \(path, privacy: .public)")
                return Result(added: 0, totalParsed: 0, skipped: false, error: nil)
            }

            // 5. Deduplicate against existing words
            let descriptor = FetchDescriptor<VocabularyWord>()
            let existing = (try? context.fetch(descriptor)) ?? []
            let existingLower = Set(existing.map { $0.word.lowercased() })

            let newWords = words.filter { !existingLower.contains($0.lowercased()) }

            guard !newWords.isEmpty else {
                logger.info("Vault sync: all \(words.count) words already in dictionary")
                return Result(added: 0, totalParsed: words.count, skipped: false, error: nil)
            }

            // 6. Add via DictionaryService
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

    /// Parses a markdown table and extracts words from the "Правильное написание" column.
    ///
    /// Expected table format:
    /// ```
    /// | Что сказал Морган | Как услышал Whisper | Правильное написание | Дата | Перенесено? |
    /// |---|---|---|---|---|
    /// | Option | общин | `Option` | 2026-05-05 | — |
    /// ```
    ///
    /// Surrounding backticks are stripped: `Option` → Option.
    /// Empty cells (—, --, blank string) are skipped.
    static func parseWords(from content: String) -> [String] {
        var words: [String] = []
        let lines = content.components(separatedBy: .newlines)

        var inTable = false
        var headerSkipped = false
        var correctWritingColumnIndex: Int?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Header row containing the "Правильное написание" column
            if !inTable && trimmed.hasPrefix("|") && trimmed.contains("Правильное написание") {
                inTable = true
                let columns = splitTableRow(trimmed)
                correctWritingColumnIndex = columns.firstIndex { $0 == "Правильное написание" }
                continue
            }

            // Already in the table but the line does not start with | — the table has ended
            if inTable && !trimmed.hasPrefix("|") {
                inTable = false
                headerSkipped = false
                correctWritingColumnIndex = nil
                continue
            }

            // Separator row |---|---|...
            if inTable && trimmed.contains("---") {
                headerSkipped = true
                continue
            }

            // Data row
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

    /// Splits a table row on `|` and trims whitespace.
    /// `| a | b | c |` → ["a", "b", "c"]
    private static func splitTableRow(_ row: String) -> [String] {
        row.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Cleans a cell: removes backticks, checks for "empty" markers.
    /// `Option` → Option ; — → "" ; blank → ""
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
