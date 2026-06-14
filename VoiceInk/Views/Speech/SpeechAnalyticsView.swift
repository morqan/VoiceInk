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
            // Match-series buckets the period by day and runs VoiceProfileMatcher per
            // bucket (scans every text) — heavy at large periods, so run it off-main like
            // the Words tab. Only Sendable values cross the boundary; the @Model profile
            // is re-fetched by id inside the background context.
            let container = modelContext.container
            let profileID = activeStyleProfile?.id
            let start = period.startDate()
            cachedMatchSeries = await Task.detached(priority: .userInitiated) { () -> [(date: Date, value: Double)] in
                guard let profileID else { return [] }
                let ctx = ModelContext(container)
                var pd = FetchDescriptor<VoiceProfileTarget>(predicate: #Predicate { $0.id == profileID })
                pd.fetchLimit = 1
                guard let target = try? ctx.fetch(pd).first else { return [] }
                let all = (try? ctx.fetch(FetchDescriptor<SpeechMetric>())) ?? []
                let metrics = start.map { s in all.filter { $0.timestamp >= s } } ?? all
                let cal = Calendar.current
                var buckets: [Date: [SpeechMetric]] = [:]
                for m in metrics {
                    buckets[cal.startOfDay(for: m.timestamp), default: []].append(m)
                }
                return buckets
                    .compactMap { day, ms -> (date: Date, value: Double)? in
                        guard let result = VoiceProfileMatcher.compute(target: target, metrics: ms) else { return nil }
                        return (date: day, value: result.totalScore)
                    }
                    .sorted { $0.date < $1.date }
            }.value
        }
        // Heavy per-tab scans fire only when that tab is active, once per data/period.
        .task(id: wordsKey) {
            guard tab == .words else { return }
            // Skip recompute when the data hasn't changed since last time (re-entering the
            // tab shouldn't re-crunch identical data).
            let dataKey = "\(period.rawValue)|\(dataStamp)"
            guard dataKey != lastWordsKey else { return }
            // Heavy: scans full history (computeDynamics + writeCache) + JSON-decodes
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
                // Reuse the active list we just computed — refreshCache would re-scan all
                // history a second time for the same result.
                AutoFillerDetector.writeCache(active: dyn.active.map { $0.phrase })
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
            lastWordsKey = dataKey   // only mark done after a successful load
            wordsLoading = false
        }
        .task(id: coachKey) {
            guard tab == .coach else { return }
            guard dataStamp != lastCoachKey else { return }   // unchanged → keep cache
            // Streaks bucket ALL history by day three times — run off-main like the Words
            // tab so entering the Coach tab never hitches.
            let container = modelContext.container
            let streaks = await Task.detached(priority: .userInitiated) { () -> (filler: Int, anglicism: Int, sentence: Int) in
                let ctx = ModelContext(container)
                let all = (try? ctx.fetch(FetchDescriptor<SpeechMetric>())) ?? []
                return SpeechStreaks.compute(all)
            }.value
            guard tab == .coach else { return }
            lastCoachKey = dataStamp
            cachedStreaks = streaks
        }
    }

    // MARK: - Daily training (exercise of the day)

    /// The latest dictation made TODAY, if any — the attempt for today's exercise.
    /// `allMetrics` is sorted newest-first, so the first match is the most recent.
    private var todaysLatestMetric: SpeechMetric? {
        allMetrics.first { Calendar.current.isDateInToday($0.timestamp) }
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
        SpeechOverviewTab(
            metrics: filteredMetrics,
            previousMetrics: previousMetrics,
            exercise: cachedExercise,
            todaysLatest: todaysLatestMetric,
            profile: activeStyleProfile,
            onOpenDetail: { selectedMetric = $0 }
        )
    }

    @ViewBuilder
    private var wordsTab: some View {
        if filteredMetrics.isEmpty {
            SpeechEmptyState()
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
            SpeechEmptyState()
        } else {
            SpeechCoachTab(metrics: filteredMetrics, streaks: cachedStreaks)
        }
    }

    @ViewBuilder
    private var historyTab: some View {
        if filteredMetrics.isEmpty {
            SpeechEmptyState()
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

}
