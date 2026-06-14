//
//  SpeechWordsTab.swift
//  VoiceInk
//
//  "Words" tab of the Speech analytics page: top fillers, filler evolution
//  (auto-detector), top anglicisms, top repeated words. Pure presentation — all data
//  is precomputed/cached by the parent and passed in.
//

import SwiftUI
import Charts

struct SpeechWordsTab: View {
    let fillers: [(word: String, count: Int)]
    let anglicisms: [(word: String, count: Int)]
    let repetitions: [(word: String, count: Int)]
    let dynamics: AutoFillerDetector.Dynamics?
    let sparklines: [String: [(date: Date, value: Double)]]
    var loading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    LocalizedText(en: "Crunching your words…", ru: "Считаю слова…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            fillersSection
            fillerEvolution
            anglicismsSection
            repetitionsSection
        }
    }

    // MARK: - Top fillers

    private var fillersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Top fillers", ru: "Топ паразитов")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.topFillers, iconSize: .small, iconColor: .secondary)
            }

            if fillers.isEmpty {
                LocalizedText(en: "No fillers detected — well done!", ru: "Паразитов нет — молодец!")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(fillers.prefix(10), id: \.word) { item in
                        wordCountRow(item.word, count: item.count, color: .orange)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Filler evolution (auto-detector)

    @ViewBuilder
    private var fillerEvolution: some View {
        // Show the panel once there's enough history (active/observing exist); the
        // changes block below is gated separately by enoughData (two windows).
        if let dyn = dynamics, dyn.hasHistory, !dyn.active.isEmpty || !dyn.observing.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 2) {
                    LocalizedText(en: "Filler evolution", ru: "Эволюция паразитов")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    LocalizedText(en: "(auto-detected)", ru: "(определяется автоматически)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    InfoTip(message: SpeechMetricTips.fillerEvolution, iconSize: .small, iconColor: .secondary)
                }

                let changes = fillerChangeRows(dyn)
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(changes, id: \.0) { row in
                            HStack(spacing: 6) {
                                Image(systemName: row.1)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(row.2)
                                    .frame(width: 14)
                                Text(row.0)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }

                if !dyn.active.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(dyn.active.prefix(8)) { entry in
                            fillerActiveRow(entry)
                        }
                    }
                }

                if !dyn.observing.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedText(en: "Looks like new fillers — watching (not counted yet)",
                                      ru: "Похоже на новые паразиты — наблюдаю (пока не в счёт)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(dyn.observing.prefix(8).map { "«\($0.phrase)» \(String(format: "%.1f", $0.ratePer100))" }.joined(separator: "   "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            )
        }
    }

    private func fillerActiveRow(_ entry: AutoFillerDetector.FillerEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.phrase)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
            Text(String(format: "%.1f/100сл", entry.ratePer100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 80, alignment: .leading)
            let series = sparklines[entry.phrase] ?? []
            if series.count >= 2 {
                Chart {
                    ForEach(series, id: \.date) { p in
                        LineMark(x: .value("d", p.date), y: .value("r", p.value))
                            .foregroundStyle(.orange)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 22)
            } else {
                Spacer()
            }
            Text("\(entry.occurrences)×")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// Change rows: (text, icon, color).
    private func fillerChangeRows(_ dyn: AutoFillerDetector.Dynamics) -> [(String, String, Color)] {
        var rows: [(String, String, Color)] = []
        for c in dyn.appeared.prefix(3) {
            rows.append((L10n.t(en: "New: ", ru: "Появился: ") + "«\(c.phrase)» \(String(format: "%.1f", c.rateNow))/100сл", "plus.circle.fill", .red))
        }
        for c in dyn.grew.prefix(3) {
            rows.append((L10n.t(en: "Up: ", ru: "Вырос: ") + "«\(c.phrase)» \(String(format: "%.1f", c.ratePrev))→\(String(format: "%.1f", c.rateNow))", "arrow.up.circle.fill", .orange))
        }
        for c in dyn.dropped.prefix(3) {
            rows.append((L10n.t(en: "Down: ", ru: "Упал: ") + "«\(c.phrase)» \(String(format: "%.1f", c.ratePrev))→\(String(format: "%.1f", c.rateNow))", "arrow.down.circle.fill", .green))
        }
        for c in dyn.disappeared.prefix(3) {
            rows.append((L10n.t(en: "Gone: ", ru: "Избавился: ") + "«\(c.phrase)»", "checkmark.circle.fill", .green))
        }
        return rows
    }

    // MARK: - Top anglicisms

    private var anglicismsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Top anglicisms", ru: "Топ англицизмов")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.topAnglicisms, iconSize: .small, iconColor: .secondary)
            }

            if anglicisms.isEmpty {
                LocalizedText(en: "No anglicisms detected", ru: "Англицизмов не обнаружено")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(anglicisms.prefix(10), id: \.word) { item in
                        wordCountRow(item.word, count: item.count, color: .pink)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func wordCountRow(_ word: String, count: Int, color: Color) -> some View {
        HStack {
            Text(word)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
            Spacer()
            Text("\(count)×")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
    }

    // MARK: - Top repeated words

    private var repetitionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                LocalizedText(en: "Top repeated words", ru: "Топ повторяющихся слов")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                LocalizedText(
                    en: "(≥ 5 times in one dictation)",
                    ru: "(≥ 5 раз в одной диктовке)"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                InfoTip(message: SpeechMetricTips.topRepetitions, iconSize: .small, iconColor: .secondary)
            }

            if repetitions.isEmpty {
                LocalizedText(en: "No word over-repetition detected", ru: "Повторов не обнаружено")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(repetitions.prefix(10), id: \.word) { item in
                        wordCountRow(item.word, count: item.count, color: .purple)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
