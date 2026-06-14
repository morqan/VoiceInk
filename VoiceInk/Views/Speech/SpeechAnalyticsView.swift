//
//  SpeechAnalyticsView.swift
//  VoiceInk
//
//  полная аналитика речи.
//
//  Включает:
//   - Period selector (Today / Week / Month)
//   - 4 агрегированные метрики (filler / sentence / anglicism / WPM)
//   - Графики тренда за 30 дней (WPM, filler rate)
//   - Top fillers — таблица
//   - Top anglicisms — таблица
//   - Recent sessions — последние диктовки
//

import SwiftUI
import SwiftData
import Charts

enum SpeechPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return L10n.t(en: "Today", ru: "Сегодня")
        case .week:  return L10n.t(en: "Week", ru: "Неделя")
        case .month: return L10n.t(en: "Month", ru: "Месяц")
        case .all:   return L10n.t(en: "All", ru: "Всё")
        }
    }

    /// Начало периода. Возвращает nil для .all (без фильтра).
    func startDate(now: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: now)
        case .week:  return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))
        case .month: return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))
        case .all:   return nil
        }
    }
}

enum SpeechTab: String, CaseIterable, Identifiable {
    case overview
    case words
    case coach
    case history

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: return L10n.t(en: "Overview", ru: "Обзор")
        case .words:    return L10n.t(en: "Words", ru: "Слова")
        case .coach:    return L10n.t(en: "Coach", ru: "Тренер")
        case .history:  return L10n.t(en: "History", ru: "История")
        }
    }
}

/// Result of the off-main Words-tab recompute.
private struct WordsTabData {
    let fillers: [(word: String, count: Int)]
    let anglicisms: [(word: String, count: Int)]
    let repetitions: [(word: String, count: Int)]
    let dynamics: AutoFillerDetector.Dynamics
    let sparklines: [String: [(date: Date, value: Double)]]
}

