//
//  LanguagePickerRow.swift
//  VoiceInk
//
//  Drop-down для выбора языка наших добавлений (Auto / English / Русский).
//

import SwiftUI

struct LanguagePickerRow: View {
    @AppStorage(L10n.storageKey) private var rawLang: String = AppLanguage.auto.rawValue

    var body: some View {
        LabeledContent {
            Picker("", selection: $rawLang) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
        } label: {
            LocalizedText(en: "Display language", ru: "Язык отображения")
        }
    }
}
