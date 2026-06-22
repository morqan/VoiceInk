//
//  VaultSyncSection.swift
//  VoiceInk
//
//  UI for managing Vocabulary synchronization
//  with a markdown file (usually from an Obsidian vault).
//
//  Shown at the bottom of Dictionary Settings. It lets you:
//   - Enable/disable sync
//   - Change the file path (manually or via Browse...)
//   - Run sync manually (Sync Now) without restarting the app
//

import SwiftUI
import SwiftData
import AppKit

struct VaultSyncSection: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(UserDefaults.Keys.vaultSyncEnabled) private var enabled: Bool = true
    @AppStorage(UserDefaults.Keys.vaultDictionaryPath) private var path: String = ""

    @State private var lastResultText: String = ""
    @State private var lastResultIsError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            description
            pathInput
            actions
            if !lastResultText.isEmpty {
                resultLabel
            }
        }
        .padding(20)
        .background(CardBackground(isSelected: false))
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(enabled ? .blue : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(en: "Vault Sync", ru: "Синхрон. с Vault")
                    .font(.headline)
                LocalizedText(
                    en: "Auto-import Vocabulary from a markdown file",
                    ru: "Авто-импорт словаря из markdown-файла"
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var description: some View {
        LocalizedText(
            en: "Reads the «Правильное написание» column from a markdown table on app launch and adds new words to Vocabulary. Designed for Obsidian Vault notes, but works with any markdown file containing such a table.",
            ru: "Читает колонку «Правильное написание» из markdown-таблицы при запуске и добавляет новые слова в Vocabulary. Сделано для заметок Obsidian Vault, но работает с любым markdown-файлом с такой таблицей."
        )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pathInput: some View {
        HStack(spacing: 8) {
            TextField(
                "~/Documents/.../voiceink-dictionary.md",
                text: $path
            )
            .textFieldStyle(.roundedBorder)
            .disabled(!enabled)
            .help(L10n.t(
                en: "Path to a markdown file with a Vocabulary table",
                ru: "Путь к markdown-файлу с таблицей Vocabulary"
            ))

            Button {
                selectFile()
            } label: {
                Label(L10n.t(en: "Browse…", ru: "Выбрать…"), systemImage: "folder")
            }
            .disabled(!enabled)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                runSync()
            } label: {
                Label(L10n.t(en: "Sync Now", ru: "Синхронизировать"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!enabled || path.isEmpty)

            Spacer()
        }
    }

    private var resultLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: lastResultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(lastResultIsError ? .orange : .green)
            Text(lastResultText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Vault Dictionary File"
        panel.message = "Choose a markdown file with a Vocabulary table"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["md", "markdown", "txt"]

        if panel.runModal() == .OK, let url = panel.url {
            // Store the absolute path — UserDefaults likes plain strings
            path = url.path
        }
    }

    private func runSync() {
        let result = VaultDictionarySync.syncFromVault(context: modelContext)
        lastResultText = result.summary
        lastResultIsError = result.error != nil
    }
}
