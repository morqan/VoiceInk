//
//  LanguagePickerRow.swift
//  VoiceInk
//
//  Drop-down for choosing the interface language (Auto / English / Русский).
//  On change it shows a "Restart required" alert — without a restart part of the UI
//  won't redraw (Text(tr("X")) is cached for the lifetime of the view).
//

import SwiftUI
import AppKit

struct LanguagePickerRow: View {
    @AppStorage(L10n.storageKey) private var rawLang: String = AppLanguage.auto.rawValue
    @State private var showRestartAlert = false
    @State private var previousLang: String?

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
            .onChange(of: rawLang) { _, newValue in
                if previousLang != nil && previousLang != newValue {
                    showRestartAlert = true
                }
                previousLang = newValue
            }
            .onAppear {
                if previousLang == nil { previousLang = rawLang }
            }
        } label: {
            LocalizedText(en: "Display language", ru: "Язык отображения")
        }
        .alert(
            L10n.t(en: "Restart required", ru: "Нужен перезапуск"),
            isPresented: $showRestartAlert
        ) {
            Button(L10n.t(en: "Restart now", ru: "Перезапустить сейчас")) {
                restartApp()
            }
            Button(L10n.t(en: "Later", ru: "Позже"), role: .cancel) {}
        } message: {
            LocalizedText(
                en: "Most of the interface only updates after restart. Restart VoiceInk now?",
                ru: "Большая часть интерфейса обновится только после перезапуска. Перезапустить VoiceInk сейчас?"
            )
        }
    }

    private func restartApp() {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
