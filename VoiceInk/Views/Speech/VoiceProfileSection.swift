//
//  VoiceProfileSection.swift
//  VoiceInk
//
//  Секция Voice Profile Match — сравнение реальной речи с целевым стилем.
//

import SwiftUI
import SwiftData

struct VoiceProfileSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoiceProfileTarget.name) private var profiles: [VoiceProfileTarget]

    /// Метрики за выбранный период (передаём из родителя).
    let metrics: [SpeechMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            profileSelector

            if let active = activeProfile {
                profileSummary(active)
                if let result = VoiceProfileMatcher.compute(target: active, metrics: metrics) {
                    totalScoreCard(result)
                    breakdown(result, profile: active)
                    Divider().padding(.vertical, 2)
                    styleCoach(result, profile: active)
                } else {
                    emptyState
                }
            } else {
                LocalizedText(en: "Choose a target style ↑", ru: "Выбери целевой стиль ↑")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.fill.viewfinder")
                .font(.system(size: 14))
                .foregroundStyle(.indigo)
            LocalizedText(en: "Voice Profile Match", ru: "Совпадение со стилем")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
            LocalizedText(en: "(target speech style)", ru: "(целевой стиль речи)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var profileSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profiles) { p in
                    Button {
                        activate(p)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: p.iconName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(profileDisplayName(p))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(p.isActive ? Color.indigo : Color.gray.opacity(0.15))
                        )
                        .foregroundColor(p.isActive ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Перевод названий пресетов на английский. Если профиль кастомный (не preset) —
    /// возвращаем как есть.
    private func profileDisplayName(_ p: VoiceProfileTarget) -> String {
        guard p.isPreset, L10n.current == .english else { return p.name }
        switch p.name {
        case "Эриксоновский гипнотизёр": return "Ericksonian Hypnotist"
        case "Жёсткий переговорщик":      return "Tactical Negotiator"
        case "Спокойный лидер":           return "Calm Leader"
        case "Харизматичный спикер":      return "Charismatic Speaker"
        default: return p.name
        }
    }

    /// Перевод summary пресета.
    private func profileSummaryText(_ p: VoiceProfileTarget) -> String {
        guard p.isPreset, L10n.current == .english else { return p.summary }
        switch p.name {
        case "Эриксоновский гипнотизёр":
            return "Slow pace, long subordinate sentences, embedded commands. Bypasses critical thinking through enveloping."
        case "Жёсткий переговорщик":
            return "Short direct sentences, framing constructions, minimum fluff. Controls conversation pace via clarity."
        case "Спокойный лидер":
            return "Medium pace, structured. List before action, clear priorities, zero fluff."
        case "Харизматичный спикер":
            return "Fast varied pace, direct address, few repetitions, emotional imagery."
        default: return p.summary
        }
    }

    private func profileSummary(_ profile: VoiceProfileTarget) -> some View {
        Text(profileSummaryText(profile))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func totalScoreCard(_ result: VoiceProfileMatcher.MatchResult) -> some View {
        HStack(spacing: 16) {
            // Circular score
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: CGFloat(result.totalScore / 100))
                    .stroke(scoreColor(result.totalScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(result.totalScore))")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor(result.totalScore))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    LocalizedText(en: "Match Score", ru: "Совпадение")
                        .font(.system(size: 13, weight: .semibold))
                    InfoTip(message: SpeechMetricTips.matchScore, iconSize: .small, iconColor: .secondary)
                }
                Text(matchVerdict(result.totalScore))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func breakdown(_ result: VoiceProfileMatcher.MatchResult, profile: VoiceProfileTarget) -> some View {
        VStack(spacing: 6) {
            metricRow(
                L10n.t(en: "Speed (WPM)", ru: "Темп (WPM)"),
                tip: SpeechMetricTips.axisWPM,
                actual: result.actualWPM,
                target: String(format: "→ %.0f", profile.targetWPM),
                format: "%.0f",
                score: result.wpmScore
            )
            metricRow(
                L10n.t(en: "Sentence length", ru: "Длина предложения"),
                tip: SpeechMetricTips.axisSentence,
                actual: result.actualSentenceLength,
                target: String(format: "→ %.0f", profile.targetSentenceLength),
                format: "%.0f",
                score: result.sentenceLengthScore
            )
            metricRow(
                L10n.t(en: "Complexity", ru: "Сложность"),
                tip: SpeechMetricTips.axisComplexity,
                actual: result.actualComplexity,
                target: String(format: "→ %.1f", profile.targetComplexity),
                format: "%.1f",
                score: result.complexityScore
            )
            metricRow(
                L10n.t(en: "Fillers /100w", ru: "Паразиты /100сл"),
                tip: SpeechMetricTips.axisFillers,
                actual: result.actualFillerRate,
                target: String(format: "→ ≤ %.0f", profile.maxFillerRate),
                format: "%.1f",
                score: result.fillerScore
            )
            metricRow(
                L10n.t(en: "Marker phrases /100w", ru: "Маркеры /100сл"),
                tip: SpeechMetricTips.axisMarkers(phrases: profile.markerPhrases),
                actual: result.actualMarkerRatePer100Words,
                target: String(format: "→ ≥ %.0f", profile.targetMarkerRatePer100Words),
                format: "%.1f",
                score: result.markerScore
            )
        }
        .padding(.top, 6)
    }

    private func metricRow(
        _ name: String,
        tip: String,
        actual: Double,
        target: String,
        format: String,
        score: Double
    ) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                InfoTip(message: tip, iconSize: .small, iconColor: .secondary)
                Spacer(minLength: 0)
            }
            .frame(width: 170, alignment: .leading)
            Text(String(format: format, actual))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
            // Цель профиля по этой оси — чтобы было видно, в какую сторону тянуть
            Text(target)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            // Прогресс-бар
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * CGFloat(score / 100), height: 6)
                }
            }
            .frame(height: 6)
            Text("\(Int(score))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(scoreColor(score))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func suggestion(_ result: VoiceProfileMatcher.MatchResult) -> some View {
        let weak = result.weakestMetric
        return HStack(spacing: 8) {
            Image(systemName: weak.gain >= 1 ? "lightbulb.fill" : "checkmark.seal.fill")
                .foregroundStyle(weak.gain >= 1 ? .yellow : .green)
                .font(.system(size: 12))
            // При gain < 1 все оси у цели — совет «подтягивай» был бы абсурдным
            Text(weak.gain >= 1
                ? L10n.t(
                    en: "Pull up first: \(axisName(weak.axis)) (\(Int(weak.score))%) — up to +\(Int(weak.gain.rounded())) to the total score",
                    ru: "Подтягивай в первую очередь: \(axisName(weak.axis)) (\(Int(weak.score))%) — до +\(Int(weak.gain.rounded())) к общему результату"
                )
                : L10n.t(
                    en: "All axes are on target — keep it up",
                    ru: "Все оси у цели — держи уровень"
                )
            )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Style coach (обучающий блок «Как дойти до стиля»)

    private static let minSessionsForCoach = 3
    private static let minWordsForCoach = 150

    @ViewBuilder
    private func styleCoach(_ result: VoiceProfileMatcher.MatchResult, profile: VoiceProfileTarget) -> some View {
        let totalWords = metrics.reduce(0) { $0 + $1.wordCount }
        let unlocked = result.sampleSize >= Self.minSessionsForCoach && totalWords >= Self.minWordsForCoach
        let key = VoiceStyleKey.from(profile: profile)
        // Оси у цели (.onTarget) исключаем: тянуть нечего, а направление-глагол был бы ложным.
        let cards = Array(result.axesByGain
            .filter { $0.weightedGain >= 1 && $0.direction != .onTarget }
            .prefix(3))

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo)
                LocalizedText(en: "How to reach the style", ru: "Как дойти до стиля")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }

            if !unlocked {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.t(
                        en: "Coach unlocks after \(Self.minSessionsForCoach) dictations (≥\(Self.minWordsForCoach) words) — keep dictating",
                        ru: "Тренер появится после \(Self.minSessionsForCoach) диктовок (≥\(Self.minWordsForCoach) слов) — продолжай диктовать"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else if cards.isEmpty {
                suggestion(result)
            } else {
                // .id(profile.id) — при смене профиля карточки пересоздаются,
                // чтобы expanded переинициализировался под новый стиль (а не залипал).
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cards) { bd in
                        CoachCard(
                            breakdown: bd,
                            styleKey: key,
                            markerUsage: bd.axis == .markers ? result.markerUsage : [],
                            topFillers: bd.axis == .fillers ? topPersonalFillers() : [],
                            defaultExpanded: bd.id == cards.first?.id
                        )
                    }
                }
                .id(profile.id)
            }
        }
    }

    /// Топ-3 личных паразита за период (для карточки оси fillers).
    private func topPersonalFillers() -> [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for m in metrics {
            for (word, count) in m.fillersByWord {
                totals[word, default: 0] += count
            }
        }
        return totals
            .map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }
    }

    private func axisName(_ axis: VoiceProfileMatcher.Axis) -> String {
        switch axis {
        case .wpm:            return L10n.t(en: "Speed (WPM)", ru: "Темп (WPM)")
        case .sentenceLength: return L10n.t(en: "Sentence length", ru: "Длина предложения")
        case .complexity:     return L10n.t(en: "Complexity", ru: "Сложность")
        case .fillers:        return L10n.t(en: "Fillers", ru: "Паразиты")
        case .markers:        return L10n.t(en: "Marker phrases", ru: "Маркер-фразы")
        }
    }

    private var emptyState: some View {
        LocalizedText(
            en: "Metrics will appear after your first dictation ≥ 15 words",
            ru: "Метрики появятся после первой диктовки ≥ 15 слов"
        )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var activeProfile: VoiceProfileTarget? {
        profiles.first { $0.isActive }
    }

    private func activate(_ target: VoiceProfileTarget) {
        for p in profiles {
            p.isActive = (p.id == target.id)
        }
        try? modelContext.save()
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    private func matchVerdict(_ score: Double) -> String {
        switch score {
        case 90...:    return L10n.t(en: "You sound like this style", ru: "Звучишь как этот стиль")
        case 75..<90:  return L10n.t(en: "Close to the style", ru: "Близко к стилю")
        case 50..<75:  return L10n.t(en: "Partial match — room to grow", ru: "Местами совпадает — есть к чему расти")
        case 25..<50:  return L10n.t(en: "Far from the style — lots to do", ru: "Далеко от стиля — много работы")
        default:       return L10n.t(en: "Completely different style", ru: "Совсем другой стиль речи")
        }
    }
}

// MARK: - Карточка тренера по одной оси

private struct CoachCard: View {
    let breakdown: VoiceProfileMatcher.AxisBreakdown
    let styleKey: VoiceStyleKey?
    let markerUsage: [VoiceProfileMatcher.MarkerPhraseUsage]
    let topFillers: [(word: String, count: Int)]
    let defaultExpanded: Bool

    @State private var expanded: Bool

    init(
        breakdown: VoiceProfileMatcher.AxisBreakdown,
        styleKey: VoiceStyleKey?,
        markerUsage: [VoiceProfileMatcher.MarkerPhraseUsage],
        topFillers: [(word: String, count: Int)],
        defaultExpanded: Bool
    ) {
        self.breakdown = breakdown
        self.styleKey = styleKey
        self.markerUsage = markerUsage
        self.topFillers = topFillers
        self.defaultExpanded = defaultExpanded
        _expanded = State(initialValue: defaultExpanded)
    }

    private var pattern: CoachingPattern? {
        VoiceStyleCoaching.patterns(for: styleKey, axis: breakdown.axis).first
    }

    /// Краткая подсказка: стиле-специфичная для пресета, иначе generic по направлению.
    private var drillText: String? {
        if let s = VoiceStyleCoaching.axisDrill(for: styleKey, axis: breakdown.axis) {
            return s.text
        }
        if let g = VoiceStyleCoaching.genericDrill(axis: breakdown.axis, direction: breakdown.direction) {
            return g.how.text
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок-дельта + бейдж прироста
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(deltaTitle)
                    .font(.system(size: 12, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("+\(Int(breakdown.weightedGain.rounded()))")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
                    .foregroundStyle(.green)
            }

            // Краткая подсказка «что делать»
            if let drillText {
                Text(drillText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Спец-контент по оси
            if breakdown.axis == .markers, !markerUsage.isEmpty {
                markerChips
            }
            if breakdown.axis == .fillers, !topFillers.isEmpty {
                fillerChips
            }

            // Раскрывашка: приём стиля с формулой и примерами
            if let pattern {
                DisclosureGroup(isExpanded: $expanded) {
                    patternBody(pattern)
                        .padding(.top, 6)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(L10n.t(en: "Technique: ", ru: "Приём: ") + pattern.name.text)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .tint(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: Pattern body

    @ViewBuilder
    private func patternBody(_ p: CoachingPattern) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.what.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Формула-шаблон
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "function")
                    .font(.system(size: 10))
                    .foregroundStyle(.indigo)
                    .padding(.top, 2)
                Text(p.formula.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.08)))

            // Примеры
            ForEach(Array(p.examples.enumerated()), id: \.offset) { _, ex in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text(ex)
                        .font(.system(size: 11))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Слова именно этого приёма — что добавить в речь
            if !p.relatedMarkers.isEmpty {
                Text(L10n.t(en: "Words of this technique: ", ru: "Слова приёма: ")
                     + p.relatedMarkers.map { "«\($0)»" }.joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(.indigo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Marker chips

    private var markerChips: some View {
        let foundCount = markerUsage.filter { $0.isUsed }.count
        return VStack(alignment: .leading, spacing: 6) {
            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(markerUsage) { usage in
                    MarkerChip(usage: usage)
                }
            }
            Text(L10n.t(
                en: "found \(foundCount) / \(markerUsage.count) phrases",
                ru: "найдено \(foundCount) / \(markerUsage.count) фраз"
            ))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var fillerChips: some View {
        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(topFillers.enumerated()), id: \.offset) { _, item in
                Text("\(item.word) ×\(item.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Delta title

    private var deltaTitle: String {
        let a = String(format: axisFormat, breakdown.actual)
        let t = String(format: axisFormat, breakdown.target)
        let unit = axisUnit
        let arrow = breakdown.axis == .fillers ? "→ ≤ " : (breakdown.axis == .markers ? "→ ≥ " : "→ ")
        return "\(verb): \(a) \(arrow)\(t)\(unit)"
    }

    private var verb: String {
        switch breakdown.axis {
        case .wpm:
            return breakdown.direction == .increase
                ? L10n.t(en: "Speed up", ru: "Ускорь")
                : L10n.t(en: "Slow down", ru: "Замедли")
        case .sentenceLength:
            return breakdown.direction == .increase
                ? L10n.t(en: "Lengthen", ru: "Удлиняй")
                : L10n.t(en: "Shorten", ru: "Руби короче")
        case .complexity:
            return breakdown.direction == .increase
                ? L10n.t(en: "Add depth", ru: "Усложняй")
                : L10n.t(en: "Simplify", ru: "Упрощай")
        case .fillers:
            return L10n.t(en: "Fewer fillers", ru: "Меньше паразитов")
        case .markers:
            return L10n.t(en: "Add markers", ru: "Добавь маркеров")
        }
    }

    private var axisFormat: String {
        switch breakdown.axis {
        case .wpm, .sentenceLength: return "%.0f"
        default: return "%.1f"
        }
    }

    private var axisUnit: String {
        switch breakdown.axis {
        case .wpm: return " WPM"
        case .sentenceLength: return L10n.t(en: " words", ru: " слов")
        case .complexity: return ""
        case .fillers, .markers: return L10n.t(en: " /100w", ru: " /100сл")
        }
    }
}

// MARK: - Одна chip фразы-маркера

private struct MarkerChip: View {
    let usage: VoiceProfileMatcher.MarkerPhraseUsage
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Text(usage.phrase)
                .font(.system(size: 10, weight: .medium))
            if usage.isUsed {
                if usage.isAmbiguousSingleToken {
                    // Возможно ложное срабатывание (substring внутри другого слова)
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 8))
                        .help(L10n.t(
                            en: "Matched by substring — may be a false positive (inside another word)",
                            ru: "Засчитано по подстроке — возможно ложно (внутри другого слова)"
                        ))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            } else {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(usage.phrase, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help(L10n.t(en: "Copy phrase", ru: "Скопировать фразу"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(chipFill)
        )
        .overlay(
            Capsule().strokeBorder(
                usage.isUsed ? Color.clear : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: 1, dash: usage.isUsed ? [] : [3, 2])
            )
        )
        .foregroundStyle(usage.isUsed ? Color.white : Color.secondary)
    }

    private var chipFill: Color {
        guard usage.isUsed else { return Color.gray.opacity(0.08) }
        // надёжно использованная — насыщенный indigo; возможно ложная — приглушённый
        return usage.isAmbiguousSingleToken ? Color.indigo.opacity(0.45) : Color.indigo
    }
}

// MARK: - Простая wrap-раскладка для chips (macOS 14+)

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !(rows[rows.count - 1].isEmpty) {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let width = maxWidth == .infinity
            ? rows.map { max(0, $0.reduce(0) { $0 + $1.width + spacing } - spacing) }.max() ?? 0
            : maxWidth
        var height: CGFloat = 0
        for row in rows {
            let rowHeight = row.map(\.height).max() ?? 0
            height += rowHeight + lineSpacing
        }
        height = max(0, height - lineSpacing)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
