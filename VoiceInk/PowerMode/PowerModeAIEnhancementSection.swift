//
//  PowerModeAIEnhancementSection.swift
//  VoiceInk
//
//  "AI Enhancement" section of the Power Mode form: enable toggle, provider/model
//  pickers (with sensible defaults seeded on enable), enhancement prompt and the
//  context-awareness toggle.
//

import SwiftUI

struct PowerModeAIEnhancementSection: View {
    @ObservedObject var form: PowerModeFormModel
    @EnvironmentObject private var aiService: AIService
    @EnvironmentObject private var enhancementService: AIEnhancementService

    var body: some View {
        Section("AI Enhancement") {
            Toggle(tr("AI Enhancement"), isOn: $form.isAIEnhancementEnabled)
                .onChange(of: form.isAIEnhancementEnabled) { _, newValue in
                    if newValue {
                        if form.selectedAIProvider == nil {
                            form.selectedAIProvider = aiService.selectedProvider.rawValue
                        }
                        if form.selectedAIModel == nil {
                            form.selectedAIModel = aiService.currentModel
                        }
                        if form.selectedPromptId == nil {
                            form.selectedPromptId = enhancementService.allPrompts.first?.id
                        }
                    }
                }

            if form.isAIEnhancementEnabled {
                providerPicker
                modelPicker
                promptPicker
                Toggle(tr("Context Awareness"), isOn: $form.useScreenCapture)
            }
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding<AIProvider>(
            get: {
                if let providerName = form.selectedAIProvider,
                   let provider = AIProvider(rawValue: providerName) {
                    return provider
                }
                return aiService.selectedProvider
            },
            set: { newValue in
                form.selectedAIProvider = newValue.rawValue
                form.selectedAIModel = nil
            }
        )
    }

    @ViewBuilder
    private var providerPicker: some View {
        if aiService.connectedProviders.isEmpty {
            LabeledContent(tr("AI Provider")) {
                Text(tr("No providers connected"))
                    .foregroundColor(.secondary)
                    .italic()
            }
        } else {
            Picker("AI Provider", selection: providerBinding) {
                ForEach(aiService.connectedProviders.filter { $0 != .elevenLabs && $0 != .deepgram }, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .onChange(of: form.selectedAIProvider) { _, newValue in
                if let provider = newValue.flatMap({ AIProvider(rawValue: $0) }) {
                    form.selectedAIModel = provider.defaultModel
                }
            }
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        let providerName = form.selectedAIProvider ?? aiService.selectedProvider.rawValue
        if let provider = AIProvider(rawValue: providerName), provider != .custom {
            let models = aiService.availableModels(for: provider)
            if models.isEmpty {
                LabeledContent(tr("AI Model")) {
                    Text(provider == .openRouter ? "No models loaded" : "No models available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                let modelBinding = Binding<String>(
                    get: {
                        if let model = form.selectedAIModel, !model.isEmpty { return model }
                        return aiService.currentModel
                    },
                    set: { form.selectedAIModel = $0 }
                )

                Picker("AI Model", selection: modelBinding) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                if provider == .openRouter {
                    Button(tr("Refresh Models")) {
                        Task { await aiService.fetchOpenRouterModels() }
                    }
                    .help(tr("Refresh models"))
                }
            }
        }
    }

    @ViewBuilder
    private var promptPicker: some View {
        if enhancementService.allPrompts.isEmpty {
            LabeledContent(tr("Enhancement Prompt")) {
                Text(tr("No prompts available"))
                    .foregroundColor(.secondary)
            }
        } else {
            Picker("Enhancement Prompt", selection: $form.selectedPromptId) {
                ForEach(enhancementService.allPrompts) { prompt in
                    Text(prompt.title).tag(prompt.id as UUID?)
                }
            }
        }
    }
}
