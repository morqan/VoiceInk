//
//  SpeechVaultExport.swift
//  VoiceInk
//
//  Экспорт недельного отчёта речевой аналитики в Obsidian Vault.
//  Markdown с frontmatter: метрики недели vs прошлая, Match Score с разбором осей,
//  топ паразитов/англицизмов/повторов и рекомендация тренера.
//
//  Путь — UserDefaults (Keys.speechReportFolder), по умолчанию
//  «10 - Reviews/Speech» в Vault Моргана. Пишем напрямую (sandbox выключен),
//  как и VaultDictionarySync.
//

import Foundation
import OSLog

enum SpeechVaultExport {

    private static let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "SpeechVaultExport"
    )

    static let defaultFolder = "~/Documents/Obsidian Vault/10 - Reviews/Speech"

    /// Папка для отчётов с развёрнутой тильдой.
    static var reportFolder: String {
        let raw = UserDefaults.standard.string(forKey: UserDefaults.Keys.speechReportFolder) ?? defaultFolder
        return NSString(string: raw.isEmpty ? defaultFolder : raw).expandingTildeInPath
    }

    struct ExportResult {
        let path: String?
        let error: String?
        var succeeded: Bool { path != nil && error == nil }
    }

    /// Собирает отчёт за последние 7 дней (со сравнением с предыдущими 7) и пишет в Vault.
    static func exportWeek(allMetrics: [SpeechMetric], profile: VoiceProfileTarget?, now: Date = Date()) -> ExportResult {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        guard let weekStart = cal.date(byAdding: .day, value: -6, to: todayStart),
              let prevWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart) else {
            return ExportResult(path: nil, error: "Calendar math failed")
        }

        let week = allMetrics.filter { $0.timestamp >= weekStart }
        let prevWeek = allMetrics.filter { $0.timestamp >= prevWeekStart && $0.timestamp < weekStart }

        guard !week.isEmpty else {
            return ExportResult(path: nil, error: L10n.t(
                en: "No dictations in the last 7 days — nothing to export",
                ru: "За последние 7 дней нет диктовок — экспортировать нечего"
            ))
        }

        let markdown = buildMarkdown(week: week, prevWeek: prevWeek, profile: profile, now: now)

        // Имя файла по дате конца окна — отчёт покрывает скользящие 7 дней,
        // а не календарную ISO-неделю, и имя не должно врать о содержимом.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let fileName = "Speech Week — \(df.string(from: now)).md"

        let folder = reportFolder
        let filePath = (folder as NSString).appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)
            logger.info("Speech week report exported to \(filePath, privacy: .public)")
            return ExportResult(path: filePath, error: nil)
        } catch {
            logger.error("Speech report export failed: \(error.localizedDescription, privacy: .public)")
            return ExportResult(path: nil, error: error.localizedDescription)
        }
    }

    // MARK: - Markdown

    private static func buildMarkdown(
        week: [SpeechMetric],
        prevWeek: [SpeechMetric],
        profile: VoiceProfileTarget?,
        now: Date
    ) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: now)
        let cal = Calendar.current
        let windowStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
        let startStr = df.string(from: windowStart)

        var md = """
        ---
        тип: отчёт
        дата: \(dateStr)
        период_с: \(startStr)
        период_до: \(dateStr)
        источник: VoiceInk
        теги: [speech, voiceink, weekly-report]
        ---

        # 🎙 Speech Week — \(dateStr)

        > Автоотчёт VoiceInk: скользящие 7 дней \(startStr) — \(dateStr). Сессий: \(week.count), слов: \(words(week)).

        ## Метрики (vs прошлая неделя)

        | Метрика | Сейчас | Прошлая | Δ |
        |---|---|---|---|
        \(metricRow("Паразиты /100сл", fillerRate(week), fillerRate(prevWeek), prevWeek.isEmpty, "%.1f"))
        \(metricRow("Длина предложения, слов", sentenceLength(week), sentenceLength(prevWeek), prevWeek.isEmpty, "%.0f"))
        \(metricRow("Англицизмы /100сл", anglicismRate(week), anglicismRate(prevWeek), prevWeek.isEmpty, "%.1f"))
        \(metricRow("Темп, WPM", wpm(week), wpm(prevWeek), prevWeek.isEmpty, "%.0f"))
        \(metricRow("Сложность", complexity(week), complexity(prevWeek), prevWeek.isEmpty, "%.1f"))
        \(metricRow("Всего слов", Double(words(week)), Double(words(prevWeek)), prevWeek.isEmpty, "%.0f"))

        """

        // Совпадение со стилем
        if let profile, let result = VoiceProfileMatcher.compute(target: profile, metrics: week) {
            let prevResult = prevWeek.isEmpty ? nil : VoiceProfileMatcher.compute(target: profile, metrics: prevWeek)
            let deltaStr = prevResult.map { String(format: " (прошлая неделя: %.0f)", $0.totalScore) } ?? ""

            md += """

            ## Совпадение со стилем «\(profile.name)»

            **Score: \(Int(result.totalScore))/100**\(deltaStr)

            | Ось | Факт | Цель | Score |
            |---|---|---|---|
            | Темп (WPM) | \(String(format: "%.0f", result.actualWPM)) | \(String(format: "%.0f", profile.targetWPM)) | \(Int(result.wpmScore))% |
            | Длина предложения | \(String(format: "%.0f", result.actualSentenceLength)) | \(String(format: "%.0f", profile.targetSentenceLength)) | \(Int(result.sentenceLengthScore))% |
            | Сложность | \(String(format: "%.1f", result.actualComplexity)) | \(String(format: "%.1f", profile.targetComplexity)) | \(Int(result.complexityScore))% |
            | Паразиты /100сл | \(String(format: "%.1f", result.actualFillerRate)) | ≤ \(String(format: "%.0f", profile.maxFillerRate)) | \(Int(result.fillerScore))% |
            | Маркеры /100сл | \(String(format: "%.1f", result.actualMarkerRatePer100Words)) | ≥ \(String(format: "%.0f", profile.targetMarkerRatePer100Words)) | \(Int(result.markerScore))% |

            *Маркеры — с анти-накруточным капом: одна фраза покрывает не более 40% цели.*

            """

            // Рекомендация тренера: ось с максимальным приростом + дрилл стиля
            let weak = result.weakestMetric
            if weak.gain >= 1 {
                let axisName = axisDisplayName(weak.axis)
                md += "\n**Подтянуть в первую очередь:** \(axisName) (\(Int(weak.score))%) — до +\(Int(weak.gain.rounded())) к скору.\n"
                let key = VoiceStyleKey.from(profile: profile)
                if let drill = VoiceStyleCoaching.axisDrill(for: key, axis: weak.axis) {
                    md += "\n> [!tip] Тренер\n> \(drill.ru)\n"
                }
                // Неиспользованные маркер-фразы — конкретный план
                if weak.axis == .markers {
                    let unused = result.markerUsage.filter { !$0.isUsed }.map { "«\($0.phrase)»" }
                    if !unused.isEmpty {
                        md += "\nНеиспользованные фразы профиля: \(unused.joined(separator: ", ")).\n"
                    }
                }
            } else {
                md += "\nВсе оси у цели — держать уровень.\n"
            }
        }

        // Топы
        md += topSection("Топ паразитов", topWords(week, \.fillersByWord))
        md += topSection("Топ англицизмов", topWords(week, \.anglicismsByWord))
        md += topSection("Топ повторов", topWords(week, \.repetitionsByWord))

        md += """

        ---

        *Сгенерировано VoiceInk \(dateStr). Метрики считаются по тексту транскрипций \
        (ASR-нормализация занижает паразитов, темп считается со временем пауз).*
        """

        return md
    }

    // MARK: - Helpers (агрегации — те же формулы, что на дашборде)

    private static func words(_ ms: [SpeechMetric]) -> Int {
        ms.reduce(0) { $0 + $1.wordCount }
    }

    private static func fillerRate(_ ms: [SpeechMetric]) -> Double {
        let w = words(ms)
        guard w > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.fillerCount }) / Double(w) * 100
    }

    private static func anglicismRate(_ ms: [SpeechMetric]) -> Double {
        let w = words(ms)
        guard w > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.anglicismCount }) / Double(w) * 100
    }

    private static func sentenceLength(_ ms: [SpeechMetric]) -> Double {
        let sentences = ms.reduce(0) { $0 + $1.sentenceCount }
        guard sentences > 0 else { return 0 }
        return Double(words(ms)) / Double(sentences)
    }

    private static func wpm(_ ms: [SpeechMetric]) -> Double {
        let timed = ms.filter { $0.durationSeconds > 0 && $0.wordCount > 0 }
        let minutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        guard minutes > 0 else { return 0 }
        return Double(timed.reduce(0) { $0 + $1.wordCount }) / minutes
    }

    private static func complexity(_ ms: [SpeechMetric]) -> Double {
        let w = words(ms)
        guard w > 0 else { return 0 }
        return ms.reduce(0.0) { $0 + $1.avgSentenceComplexity * Double($1.wordCount) } / Double(w)
    }

    private static func metricRow(_ name: String, _ current: Double, _ previous: Double, _ noPrev: Bool, _ fmt: String) -> String {
        let cur = String(format: fmt, current)
        guard !noPrev else { return "| \(name) | \(cur) | — | — |" }
        let prev = String(format: fmt, previous)
        let diff = current - previous
        let diffStr = String(format: fmt, abs(diff))
        // Сравниваем после форматирования: «▲ 0.0» со стрелкой вводит в заблуждение
        if (Double(diffStr) ?? 0) == 0 {
            return "| \(name) | \(cur) | \(prev) | = |"
        }
        let arrow = diff > 0 ? "▲" : "▼"
        return "| \(name) | \(cur) | \(prev) | \(arrow) \(diffStr) |"
    }

    private static func topWords(_ ms: [SpeechMetric], _ keyPath: KeyPath<SpeechMetric, [String: Int]>) -> [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for m in ms {
            for (word, count) in m[keyPath: keyPath] {
                totals[word, default: 0] += count
            }
        }
        return totals
            .map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    private static func topSection(_ title: String, _ items: [(word: String, count: Int)]) -> String {
        guard !items.isEmpty else { return "" }
        var s = "\n## \(title)\n\n"
        for item in items {
            s += "- \(item.word) — \(item.count)×\n"
        }
        return s
    }

    private static func axisDisplayName(_ axis: VoiceProfileMatcher.Axis) -> String {
        switch axis {
        case .wpm:            return "Темп (WPM)"
        case .sentenceLength: return "Длина предложения"
        case .complexity:     return "Сложность"
        case .fillers:        return "Паразиты"
        case .markers:        return "Маркер-фразы"
        }
    }
}
