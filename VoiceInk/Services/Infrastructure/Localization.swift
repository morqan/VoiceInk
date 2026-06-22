//
//  Localization.swift
//  VoiceInk
//
//  Simple localization mechanism for two languages (en/ru) with auto-detect.
//
//  Usage in SwiftUI views:
//      LocalizedText(en: "Speech Today", ru: "Сегодняшняя речь")
//
//  Usage in string contexts (placeholder, accessibility hints):
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

/// Localization utility with runtime switching.
enum L10n {

    /// UserDefaults key for the selected language.
    static let storageKey = "AppLanguage"

    /// Effective language — auto is resolved via the system locale.
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.auto.rawValue
        let stored = AppLanguage(rawValue: raw) ?? .auto

        if stored == .auto {
            // If the system language is Russian, use Russian; otherwise English
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ru") ? .russian : .english
        }
        return stored
    }

    /// Returns the string in the current language.
    /// Used for String contexts (placeholder, log messages, accessibility).
    /// For UI text, prefer LocalizedText.
    static func t(en: String, ru: String) -> String {
        return current == .russian ? ru : en
    }
}

/// A SwiftUI Text that automatically redraws when the language changes.
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

// MARK: - Plural forms

extension L10n {
    /// Russian plural forms: 1 сессия / 2 сессии / 5 сессий.
    static func ruPlural(_ n: Int, one: String, few: String, many: String) -> String {
        let mod100 = n % 100
        if (11...14).contains(mod100) { return many }
        switch n % 10 {
        case 1:     return one
        case 2...4: return few
        default:    return many
        }
    }

    /// "N session(s)" / "N сессия/сессии/сессий" with correct pluralization.
    static func sessionsCount(_ n: Int) -> String {
        t(
            en: "\(n) session\(n == 1 ? "" : "s")",
            ru: "\(n) \(ruPlural(n, one: "сессия", few: "сессии", many: "сессий"))"
        )
    }
}

// MARK: - Auto translation for full app

extension L10n {
    /// If the active language is Russian, looks up the en key in the translation table.
    /// If not found, returns the original. In English, always returns the original.
    static func auto(_ en: String) -> String {
        guard current == .russian else { return en }
        return ruTranslations[en] ?? en
    }
}

/// Global shortcut. `Text(tr("Sessions Recorded"))` returns the Russian string
/// if the language is switched to Russian.
func tr(_ en: String) -> String { L10n.auto(en) }

