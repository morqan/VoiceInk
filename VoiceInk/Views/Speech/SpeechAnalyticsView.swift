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
        .task(id: matchSeriesCacheKey) {
            cachedExercise = DailyExerciseGenerator.forToday(profile: activeStyleProfile, metrics: allMetrics)
            cachedMatchSeries = computeDailyMatchSeries()
            // Filler dynamics + active-list refresh scan the full history (heavy) — only
            // the Words tab needs them, so this no longer runs on the default Overview.
            if tab == .words {
                let markerExclude = Set(styleProfiles.flatMap { $0.markerPhrases }.map { $0.lowercased() })
                let dyn = AutoFillerDetector.computeDynamics(
                    history: allMetrics,
                    current: filteredMetrics,
                    previous: previousMetrics,
                    excluding: markerExclude
                )
                fillerDynamics = dyn
                fillerSparklines = AutoFillerDetector.dailyRateSeries(
                    phrases: dyn.active.prefix(8).map { $0.phrase },
                    in: filteredMetrics
                )
                AutoFillerDetector.refreshCache(history: allMetrics, excluding: markerExclude)
            }
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

    /// Cache-invalidation key for the heavy `.task`: tab, period, active profile, data.
    /// Tab is included so switching to Words triggers the filler-dynamics computation.
    private var matchSeriesCacheKey: String {
        let newest = allMetrics.first?.timestamp.timeIntervalSince1970 ?? 0
        return "\(tab.rawValue)|\(period.rawValue)|\(activeStyleProfile?.id.uuidString ?? "none")|\(allMetrics.count)|\(newest)"
    }

    // MARK: - Tabs

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(SpeechTab.allCases) { t in
                Text(t.displayName).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
            topFillers
            fillerEvolution
            topAnglicisms
            topRepetitions
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
            if period != .today {
                trendCharts
            }
            recentSessions
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
            statCard(
                title: L10n.t(en: "Fillers", ru: "Паразиты"),
                value: String(format: "%.1f", aggFillerRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 2", ru: "Цель ≤ 2"),
                color: fillerColor(aggFillerRate),
                icon: "text.bubble",
                tip: SpeechMetricTips.fillers,
                delta: delta(fillerRate).map { CardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            statCard(
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
                    return CardDelta(value: d, format: "%.0f", improved: improved)
                }
            )
            statCard(
                title: L10n.t(en: "Anglicisms", ru: "Англицизмы"),
                value: String(format: "%.1f", aggAnglicismRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Target ≤ 1", ru: "Цель ≤ 1"),
                color: anglicismColor(aggAnglicismRate),
                icon: "globe",
                tip: SpeechMetricTips.anglicisms,
                delta: delta(anglicismRate).map { CardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            statCard(
                title: L10n.t(en: "Smoothness", ru: "Гладкость"),
                value: String(format: "%.1f", aggSelfCorrectionRate),
                unit: L10n.t(en: "/100w", ru: "/100сл"),
                detail: L10n.t(en: "Self-corrections", ru: "Самоисправления"),
                color: smoothnessColor(aggSelfCorrectionRate),
                icon: "pencil.and.scribble",
                tip: SpeechMetricTips.smoothness,
                delta: delta(selfCorrectionRate).map { CardDelta(value: $0, format: "%.1f", improved: $0 < 0) }
            )
            statCard(
                title: L10n.t(en: "Speed", ru: "Темп"),
                value: String(format: "%.0f", aggWPM),
                unit: "WPM",
                detail: wpmDetail,
                color: .blue,
                icon: "speedometer",
                tip: SpeechMetricTips.wpm,
                delta: delta(wpm).map { CardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            statCard(
                title: L10n.t(en: "Total words", ru: "Всего слов"),
                value: "\(aggWordCount)",
                unit: "",
                detail: L10n.t(en: "in this period", ru: "за период"),
                color: .indigo,
                icon: "text.alignleft",
                tip: SpeechMetricTips.totalWords,
                delta: delta({ Double(wordCount(of: $0)) }).map { CardDelta(value: $0, format: "%.0f", improved: nil) }
            )
            statCard(
                title: L10n.t(en: "EN / RU ratio", ru: "EN / RU"),
                value: String(format: "%.0f%%", aggEnRatio * 100),
                unit: "",
                detail: L10n.t(en: "English chars share", ru: "Доля латинских букв"),
                color: .pink,
                icon: "character.textbox",
                tip: SpeechMetricTips.enRuRatio,
                delta: delta({ enRatio(of: $0) * 100 }).map { CardDelta(value: $0, format: "%.0f", improved: nil) }
            )

            statCard(
                title: L10n.t(en: "Complexity", ru: "Сложность"),
                value: String(format: "%.1f", aggComplexity),
                unit: "",
                detail: L10n.t(en: "Subordinations per sentence", ru: "Подчинения в предложении"),
                color: .teal,
                icon: "arrow.triangle.branch",
                tip: SpeechMetricTips.complexity,
                delta: delta(complexity).map { CardDelta(value: $0, format: "%.1f", improved: nil) }
            )
        }
    }

    /// Дельта карточки к прошлому периоду.
    /// improved: true → зелёный, false → красный, nil → нейтральная метрика (серый).
    /// Вычисляется на месте вызова — например, длина предложения «улучшилась»,
    /// если приблизилась к цели активного профиля, а не просто упала.
    struct CardDelta {
        let value: Double
        let format: String
        let improved: Bool?
    }

    private func statCard(
        title: String,
        value: String,
        unit: String,
        detail: String,
        color: Color,
        icon: String,
        tip: String? = nil,
        delta: CardDelta? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 26, height: 26)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let tip {
                    Spacer(minLength: 0)
                    InfoTip(message: tip, iconSize: .small, iconColor: .secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                if let delta {
                    deltaBadge(delta)
                }
            }

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    @ViewBuilder
    private func deltaBadge(_ delta: CardDelta) -> some View {
        let formatted = String(format: delta.format, abs(delta.value))
        // «↑0» со стрелкой и цветом вводит в заблуждение — нулевую дельту не показываем
        if (Double(formatted) ?? 0) != 0 {
            HStack(spacing: 1) {
                Image(systemName: delta.value >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text(formatted)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundColor(delta.improved.map { $0 ? Color.green : .red } ?? .secondary)
            .help(L10n.t(
                en: "vs previous period of the same length",
                ru: "к предыдущему периоду той же длины"
            ))
        }
    }

    // MARK: - Charts (Stage 4)

    private var trendCharts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Trends", ru: "Тренды")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.trends, iconSize: .small, iconColor: .secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                chartCard(
                    title: "WPM",
                    series: dailyWPMSeries,
                    color: .blue,
                    yAxisLabel: "WPM"
                )
                chartCard(
                    title: L10n.t(en: "Fillers / 100 words", ru: "Паразиты / 100 слов"),
                    series: dailyFillerRateSeries,
                    color: .orange,
                    yAxisLabel: "rate",
                    targetLine: 2
                )
            }

            // Динамика совпадения с активным стилем — главный мотиватор тренера
            if activeStyleProfile != nil {
                chartCard(
                    title: L10n.t(en: "Match Score (style)", ru: "Match Score (стиль)"),
                    series: cachedMatchSeries,
                    color: .indigo,
                    yAxisLabel: "score",
                    yDomain: 0...100
                )
            }
        }
    }

    private func chartCard(
        title: String,
        series: [(date: Date, value: Double)],
        color: Color,
        yAxisLabel: String,
        targetLine: Double? = nil,
        yDomain: ClosedRange<Double>? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            if series.isEmpty {
                LocalizedText(en: "Not enough data", ru: "Недостаточно данных")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    if let targetLine {
                        RuleMark(y: .value("Target", targetLine))
                            .foregroundStyle(.green.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(series, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(yAxisLabel, point.value)
                        )
                        .foregroundStyle(color)
                    }
                }
                .frame(height: 120)
                .modifier(OptionalYDomain(domain: yDomain))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, series.count / 5))) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Top fillers

    private var topFillers: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Top fillers", ru: "Топ паразитов")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.topFillers, iconSize: .small, iconColor: .secondary)
            }

            if topFillerList.isEmpty {
                LocalizedText(en: "No fillers detected — well done!", ru: "Паразитов нет — молодец!")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(topFillerList.prefix(10), id: \.word) { item in
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

    // MARK: - Filler evolution (авто-детектор паразитов)

    @ViewBuilder
    private var fillerEvolution: some View {
        // Панель показываем, если хватило истории (active/observing есть);
        // блок изменений ниже гейтится отдельно по enoughData (два окна).
        if let dyn = fillerDynamics, dyn.hasHistory, !dyn.active.isEmpty || !dyn.observing.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 2) {
                    LocalizedText(en: "Filler evolution", ru: "Эволюция паразитов")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    LocalizedText(en: "(auto-detected)", ru: "(определяется автоматически)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    InfoTip(message: SpeechMetricTips.fillerEvolution, iconSize: .small, iconColor: .secondary)
                }

                // Изменения: появился / ушёл / вырос / упал
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

                // Активные паразиты с частотой и спарклайном
                if !dyn.active.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(dyn.active.prefix(8)) { entry in
                            fillerActiveRow(entry)
                        }
                    }
                }

                // Под наблюдением
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
            // Спарклайн по дням периода (из кэша, посчитан в .task)
            let series = fillerSparklines[entry.phrase] ?? []
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

    /// Строки изменений: (текст, иконка, цвет).
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

    private var topAnglicisms: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Top anglicisms", ru: "Топ англицизмов")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.topAnglicisms, iconSize: .small, iconColor: .secondary)
            }

            if topAnglicismList.isEmpty {
                LocalizedText(en: "No anglicisms detected", ru: "Англицизмов не обнаружено")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(topAnglicismList.prefix(10), id: \.word) { item in
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

    private var fillerStreak: Int {
        computeStreak { fillers, _, words, _ in
            guard words > 0 else { return false }
            return Double(fillers) / Double(words) * 100 <= 2.0
        }
    }

    private var anglicismStreak: Int {
        computeStreak { _, anglicisms, words, _ in
            guard words > 0 else { return false }
            return Double(anglicisms) / Double(words) * 100 <= 1.0
        }
    }

    private var sentenceStreak: Int {
        computeStreak { _, _, words, sentences in
            guard words > 0, sentences > 0 else { return false }
            // Дневной агрегат: слова дня ÷ предложения дня (взвешенно, как в карточке)
            return Double(words) / Double(sentences) <= 18.0
        }
    }

    // MARK: - Top repetitions

    private var topRepetitions: some View {
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

            if topRepetitionList.isEmpty {
                LocalizedText(en: "No word over-repetition detected", ru: "Повторов не обнаружено")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(topRepetitionList.prefix(10), id: \.word) { item in
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

    // MARK: - Recent sessions

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                LocalizedText(en: "Recent sessions", ru: "Недавние сессии")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                InfoTip(message: SpeechMetricTips.recentSessions, iconSize: .small, iconColor: .secondary)
            }

            VStack(spacing: 6) {
                ForEach(filteredMetrics.prefix(15)) { metric in
                    Button {
                        selectedMetric = metric
                    } label: {
                        sessionRow(metric)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t(en: "Open dictation breakdown", ru: "Открыть разбор диктовки"))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .sheet(item: $selectedMetric) { metric in
            SpeechSessionDetailView(metric: metric, profile: activeStyleProfile)
        }
    }

    private func sessionRow(_ metric: SpeechMetric) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.text.prefix(80) + (metric.text.count > 80 ? "…" : ""))
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(metric.timestamp, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                metricBadge(
                    "\(metric.wordCount)w",
                    color: .secondary,
                    help: L10n.t(en: "Words in this dictation", ru: "Слов в диктовке")
                )
                metricBadge(
                    String(format: "%.0f wpm", metric.wpm),
                    color: .blue,
                    help: L10n.t(en: "Pace, words per minute", ru: "Темп, слов в минуту")
                )
                if metric.fillerCount > 0 {
                    metricBadge(
                        "\(metric.fillerCount)f",
                        color: .orange,
                        help: L10n.t(en: "Filler words found", ru: "Найдено слов-паразитов")
                    )
                }
                if metric.anglicismCount > 0 {
                    metricBadge(
                        "\(metric.anglicismCount)en",
                        color: .pink,
                        help: L10n.t(en: "Anglicisms found", ru: "Найдено англицизмов")
                    )
                }
                if metric.repetitionCount > 0 {
                    metricBadge(
                        "\(metric.repetitionCount)rep",
                        color: .purple,
                        help: L10n.t(en: "Words repeated ≥ 5 times", ru: "Слов с повторами ≥ 5 раз")
                    )
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metricBadge(_ text: String, color: Color, help: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .foregroundColor(color)
            .help(help)
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

    private func wordCount(of ms: [SpeechMetric]) -> Int {
        ms.reduce(0) { $0 + $1.wordCount }
    }

    private func fillerRate(of ms: [SpeechMetric]) -> Double {
        let words = wordCount(of: ms)
        guard words > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.fillerCount }) / Double(words) * 100
    }

    private func anglicismRate(of ms: [SpeechMetric]) -> Double {
        let words = wordCount(of: ms)
        guard words > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.anglicismCount }) / Double(words) * 100
    }

    /// Самоисправления на 100 слов (обратная мера гладкости) — pooled по словам.
    private func selfCorrectionRate(of ms: [SpeechMetric]) -> Double {
        let words = wordCount(of: ms)
        guard words > 0 else { return 0 }
        return Double(ms.reduce(0) { $0 + $1.selfCorrectionCount }) / Double(words) * 100
    }

    private func sentenceLength(of ms: [SpeechMetric]) -> Double {
        let sentences = ms.reduce(0) { $0 + $1.sentenceCount }
        guard sentences > 0 else { return 0 }
        return Double(wordCount(of: ms)) / Double(sentences)
    }

    /// WPM — pooled: все слова ÷ суммарное время записей (вместо невзвешенного
    /// среднего по сессиям, где 16-словная реплика весила как 10-минутная диктовка).
    private func wpm(of ms: [SpeechMetric]) -> Double {
        let timed = ms.filter { $0.durationSeconds > 0 && $0.wordCount > 0 }
        let minutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        guard minutes > 0 else { return 0 }
        return Double(timed.reduce(0) { $0 + $1.wordCount }) / minutes
    }

    /// EN/RU — взвешенно по словам сессий (длинная сессия весит больше короткой).
    private func enRatio(of ms: [SpeechMetric]) -> Double {
        let words = wordCount(of: ms)
        guard words > 0 else { return 0 }
        return ms.reduce(0.0) { $0 + $1.enRuRatio * Double($1.wordCount) } / Double(words)
    }

    /// Сложность — взвешенно по словам, включая нулевые сессии
    /// (исключение нулей смещало среднее вверх).
    private func complexity(of ms: [SpeechMetric]) -> Double {
        let words = wordCount(of: ms)
        guard words > 0 else { return 0 }
        return ms.reduce(0.0) { $0 + $1.avgSentenceComplexity * Double($1.wordCount) } / Double(words)
    }

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

    private var topFillerList: [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in filteredMetrics {
            for (word, count) in metric.fillersByWord {
                totals[word, default: 0] += count
            }
        }
        return totals.map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var topAnglicismList: [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in filteredMetrics {
            for (word, count) in metric.anglicismsByWord {
                totals[word, default: 0] += count
            }
        }
        return totals.map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var topRepetitionList: [(word: String, count: Int)] {
        var totals: [String: Int] = [:]
        for metric in filteredMetrics {
            for (word, count) in metric.repetitionsByWord {
                totals[word, default: 0] += count
            }
        }
        return totals.map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Daily series for charts

    /// Дневной WPM — pooled: слова дня ÷ время записей дня.
    private var dailyWPMSeries: [(date: Date, value: Double)] {
        let cal = Calendar.current
        var buckets: [Date: (words: Int, seconds: Double)] = [:]
        for m in filteredMetrics where m.durationSeconds > 0 && m.wordCount > 0 {
            let day = cal.startOfDay(for: m.timestamp)
            let prev = buckets[day, default: (0, 0)]
            buckets[day] = (prev.words + m.wordCount, prev.seconds + m.durationSeconds)
        }
        return buckets
            .compactMap { day, t -> (date: Date, value: Double)? in
                guard t.seconds > 0 else { return nil }
                return (date: day, value: Double(t.words) / (t.seconds / 60.0))
            }
            .sorted { $0.date < $1.date }
    }

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

    /// Daily filler rate (per 100 words) с weighted average.
    private var dailyFillerRateSeries: [(date: Date, value: Double)] {
        let cal = Calendar.current
        var buckets: [Date: (fillers: Int, words: Int)] = [:]
        for m in filteredMetrics {
            let day = cal.startOfDay(for: m.timestamp)
            let prev = buckets[day, default: (0, 0)]
            buckets[day] = (prev.fillers + m.fillerCount, prev.words + m.wordCount)
        }
        return buckets
            .map { day, t -> (Date, Double) in
                let rate = t.words > 0 ? Double(t.fillers) / Double(t.words) * 100 : 0
                return (day, rate)
            }
            .map { (date: $0.0, value: $0.1) }
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
                    statCard(
                        title: L10n.t(en: "Expressiveness", ru: "Выразительность"),
                        value: String(format: "%.1f", avgPitchRange),
                        unit: L10n.t(en: "st", ru: "пт"),
                        detail: L10n.t(en: "F0 range", ru: "Разброс тона"),
                        color: .purple,
                        icon: "waveform.path",
                        tip: SpeechMetricTips.expressiveness,
                        delta: nil
                    )
                    statCard(
                        title: L10n.t(en: "Pauses", ru: "Паузы"),
                        value: String(format: "%.0f", avgPauseRatio),
                        unit: "%",
                        detail: L10n.t(en: "of speaking time", ru: "от времени речи"),
                        color: .teal,
                        icon: "pause.circle",
                        tip: SpeechMetricTips.pauses,
                        delta: nil
                    )
                    statCard(
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

/// Опциональный фиксированный домен оси Y (для Match Score 0–100).
private struct OptionalYDomain: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain {
            content.chartYScale(domain: domain)
        } else {
            content
        }
    }
}
