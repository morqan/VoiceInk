//
//  SpeechMetricRecalcService.swift
//  VoiceInk
//
//  Одноразовая миграция: пересчёт исторических SpeechMetric под честные формулы
//  (PhraseOccurrenceScanner с границами слов, сложность без голого «что»).
//
//  Без пересчёта тренды/дельты/Match Score смешивали бы две линейки: старые записи
//  считались substring-матчем и завышенной сложностью — график делал бы «ступеньку»
//  на дате деплоя, выдавая смену формулы за изменение речи.
//
//  Текст транскрипции хранится в каждой записи — пересчитываем паразитов,
//  сложность и повторы заново. WPM/предложения/англицизмы не трогаем (их
//  алгоритмы не менялись). Паттерн — как SessionMetricMigrationService:
//  фоновый контекст + UserDefaults-флаг завершения.
//

import Foundation
import SwiftData
import OSLog

@MainActor
final class SpeechMetricRecalcService {
    static let shared = SpeechMetricRecalcService()

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "SpeechMetricRecalcService"
    )

    /// Версия в ключе: при следующем изменении формул достаточно поднять v.
    /// v3 — бэкафилл rawText + пересчёт паразитов под авто-детектор.
    /// v4 — добавлена метрика «гладкость» (самоисправления) для всей истории.
    private let completionKey = "SpeechMetricRecalc_v4_done"
    private(set) var isRunning = false

    private init() {}

    @discardableResult
    func runIfNeeded(modelContainer: ModelContainer) -> Task<Void, Never>? {
        guard !UserDefaults.standard.bool(forKey: completionKey), !isRunning else { return nil }
        isRunning = true

        let logger = self.logger
        let completionKey = self.completionKey

        return Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            do {
                let metrics = try context.fetch(FetchDescriptor<SpeechMetric>())

                // Шаг A: бэкафилл rawText для старых записей. Настоящий сырой ASR
                // тогда не сохранялся — лучшее доступное приближение = очищенный text.
                for metric in metrics where metric.rawText.isEmpty {
                    metric.rawText = metric.text
                }
                try context.save()

                // Шаг B: персональный активный список паразитов по ВСЕЙ истории.
                // Маркер-фразы стилей исключаем — иначе «слушайте»/«значит» уйдут
                // и в паразиты, и в тренер (конфликт).
                let profiles = (try? context.fetch(FetchDescriptor<VoiceProfileTarget>())) ?? []
                let markerExclude = Set(profiles.flatMap { $0.markerPhrases }.map { $0.lowercased() })
                let activeFillers = AutoFillerDetector.activeFillers(history: metrics, excluding: markerExclude)
                AutoFillerDetector.refreshCache(history: metrics, excluding: markerExclude)

                // Шаг C: пересчёт по сырому тексту с авто-списком.
                var updated = 0
                for metric in metrics {
                    let source = AutoFillerDetector.sourceText(metric)
                    guard !source.isEmpty else { continue }
                    let words = SpeechMetricsAnalyzer.extractWords(from: source)
                    guard !words.isEmpty else { continue }

                    let fillers = SpeechMetricsAnalyzer.countFillers(text: source, activeFillers: activeFillers)
                    let complexity = SpeechMetricsAnalyzer.calculateComplexity(
                        text: source,
                        sentenceCount: metric.sentenceCount
                    )
                    let repetitions = SpeechMetricsAnalyzer.countRepetitions(
                        words: words,
                        fillers: Set(fillers.keys),
                        anglicisms: Set(metric.anglicismsByWord.keys)
                    )
                    let selfCorrections = SpeechMetricsAnalyzer.countSelfCorrections(text: source, words: words)

                    metric.fillerCount = fillers.values.reduce(0, +)
                    metric.fillersByWordJSON = Self.encodeJSON(fillers)
                    metric.avgSentenceComplexity = complexity
                    metric.repetitionsByWordJSON = Self.encodeJSON(repetitions)
                    metric.selfCorrectionCount = selfCorrections.total
                    metric.selfCorrectionsByWordJSON = Self.encodeJSON(selfCorrections.byMarker)
                    updated += 1
                }

                try context.save()
                UserDefaults.standard.set(true, forKey: completionKey)
                logger.info("Speech metric recalc v4 done: \(updated) records (auto-filler + rawText + smoothness)")
            } catch {
                logger.error("Speech metric recalc failed: \(error.localizedDescription, privacy: .public)")
                // Флаг не ставим — попробуем на следующем запуске
            }

            await MainActor.run {
                SpeechMetricRecalcService.shared.isRunning = false
            }
        }
    }

    private nonisolated static func encodeJSON(_ dict: [String: Int]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
