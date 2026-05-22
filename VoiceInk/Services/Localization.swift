//
//  Localization.swift
//  VoiceInk
//
//  Простой механизм локализации для двух языков (en/ru) с auto-detect.
//
//  Использование в SwiftUI views:
//      LocalizedText(en: "Speech Today", ru: "Сегодняшняя речь")
//
//  Использование в строковых контекстах (placeholder, accessibility hints):
//      L10n.t(en: "Browse…", ru: "Выбрать…")
//

import SwiftUI
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:     return "Auto / Авто"
        case .english:  return "English"
        case .russian:  return "Русский"
        }
    }
}

/// Утилита для локализации с runtime-переключением.
enum L10n {

    /// Ключ в UserDefaults для выбранного языка.
    static let storageKey = "AppLanguage"

    /// Эффективный язык — auto разрешается через системную локаль.
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.auto.rawValue
        let stored = AppLanguage(rawValue: raw) ?? .auto

        if stored == .auto {
            // Если системный язык — русский, используем русский, иначе английский
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ru") ? .russian : .english
        }
        return stored
    }

    /// Возвращает строку на текущем языке.
    /// Используется для String-контекстов (placeholder, log messages, accessibility).
    /// Для UI текста предпочитай LocalizedText.
    static func t(en: String, ru: String) -> String {
        return current == .russian ? ru : en
    }
}

/// SwiftUI Text который автоматически перерисовывается при смене языка.
struct LocalizedText: View {
    let en: String
    let ru: String

    @AppStorage(L10n.storageKey) private var rawLang: String = AppLanguage.auto.rawValue

    var body: some View {
        Text(currentString)
    }

    private var currentString: String {
        let stored = AppLanguage(rawValue: rawLang) ?? .auto
        if stored == .auto {
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ru") ? ru : en
        }
        return stored == .russian ? ru : en
    }
}

// MARK: - Auto translation for full app

extension L10n {
    /// Если активный язык — русский, ищет en-ключ в таблице переводов.
    /// Не нашёл — возвращает оригинал. На английском — всегда оригинал.
    static func auto(_ en: String) -> String {
        guard current == .russian else { return en }
        return ruTranslations[en] ?? en
    }
}

/// Глобальный shortcut. `Text(tr("Sessions Recorded"))` вернёт русскую строку
/// если язык переключён на русский.
func tr(_ en: String) -> String { L10n.auto(en) }

