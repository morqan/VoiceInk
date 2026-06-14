//
//  StyleRewritePrompt.swift
//  VoiceInk
//
//  Строит системный промпт для фичи «Как сказал бы [стиль]»: модель переписывает
//  диктовку пользователя в целевом стиле, сохраняя смысл, чтобы он учился на
//  собственном тексте. Промпт собирается из профиля (цели + маркер-фразы) и
//  именованных приёмов из VoiceStyleCoaching.
//

import Foundation

enum StyleRewritePrompt {

    /// Системный промпт для переписывания транскрипта в стиле профиля.
    static func systemPrompt(for profile: VoiceProfileTarget) -> String {
        let name = profile.name
        let markers = profile.markerPhrases.prefix(12).map { "«\($0)»" }.joined(separator: ", ")

        let pace: String
        switch profile.targetWPM {
        case ..<115:   pace = "медленный, размеренный темп"
        case 115..<140: pace = "средний, спокойный темп"
        default:       pace = "энергичный темп"
        }

        let sentence = Int(profile.targetSentenceLength)
        let complexity: String
        switch profile.targetComplexity {
        case ..<1.5:  complexity = "простые рубленые предложения, без придаточных"
        case 1.5..<3: complexity = "умеренная сложность, один оборот на предложение"
        default:      complexity = "длинные многоэтажные предложения с придаточными («который», «когда», «если», «пока», «по мере того как»)"
        }

        // Приёмы стиля из базы тренера (если это пресет)
        var techniques = ""
        if let key = VoiceStyleKey.from(profile: profile) {
            let names = VoiceStyleCoaching.patterns(for: key, axis: .markers)
                + VoiceStyleCoaching.patterns(for: key, axis: .sentenceLength)
                + VoiceStyleCoaching.patterns(for: key, axis: .complexity)
            let lines = names.prefix(5).map { "— \($0.name.text): \($0.formula.text)" }
            if !lines.isEmpty {
                techniques = "\n\nПриёмы стиля, которые стоит применить:\n" + lines.joined(separator: "\n")
            }
        }

        return """
        Ты — мастер-редактор устной речи. Перепиши текст в скобках <TRANSCRIPT> в стиле «\(name)».

        Характеристика стиля: \(profile.summary)
        Целевые параметры:
        — Темп подачи: \(pace).
        — Длина предложений: в среднем около \(sentence) слов; \(complexity).
        — Фирменные фразы стиля, которые нужно естественно вплести: \(markers).\(techniques)

        ЖЁСТКИЕ ПРАВИЛА:
        1. Сохрани СМЫСЛ и все факты оригинала. Ничего не выдумывай и не добавляй новой информации.
        2. Убери слова-паразиты, самоисправления («не X, а Y»), повторы и запинки.
        3. Пиши на русском языке, как живую речь этого стиля — это будет произнесено вслух.
        4. Длина результата примерно как у оригинала (±30%), не раздувай.
        5. Выведи ТОЛЬКО переписанный текст. Без вступлений, без пояснений, без кавычек вокруг, без markdown.
        """
    }
}
