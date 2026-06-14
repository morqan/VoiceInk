//
//  PowerModeTranscriptionSection.swift
//  VoiceInk
//
//  "Transcription" section of the Power Mode form: model picker, language picker
//  (gated by the model's capabilities) and the transcript-formatting options.
//

import SwiftUI

struct PowerModeTranscriptionSection: View {
    @ObservedObject var form: PowerModeFormModel
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    var body: some View {
        Section("Transcription") {
            modelPicker
            languagePicker
            formattingDisclosure
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        if transcriptionModelManager.usableModels.isEmpty {
            Text(tr("No transcription models available. Please connect to a cloud service or download a local model in the AI Models tab."))
                .foregroundColor(.secondary)
        } else {
            let modelBinding = Binding<String?>(
                get: { form.selectedTranscriptionModelName ?? transcriptionModelManager.currentTranscriptionModel?.name },
                set: { form.selectedTranscriptionModelName = $0 }
            )

            Picker("Model", selection: modelBinding) {
                ForEach(transcriptionModelManager.usableModels, id: \.name) { model in
                    Text(model.displayName).tag(model.name as String?)
                }
            }
            .onChange(of: form.selectedTranscriptionModelName) { _, newModelName in
                if let modelName = newModelName ?? transcriptionModelManager.currentTranscriptionModel?.name,
                   let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == modelName }) {
                    if model.provider == .gemini {
                        form.selectedLanguage = "auto"
                    } else {
                        form.useCompatibleLanguage(for: model)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        if form.languageSelectionDisabled(transcriptionModelManager) {
            LabeledContent(tr("Language")) {
                Text(tr("Autodetected"))
                    .foregroundColor(.secondary)
            }
            .onAppear {
                form.selectedLanguage = "auto"
            }
        } else if let selectedModel = form.effectiveModelName(transcriptionModelManager),
                  let modelInfo = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModel }),
                  modelInfo.isMultilingualModel {
            let languageBinding = Binding<String?>(
                get: { form.selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto" },
                set: { form.selectedLanguage = $0 }
            )

            Picker("Language", selection: languageBinding) {
                ForEach(form.availableLanguages(for: modelInfo).sorted(by: {
                    if $0.key == "auto" { return true }
                    if $1.key == "auto" { return false }
                    return $0.value < $1.value
                }), id: \.key) { key, value in
                    Text(value).tag(key as String?)
                }
            }
        } else if let selectedModel = form.effectiveModelName(transcriptionModelManager),
                  let modelInfo = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModel }),
                  !modelInfo.isMultilingualModel {
            EmptyView()
                .onAppear {
                    if form.selectedLanguage == nil {
                        form.selectedLanguage = "en"
                    }
                }
        }
    }

    @ViewBuilder
    private var formattingDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                form.isTranscriptFormattingExpanded.toggle()
            }
        } label: {
            HStack {
                Text(tr("Transcript Formatting"))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(form.isTranscriptFormattingExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if form.isTranscriptFormattingExpanded {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $form.isTextFormattingEnabled) {
                    HStack(spacing: 4) {
                        Text(tr("Paragraph breaks"))
                        InfoTip("Apply intelligent text formatting to break large block of text into paragraphs.")
                    }
                }

                Picker(selection: $form.punctuationCleanupMode) {
                    ForEach(PunctuationCleanupMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tr("Punctuation"))
                        InfoTip("Keep preserves punctuation as transcribed. Remove all strips punctuation marks from the transcribed text. Remove trailing period only removes a final period from the transcribed text.")
                    }
                }
                .pickerStyle(.menu)

                Toggle(isOn: $form.lowercaseTranscription) {
                    HStack(spacing: 4) {
                        Text(tr("Lowercase output"))
                        InfoTip("Convert transcription output to lowercase.")
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}
