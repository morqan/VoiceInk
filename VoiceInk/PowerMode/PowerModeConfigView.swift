import SwiftUI

struct PowerModeConfigView: View {
    @StateObject private var form: PowerModeFormModel
    @EnvironmentObject var enhancementService: AIEnhancementService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @FocusState private var isNameFieldFocused: Bool

    init(mode: ConfigurationMode, powerModeManager: PowerModeManager, onDismiss: @escaping () -> Void) {
        _form = StateObject(wrappedValue: PowerModeFormModel(
            mode: mode,
            powerModeManager: powerModeManager,
            onDismiss: onDismiss
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                generalSection
                PowerModeTriggerScenariosSection(form: form)
                PowerModeTranscriptionSection(form: form)
                PowerModeAIEnhancementSection(form: form)
                PowerModeAdvancedSection(form: form)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(NSColor.controlBackgroundColor))
            .confirmationDialog(
                "Delete Power Mode?",
                isPresented: $form.isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if case .edit(let config) = form.mode {
                    Button("Delete", role: .destructive) {
                        form.powerModeManager.removeConfiguration(with: config.id)
                        form.onDismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if case .edit(let config) = form.mode {
                    Text("Are you sure you want to delete the '\(config.name)' power mode? This action cannot be undone.")
                }
            }
            .powerModeValidationAlert(errors: form.validationErrors, isPresented: $form.showValidationAlert)
            .onAppear { onAppearSetup() }
            .onDisappear { form.cleanupUnsavedShortcutIfNeeded() }

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(form.mode.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            Button(action: form.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(tr("Close"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            HStack(spacing: 12) {
                Button {
                    form.isShowingEmojiPicker.toggle()
                } label: {
                    Text(form.selectedEmoji)
                        .font(.system(size: 22))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $form.isShowingEmojiPicker, arrowEdge: .bottom) {
                    EmojiPickerView(
                        selectedEmoji: $form.selectedEmoji,
                        isPresented: $form.isShowingEmojiPicker
                    )
                }

                TextField("Name", text: $form.configName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            HStack {
                if case .edit = form.mode {
                    Button("Delete", role: .destructive) {
                        form.isShowingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(tr("Cancel")) { form.onDismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    form.saveConfiguration()
                } label: {
                    Text(tr("Save Changes"))
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!form.canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Setup

    private func onAppearSetup() {
        // Set AI provider/model after EnvironmentObjects are available
        if case .add = form.mode {
            if form.selectedAIProvider == nil {
                form.selectedAIProvider = aiService.selectedProvider.rawValue
            }
            if form.selectedAIModel == nil || form.selectedAIModel?.isEmpty == true {
                form.selectedAIModel = aiService.currentModel
            }
        }

        if form.isAIEnhancementEnabled && form.selectedPromptId == nil {
            form.selectedPromptId = enhancementService.allPrompts.first?.id
        }

        if let selectedModelName = form.effectiveModelName(transcriptionModelManager),
           let model = transcriptionModelManager.allAvailableModels.first(where: { $0.name == selectedModelName }),
           model.provider != .gemini {
            form.useCompatibleLanguage(for: model)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
}
