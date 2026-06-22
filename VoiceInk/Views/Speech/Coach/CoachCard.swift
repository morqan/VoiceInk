//
//  CoachCard.swift
//  VoiceInk
//
//  One coaching card per axis in the "How to reach the style" block: a delta title
//  with the gain badge, a short drill hint, axis-specific chips (markers / fillers),
//  and an expandable technique with formula + examples.
//

import SwiftUI

struct CoachCard: View {
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

    /// Short hint: style-specific for the preset, otherwise generic based on the direction.
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
            // Delta title + gain badge
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

            // Short "what to do" hint
            if let drillText {
                Text(drillText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Axis-specific content
            if breakdown.axis == .markers, !markerUsage.isEmpty {
                markerChips
            }
            if breakdown.axis == .fillers, !topFillers.isEmpty {
                fillerChips
            }

            // Disclosure: style technique with formula and examples
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

            // Formula template
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

            // Examples
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

            // Words specific to this technique — what to add to your speech
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