struct SpeechAnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var period: SpeechPeriod = .week
    @State private var tab: SpeechTab = .overview
    @Query(sort: \SpeechMetric.timestamp, order: .reverse) private var allMetrics: [SpeechMetric]
    @Query(sort: \VoiceProfileTarget.name) private var styleProfiles: [VoiceProfileTarget]
    @State private var selectedMetric: SpeechMetric?
    @State private var exportFeedback: String?
    @State private var exportFeedbackTask: DispatchWorkItem?
    @State private var showExportSettings = false
    /// Кэш дневной серии Match Score: compute() сканирует тексты всех сессий
    /// периода — пересчитывать на каждый рендер body слишком дорого.
    @State private var cachedMatchSeries: [(date: Date, value: Double)] = []
    /// Кэш авто-детектора паразитов (тоже сканирует всю историю).
    @State private var fillerDynamics: AutoFillerDetector.Dynamics?
    /// Кэш дневных рядов для sparkline активных паразитов (считаем в .task, не в body).
    @State private var fillerSparklines: [String: [(date: Date, value: Double)]] = [:]
    /// Cached exercise of the day — built off the render path in `.task` because it
    /// scans recent dictations for under-used marker phrases.
    @State private var cachedExercise: DailyExercise?
    /// Cached top-word lists for the Words tab — each one JSON-decodes every metric,
    /// so they're built in `.task`, not recomputed on every render.
    @State private var topFillerList: [(word: String, count: Int)] = []
    @State private var topAnglicismList: [(word: String, count: Int)] = []
    @State private var topRepetitionList: [(word: String, count: Int)] = []
    /// Cached streaks for the Coach tab — each one scans all history, so compute once.
    @State private var cachedStreaks: (filler: Int, anglicism: Int, sentence: Int) = (0, 0, 0)
    /// Words tab recompute runs off-main; this drives a spinner so the tab never freezes.
    @State private var wordsLoading = false
    /// Last data key the Words/Coach tabs were computed for — skip recompute on re-entry
    /// when nothing changed (re-entering a tab shouldn't re-crunch identical data).
    @State private var lastWordsKey = ""
    @State private var lastCoachKey = ""
    @AppStorage(UserDefaults.Keys.speechReportFolder) private var reportFolder: String = SpeechVaultExport.defaultFolder

    private var activeStyleProfile: VoiceProfileTarget? {
        styleProfiles.first { $0.isActive }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                tabPicker
                periodSelector
                tabContent
            }
            .padding(28)
        }
        .background(Color(.windowBackgroundColor))
        .sheet(item: $selectedMetric) { metric in
            SpeechSessionDetailView(metric: metric, profile: activeStyleProfile)
        }
        // Exercise + match-series depend on data/period, NOT the tab — so switching
        // sub-tabs no longer re-runs them (that was the main sub-tab-switch lag).
        .task(id: exerciseKey) {
            cachedExercise = DailyExerciseGenerator.forToday(profile: activeStyleProfile, metrics: allMetrics)
        }
        .task(id: chartsKey) {
            cachedMatchSeries = computeDailyMatchSeries()
        }
        // Heavy per-tab scans fire only when that tab is active, once per data/period.
        .task(id: wordsKey) {
            guard tab == .words else { return }
            // Skip recompute when the data hasn't changed since last time (re-entering the
            // tab shouldn't re-crunch identical data).
            let dataKey = "\(period.rawValue)|\(dataStamp)"
            guard dataKey != lastWordsKey else { return }
            lastWordsKey = dataKey
            // Heavy: scans full history (computeDynamics + refreshCache) + JSON-decodes
            // every metric. Runs OFF the main thread so the tab never freezes; a spinner
            // shows while it computes.
            wordsLoading = true
            let container = modelContext.container
            let start = period.startDate()
            let prevDays: Int
            switch period {
            case .today: prevDays = 1
            case .week:  prevDays = 7
            case .month: prevDays = 30
            case .all:   prevDays = 0
            }
            let prevStart = start.flatMap { Calendar.current.date(byAdding: .day, value: -prevDays, to: $0) }
            let markerExclude = Set(styleProfiles.flatMap { $0.markerPhrases }.map { $0.lowercased() })

            let data = await Task.detached(priority: .userInitiated) { () -> WordsTabData in
                let ctx = ModelContext(container)
                let all = (try? ctx.fetch(FetchDescriptor<SpeechMetric>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? []
                let current = start.map { s in all.filter { $0.timestamp >= s } } ?? all
                let previous: [SpeechMetric]
                if let s = start, let ps = prevStart {
                    previous = all.filter { $0.timestamp >= ps && $0.timestamp < s }
                } else {
                    previous = []
                }
                let dyn = AutoFillerDetector.computeDynamics(history: all, current: current, previous: previous, excluding: markerExclude)
                AutoFillerDetector.refreshCache(history: all, excluding: markerExclude)
                return WordsTabData(
                    fillers: SpeechAggregates.topWords(current) { $0.fillersByWord },
                    anglicisms: SpeechAggregates.topWords(current) { $0.anglicismsByWord },
                    repetitions: SpeechAggregates.topWords(current) { $0.repetitionsByWord },
                    dynamics: dyn,
                    sparklines: AutoFillerDetector.dailyRateSeries(phrases: dyn.active.prefix(8).map { $0.phrase }, in: current)
                )
            }.value

            guard tab == .words else { wordsLoading = false; return }
            topFillerList = data.fillers
            topAnglicismList = data.anglicisms
            topRepetitionList = data.repetitions
            fillerDynamics = data.dynamics
            fillerSparklines = data.sparklines
            wordsLoading = false
        }
        .task(id: coachKey) {
            guard tab == .coach else { return }
            guard dataStamp != lastCoachKey else { return }   // unchanged → keep cache
            lastCoachKey = dataStamp
            cachedStreaks = computeStreaks()
        }
    }

    // MARK: - Daily training (exercise of the day)

    /// The latest dictation made TODAY, if any — the attempt for today's exercise.
    /// `allMetrics` is sorted newest-first, so the first match is the most recent.
    private var todaysLatestMetric: SpeechMetric? {
        allMetrics.first { Calendar.current.isDateInToday($0.timestamp) }
    }

    /// Exercise-of-the-day card. Scores today's dictation against today's targets;
    /// «Analyze in detail» opens the existing drill-down (where the style rewrite lives).
    @ViewBuilder
    private var dailyTraining: some View {
        if let cachedExercise {
            DailyTrainingCard(
                exercise: cachedExercise,
                latestMetric: todaysLatestMetric,
                profile: activeStyleProfile,
                onOpenDetail: { selectedMetric = $0 }
            )
        }
    }

    /// Data fingerprint — changes when metrics are added/changed.
    private var dataStamp: String {
        let newest = allMetrics.first?.timestamp.timeIntervalSince1970 ?? 0
        return "\(allMetrics.count)|\(newest)"
    }
    /// Exercise depends on profile + data — NOT period, NOT tab.
    private var exerciseKey: String { "\(activeStyleProfile?.id.uuidString ?? "none")|\(dataStamp)" }
    /// Match-score chart depends on period + profile + data — NOT tab, so switching
    /// sub-tabs no longer recomputes it (this was the main sub-tab-switch lag).
    private var chartsKey: String { "\(period.rawValue)|\(activeStyleProfile?.id.uuidString ?? "none")|\(dataStamp)" }
    /// Heavy per-tab work fires only while that tab is active.
    private var wordsKey: String { tab == .words ? "\(period.rawValue)|\(dataStamp)" : "off" }
    private var coachKey: String { tab == .coach ? dataStamp : "off" }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(SpeechTab.allCases) { t in
                Text(t.displayName).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .pointingHandCursor()
    }

    /// Only the active sub-tab's sections are built — keeps each render light and
    /// avoids the endless scroll. Heavy sections (streaks scan, coach, word tables)
    /// no longer run on the default Overview.
    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .overview: overviewTab
        case .words:    wordsTab
        case .coach:    coachTab
        case .history:  historyTab
        }
    }

    @ViewBuilder
    private var overviewTab: some View {
        dailyTraining
        if filteredMetrics.isEmpty {
            emptyState
        } else {
            aggregatedMetrics
            prosodySection
        }
    }

    @ViewBuilder
    private var wordsTab: some View {
        if filteredMetrics.isEmpty {
            emptyState
        } else {
            SpeechWordsTab(
                fillers: topFillerList,
                anglicisms: topAnglicismList,
                repetitions: topRepetitionList,
                dynamics: fillerDynamics,
                sparklines: fillerSparklines,
                loading: wordsLoading
            )
        }
    }

    @ViewBuilder
    private var coachTab: some View {
        if filteredMetrics.isEmpty {
            emptyState
        } else {
            VoiceProfileSection(metrics: filteredMetrics)
            streaksSection
        }
    }

    @ViewBuilder
    private var historyTab: some View {
        if filteredMetrics.isEmpty {
            emptyState
        } else {
            SpeechHistoryTab(
                metrics: filteredMetrics,
                matchSeries: cachedMatchSeries,
                showMatchChart: activeStyleProfile != nil,
                showTrends: period != .today,
                onSelect: { selectedMetric = $0 }
            )
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    LocalizedText(en: "Speech Analytics", ru: "Аналитика речи")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    LocalizedText(
                        en: "Track your speech patterns and improve over time",
                        ru: "Отслеживай паттерны речи и улучшайся со временем"
                    )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                exportButton
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    /// Экспорт недельного отчёта в Obsidian Vault + настройка папки.
    private var exportButton: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    runExport()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.t(en: "Export week", ru: "Экспорт недели"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.18)))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(L10n.t(
                    en: "Save the weekly speech report to Obsidian Vault",
                    ru: "Сохранить недельный отчёт речи в Obsidian Vault"
                ))

                Button {
                    showExportSettings.toggle()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showExportSettings) {
                    VStack(alignment: .leading, spacing: 8) {
                        LocalizedText(en: "Report folder", ru: "Папка отчётов")
                            .font(.system(size: 11, weight: .semibold))
                        TextField(SpeechVaultExport.defaultFolder, text: $reportFolder)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(width: 320)
                        LocalizedText(
                            en: "File: Speech Week YYYY-Www.md (overwritten on re-export)",
                            ru: "Файл: Speech Week YYYY-Www.md (перезаписывается при повторном экспорте)"
                        )
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
            }

            if let exportFeedback {
                Text(exportFeedback)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        }
    }

    private func runExport() {
        let result = SpeechVaultExport.exportWeek(allMetrics: allMetrics, profile: activeStyleProfile)
        if result.succeeded {
            exportFeedback = L10n.t(en: "Saved to Vault ✓", ru: "Сохранено в Vault ✓")
        } else {
            exportFeedback = result.error
        }
        // Отменяем предыдущий таймер: два экспорта подряд не должны
        // стирать фидбек второго раньше времени
        exportFeedbackTask?.cancel()
        let task = DispatchWorkItem { exportFeedback = nil }
        exportFeedbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    // MARK: - Period selector

    private var periodSelector: some View {
        HStack(spacing: 8) {
            ForEach(SpeechPeriod.allCases) { p in
                Button {
                    period = p
                } label: {
                    Text(p.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(period == p ? Color.accentColor : Color.gray.opacity(0.15))
                        )
                        .foregroundColor(period == p ? .white : .primary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Spacer()
            Text(L10n.sessionsCount(filteredMetrics.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            LocalizedText(
                en: "No dictations in this period yet",
                ru: "В этом периоде ещё нет диктовок"
            )
                .font(.system(size: 15, weight: .semibold))
            LocalizedText(
                en: "Speech metrics are recorded after each dictation ≥ 15 words",
                ru: "Метрики записываются после каждой диктовки ≥ 15 слов"
            )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Aggregated metrics

    private var aggregatedMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            SpeechStatCard(
                title: L10n.t(en: "Fillers", ru: "Паразиты"),
                value: String(format: "%.1f", aggFillerRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 2", ru: "Цель ≤ 2"),
                color: fillerColor(aggFillerRate),
                icon: "text.bubble",
                tip: SpeechMetricTips.fillers,
                delta: delta(fillerRate).map { SpeechCardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Avg sentence", ru: "Длина предложения"),
                value: String(format: "%.0f", aggSentenceLength),
                unit: L10n.t(en: "words", ru: "слов"),
                detail: L10n.t(en: "Target ≤ 18", ru: "Цель ≤ 18"),
                color: sentenceColor(aggSentenceLength),
                icon: "text.alignleft",
                tip: SpeechMetricTips.sentenceLength,
                delta: delta(sentenceLength).map { d in
                    // «Лучше» = ближе к цели активного стиля (для Эриксона длиннее — хорошо)
                    let target = activeStyleProfile?.targetSentenceLength ?? 18
                    let improved = abs(sentenceLength(of: filteredMetrics) - target)
                        < abs(sentenceLength(of: previousMetrics) - target)
                    return SpeechCardDelta(value: d, format: "%.0f", improved: improved)
                }
            )
            SpeechStatCard(
                title: L10n.t(en: "Anglicisms", ru: "Англицизмы"),
                value: String(format: "%.1f", aggAnglicismRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 1", ru: "Цель ≤ 1"),
                color: anglicismColor(aggAnglicismRate),
                icon: "globe",
                tip: SpeechMetricTips.anglicisms,
                delta: delta(anglicismRate).map { SpeechCardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Smoothness", ru: "Гладкость"),
                value: String(format: "%.1f", aggSelfCorrectionRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Self-corrections", ru: "Самоисправления"),
                color: smoothnessColor(aggSelfCorrectionRate),
                icon: "pencil.and.scribble",
                tip: SpeechMetricTips.smoothness,
                delta: delta(selfCorrectionRate).map { SpeechCardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Speed", ru: "Темп"),
                value: String(format: "%.0f", aggWPM),
                unit: "WPM",
                detail: wpmDetail,
                color: .blue,
                icon: "speedometer",
                tip: SpeechMetricTips.wpm,
                delta: delta(wpm).map { SpeechCardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            SpeechStatCard(
                title: L10n.t(en: "Total words", ru: "Всего слов"),
                value: "\(aggWordCount)",
                unit: "",
                detail: L10n.t(en: "in this period", ru: "за период"),
                color: .indigo,
                icon: "text.alignleft",
                tip: SpeechMetricTips.totalWords,
                delta: delta({ Double(wordCount(of: $0)) }).map { SpeechCardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            SpeechStatCard(
                title: L10n.t(en: "EN / RU ratio", ru: "EN / RU"),
                value: String(format: "%.0f%%", aggEnRatio * 100),
                unit: "",
                detail: L10n.t(en: "English chars share", ru: "Доля латинских букв"),
                color: .pink,
                icon: "character.textbox",
                tip: SpeechMetricTips.enRuRatio,
                delta: delta({ enRatio(of: $0) * 100 }).map { SpeechCardDelta(value: $0, format: "%.0f", improved: nil) }
            )

            SpeechStatCard(
                title: L10n.t(en: "Complexity", ru: "Сложность"),
                value: String(format: "%.1f", aggComplexity),
                unit: "",
                detail: L10n.t(en: "Subordinations per sentence", ru: "Подчинения в предложении"),
                color: .teal,
                icon: "arrow.triangle.branch",
                tip: SpeechMetricTips.complexity,
                delta: delta(complexity).map { SpeechCardDelta(value: $0, format: "%.1f", improved: nil) }
            )
        }
    }

    /// Дельта карточки к прошлому периоду.
    /// improved: true → зелёный, false → красный, nil → нейтральная метрика (серый).
    /// Вычисляется на месте вызова — например, длина предложения «улучшилась»,
    /// если приблизилась к цели активного профиля, а не просто упала.
    // MARK: - Streaks

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                LocalizedText(en: "Streaks", ru: "Стрики")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                LocalizedText(
                    en: "(consecutive days on target — all history)",
                    ru: "(дней подряд под целью — по всей истории)"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                InfoTip(message: SpeechMetricTips.streaks, iconSize: .small, iconColor: .secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                streakCard(
                    title: L10n.t(en: "Filler-free", ru: "Без паразитов"),
                    value: fillerStreak,
                    subtitle: L10n.t(en: "≤ 2 / 100 words", ru: "≤ 2 / 100 слов"),
                    color: .orange,
                    icon: "text.bubble"
                )
                streakCard(
                    title: L10n.t(en: "Anglicism-free", ru: "Без англицизмов"),
                    value: anglicismStreak,
                    subtitle: L10n.t(en: "≤ 1 / 100 words", ru: "≤ 1 / 100 слов"),
                    color: .pink,
                    icon: "globe"
                )
                streakCard(
                    title: L10n.t(en: "Short sentences", ru: "Короткие предложения"),
                    value: sentenceStreak,
                    subtitle: L10n.t(en: "≤ 18 words", ru: "≤ 18 слов"),
                    color: .green,
                    icon: "text.alignleft"
                )
            }
        }
    }

    private func streakCard(
        title: String,
        value: Int,
        subtitle: String,
        color: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(color)
                    Text(daysLabel(for: value))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    if value >= 7 {
                        Text("🔥")
                            .font(.system(size: 14))
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Streak calculation

    /// Группирует ВСЕ metrics (не filtered) по дням, считает streak с сегодня назад.
    /// Streak ломается на первом дне с данными где criteria failed.
    /// Дни без данных пропускаются (не ломают streak).
    private func computeStreak(
        passedCheck: (Int /* fillers */, Int /* anglicisms */, Int /* words */, Int /* sentences */) -> Bool
    ) -> Int {
        let cal = Calendar.current
        // Группируем все metrics по дням
        var byDay: [Date: (fillers: Int, anglicisms: Int, words: Int, sentences: Int)] = [:]
        for m in allMetrics {
            let day = cal.startOfDay(for: m.timestamp)
            var d = byDay[day, default: (0, 0, 0, 0)]
            d.fillers += m.fillerCount
            d.anglicisms += m.anglicismCount
            d.words += m.wordCount
            d.sentences += m.sentenceCount
            byDay[day] = d
        }

        guard !byDay.isEmpty else { return 0 }

        // Идём с сегодня назад
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        let earliest = byDay.keys.min() ?? cursor

        while cursor >= earliest {
            if let d = byDay[cursor] {
                if passedCheck(d.fillers, d.anglicisms, d.words, d.sentences) {
                    streak += 1
                } else {
                    break
                }
            }
            // День без данных — пропускаем, не ломаем streak
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? earliest
        }
        return streak
    }

    /// Корректная форма «день/дня/дней» с учётом языка.
    private func daysLabel(for value: Int) -> String {
        if L10n.current == .english {
            return value == 1 ? "day" : "days"
        }
        return L10n.ruPlural(value, one: "день", few: "дня", many: "дней")
    }

    private var fillerStreak: Int { cachedStreaks.filler }
    private var anglicismStreak: Int { cachedStreaks.anglicism }
    private var sentenceStreak: Int { cachedStreaks.sentence }

    /// Computes all three streaks — called from `.task` (Coach tab), not on render.
    private func computeStreaks() -> (filler: Int, anglicism: Int, sentence: Int) {
        let filler = computeStreak { fillers, _, words, _ in
            guard words > 0 else { return false }
            return Double(fillers) / Double(words) * 100 <= 2.0
        }
        let anglicism = computeStreak { _, anglicisms, words, _ in
            guard words > 0 else { return false }
            return Double(anglicisms) / Double(words) * 100 <= 1.0
        }
        let sentence = computeStreak { _, _, words, sentences in
            guard words > 0, sentences > 0 else { return false }
            // Daily aggregate: day words ÷ day sentences (weighted, as on the card).
            return Double(words) / Double(sentences) <= 18.0
        }
        return (filler, anglicism, sentence)
    }

    // MARK: - Filtering

    private var filteredMetrics: [SpeechMetric] {
        guard let start = period.startDate() else { return allMetrics }
        return allMetrics.filter { $0.timestamp >= start }
    }

    /// Метрики предыдущего окна той же длины — для дельт на карточках.
    /// Для «Всё» прошлого окна нет.
    private var previousMetrics: [SpeechMetric] {
        guard let start = period.startDate() else { return [] }
        let days: Int
        switch period {
        case .today: days = 1
        case .week:  days = 7
        case .month: days = 30
        case .all:   return []
        }
        guard let prevStart = Calendar.current.date(byAdding: .day, value: -days, to: start) else { return [] }
        return allMetrics.filter { $0.timestamp >= prevStart && $0.timestamp < start }
    }

    // MARK: - Aggregations
    // Параметризованы по набору метрик: считаются и для текущего, и для прошлого периода.

    // Thin delegates to SpeechAggregates (the aggregation logic lives there now).
    private func wordCount(of ms: [SpeechMetric]) -> Int { SpeechAggregates.wordCount(ms) }
    private func fillerRate(of ms: [SpeechMetric]) -> Double { SpeechAggregates.fillerRate(ms) }
    private func anglicismRate(of ms: [SpeechMetric]) -> Double { SpeechAggregates.anglicismRate(ms) }
    private func selfCorrectionRate(of ms: [SpeechMetric]) -> Double { SpeechAggregates.selfCorrectionRate(ms) }
    private func sentenceLength(of ms: [SpeechMetric]) -> Double { SpeechAggregates.sentenceLength(ms) }
    private func wpm(of ms: [SpeechMetric]) -> Double { SpeechAggregates.wpm(ms) }
    private func enRatio(of ms: [SpeechMetric]) -> Double { SpeechAggregates.enRatio(ms) }
    private func complexity(of ms: [SpeechMetric]) -> Double { SpeechAggregates.complexity(ms) }

    /// Подпись карточки «Темп»: цель активного стиля + направление, либо «средний темп».
    private var wpmDetail: String {
        guard let target = activeStyleProfile?.targetWPM, aggWPM > 0 else {
            return L10n.t(en: "Avg speaking pace", ru: "Средний темп речи")
        }
        let dir = aggWPM < target - 5
            ? L10n.t(en: "speak faster", ru: "быстрее")
            : (aggWPM > target + 5 ? L10n.t(en: "slow down", ru: "медленнее") : L10n.t(en: "on target", ru: "в цели"))
        return L10n.t(
            en: "Target \(Int(target)) · \(dir)",
            ru: "Цель \(Int(target)) · \(dir)"
        )
    }

    private var aggWordCount: Int { wordCount(of: filteredMetrics) }
    private var aggFillerRate: Double { fillerRate(of: filteredMetrics) }
    private var aggAnglicismRate: Double { anglicismRate(of: filteredMetrics) }
    private var aggSelfCorrectionRate: Double { selfCorrectionRate(of: filteredMetrics) }
    private var aggSentenceLength: Double { sentenceLength(of: filteredMetrics) }
    private var aggWPM: Double { wpm(of: filteredMetrics) }
    private var aggEnRatio: Double { enRatio(of: filteredMetrics) }
    private var aggComplexity: Double { complexity(of: filteredMetrics) }

    /// Дельта к прошлому окну, nil если прошлых данных нет.
    private func delta(_ value: (([SpeechMetric]) -> Double)) -> Double? {
        let prev = previousMetrics
        guard !prev.isEmpty else { return nil }
        return value(filteredMetrics) - value(prev)
    }

    /// Aggregate a per-metric word→count dictionary across the period, sorted desc.
    /// Each `extract` access JSON-decodes a stored field, so callers cache the result.
    private func topWords(_ extract: (SpeechMetric) -> [String: Int]) -> [(word: String, count: Int)] {
        SpeechAggregates.topWords(filteredMetrics, extract)
    }

    // MARK: - Daily series for charts

    /// Дневной Match Score по активному профилю — кривая «дохожу до стиля».
    /// Вызывается только из .task при смене ключа кэша — не на каждый рендер.
    private func computeDailyMatchSeries() -> [(date: Date, value: Double)] {
        guard let active = activeStyleProfile else { return [] }
        let cal = Calendar.current
        var buckets: [Date: [SpeechMetric]] = [:]
        for m in filteredMetrics {
            buckets[cal.startOfDay(for: m.timestamp), default: []].append(m)
        }
        return buckets
            .compactMap { day, ms -> (date: Date, value: Double)? in
                guard let result = VoiceProfileMatcher.compute(target: active, metrics: ms) else { return nil }
                return (date: day, value: result.totalScore)
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Prosody (voice)

    /// Period metrics that already have prosody numbers (audio still on disk).
    private var prosodyMetrics: [SpeechMetric] {
        filteredMetrics.filter { $0.prosodyAnalyzed }
    }

    /// Voice/prosody cards — shown only once at least one dictation has been analysed.
    @ViewBuilder
    private var prosodySection: some View {
        if !prosodyMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    LocalizedText(en: "Voice (prosody)", ru: "Голос (просодика)")
                        .font(.system(size: 16, weight: .bold))
                    InfoTip(message: SpeechMetricTips.prosody, iconSize: .small, iconColor: .secondary)
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    SpeechStatCard(
                        title: L10n.t(en: "Expressiveness", ru: "Выразительность"),
                        value: String(format: "%.1f", avgPitchRange),
                        unit: L10n.t(en: "st", ru: "пт"),
                        detail: L10n.t(en: "F0 range", ru: "Разброс тона"),
                        color: .purple,
                        icon: "waveform.path",
                        tip: SpeechMetricTips.expressiveness,
                        delta: nil
                    )
                    SpeechStatCard(
                        title: L10n.t(en: "Pauses", ru: "Паузы"),
                        value: String(format: "%.0f", avgPauseRatio),
                        unit: "%",
                        detail: L10n.t(en: "of speaking time", ru: "от времени речи"),
                        color: .teal,
                        icon: "pause.circle",
                        tip: SpeechMetricTips.pauses,
                        delta: nil
                    )
                    SpeechStatCard(
                        title: L10n.t(en: "Dynamics", ru: "Динамика"),
                        value: String(format: "%.0f", avgLoudnessRange),
                        unit: "dB",
                        detail: L10n.t(en: "loudness spread", ru: "разброс громкости"),
                        color: .mint,
                        icon: "speaker.wave.3",
                        tip: SpeechMetricTips.dynamics,
                        delta: nil
                    )
                }
            }
        }
    }

    private var avgPitchRange: Double { meanOf(prosodyMetrics.map { $0.pitchRangeSemitones }.filter { $0 > 0 }) }
    private var avgPauseRatio: Double { meanOf(prosodyMetrics.map { $0.pauseRatioPercent }) }
    private var avgLoudnessRange: Double { meanOf(prosodyMetrics.map { $0.loudnessRangeDb }.filter { $0 > 0 }) }
    private func meanOf(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

    // MARK: - Color thresholds

    private func fillerColor(_ rate: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if rate <= 2 { return .green }
        if rate <= 4 { return .orange }
        return .red
    }

    private func sentenceColor(_ length: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if length <= 18 { return .green }
        if length <= 25 { return .orange }
        return .red
    }

    private func anglicismColor(_ rate: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if rate <= 1 { return .green }
        if rate <= 3 { return .orange }
        return .red
    }

    /// Гладкость: ≤1 самоисправление/100сл — зелёная, до 3 — оранжевая, выше — красная.
    private func smoothnessColor(_ rate: Double) -> Color {
        if aggWordCount == 0 { return .secondary }
        if rate <= 1 { return .green }
        if rate <= 3 { return .orange }
        return .red
    }
}
}
