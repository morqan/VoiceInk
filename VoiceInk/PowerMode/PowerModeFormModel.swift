//
//  PowerModeFormModel.swift
//  VoiceInk
//
//  State + logic for the Power Mode configuration form. Holds every field, the
//  add/edit seeding, and the save/validate/build-config logic so the form view and
//  its sections stay thin. Manager-dependent helpers take the manager as a parameter
//  (it lives in the SwiftUI environment, not here).
//

import SwiftUI
import AppKit

@MainActor
final class PowerModeFormModel: ObservableObject {
    let mode: ConfigurationMode
    let powerModeManager: PowerModeManager
    let onDismiss: () -> Void

    @Published var configName: String
    @Published var selectedEmoji: String
    @Published var isShowingEmojiPicker = false
    @Published var isShowingAppPicker = false
    @Published var isAIEnhancementEnabled: Bool
    @Published var selectedPromptId: UUID?
    @Published var selectedTranscriptionModelName: String?
    @Published var selectedLanguage: String?
    @Published var isTextFormattingEnabled: Bool
    @Published var punctuationCleanupMode: PunctuationCleanupMode
    @Published var lowercaseTranscription: Bool
    @Published var installedApps: [PowerModeAppScanner.InstalledApp] = []
    @Published var searchText = ""
    @Published var validationErrors: [PowerModeValidationError] = []
    @Published var showValidationAlert = false
    @Published var selectedAIProvider: String?
    @Published var selectedAIModel: String?
    @Published var selectedAppConfigs: [AppConfig]
    @Published var websiteConfigs: [URLConfig]
    @Published var newWebsiteURL: String = ""
    @Published var useScreenCapture: Bool
    @Published var autoSendKey: AutoSendKey
    @Published var isDefault: Bool
    @Published var isShowingDeleteConfirmation = false
    @Published var powerModeConfigId: UUID
    @Published var isTranscriptFormattingExpanded: Bool
    @Published var didSaveConfiguration = false

    init(mode: ConfigurationMode, powerModeManager: PowerModeManager, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.powerModeManager = powerModeManager
        self.onDismiss = onDismiss

        switch mode {
        case .add:
            powerModeConfigId = UUID()
            isAIEnhancementEnabled = false
            selectedPromptId = nil
            selectedTranscriptionModelName = nil
            selectedLanguage = nil
            isTextFormattingEnabled = false
            punctuationCleanupMode = .keep
            lowercaseTranscription = false
            configName = ""
            selectedEmoji = "✏️"
            selectedAppConfigs = []
            websiteConfigs = []
            useScreenCapture = false
            autoSendKey = .none
            isDefault = false
            // Use UserDefaults directly since EnvironmentObjects aren't available here
            selectedAIProvider = UserDefaults.standard.string(forKey: "selectedAIProvider")
            selectedAIModel = nil
            isTranscriptFormattingExpanded = false
        case .edit(let config):
            // Fetch latest version in case config was modified elsewhere
            let latestConfig = powerModeManager.getConfiguration(with: config.id) ?? config
            powerModeConfigId = latestConfig.id
            isAIEnhancementEnabled = latestConfig.isAIEnhancementEnabled
            selectedPromptId = latestConfig.selectedPrompt.flatMap { UUID(uuidString: $0) }
            selectedTranscriptionModelName = latestConfig.selectedTranscriptionModelName
            selectedLanguage = latestConfig.selectedLanguage
            isTextFormattingEnabled = latestConfig.isTextFormattingEnabled
            punctuationCleanupMode = latestConfig.punctuationCleanupMode
            lowercaseTranscription = latestConfig.lowercaseTranscription
            configName = latestConfig.name
            selectedEmoji = latestConfig.emoji
            selectedAppConfigs = latestConfig.appConfigs ?? []
            websiteConfigs = latestConfig.urlConfigs ?? []
            useScreenCapture = latestConfig.useScreenCapture
            autoSendKey = latestConfig.autoSendKey
            isDefault = latestConfig.isDefault
            selectedAIProvider = latestConfig.selectedAIProvider
            selectedAIModel = latestConfig.selectedAIModel
            isTranscriptFormattingExpanded = latestConfig.isTextFormattingEnabled || latestConfig.punctuationCleanupMode != .keep || latestConfig.lowercaseTranscription
        }
    }

    // MARK: - Derived

    var filteredApps: [PowerModeAppScanner.InstalledApp] {
        if searchText.isEmpty { return installedApps }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var canSave: Bool { !configName.isEmpty }

    /// Currently effective model: explicit choice, else the app-wide current model.
    func effectiveModelName(_ manager: TranscriptionModelManager) -> String? {
        selectedTranscriptionModelName ?? manager.currentTranscriptionModel?.name
    }

    func languageSelectionDisabled(_ manager: TranscriptionModelManager) -> Bool {
        guard let selectedModelName = effectiveModelName(manager),
              let model = manager.allAvailableModels.first(where: { $0.name == selectedModelName })
        else { return false }
        return model.provider == .gemini
    }

    func availableLanguages(for model: any TranscriptionModel) -> [String: String] {
        TranscriptionLanguageSupport.languages(for: model)
    }

    func useCompatibleLanguage(for model: any TranscriptionModel) {
        selectedLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(
            selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage"),
            for: model
        )
    }

    // MARK: - Actions

    func addWebsite() {
        guard !newWebsiteURL.isEmpty else { return }
        let cleanedURL = powerModeManager.cleanURL(newWebsiteURL)
        websiteConfigs.append(URLConfig(url: cleanedURL))
        newWebsiteURL = ""
    }

    func loadInstalledApps() {
        installedApps = PowerModeAppScanner.scan()
    }

    func getConfigForForm() -> PowerModeConfig {
        switch mode {
        case .add:
            return PowerModeConfig(
                id: powerModeConfigId,
                name: configName,
                emoji: selectedEmoji,
                appConfigs: selectedAppConfigs.isEmpty ? nil : selectedAppConfigs,
                urlConfigs: websiteConfigs.isEmpty ? nil : websiteConfigs,
                isAIEnhancementEnabled: isAIEnhancementEnabled,
                selectedPrompt: selectedPromptId?.uuidString,
                selectedTranscriptionModelName: selectedTranscriptionModelName,
                selectedLanguage: selectedLanguage,
                useScreenCapture: useScreenCapture,
                isTextFormattingEnabled: isTextFormattingEnabled,
                punctuationCleanupMode: punctuationCleanupMode,
                lowercaseTranscription: lowercaseTranscription,
                selectedAIProvider: selectedAIProvider,
                selectedAIModel: selectedAIModel,
                autoSendKey: autoSendKey,
                isDefault: isDefault
            )
        case .edit(let config):
            var updatedConfig = config
            updatedConfig.name = configName
            updatedConfig.emoji = selectedEmoji
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            updatedConfig.selectedTranscriptionModelName = selectedTranscriptionModelName
            updatedConfig.selectedLanguage = selectedLanguage
            updatedConfig.isTextFormattingEnabled = isTextFormattingEnabled
            updatedConfig.punctuationCleanupMode = punctuationCleanupMode
            updatedConfig.lowercaseTranscription = lowercaseTranscription
            updatedConfig.appConfigs = selectedAppConfigs.isEmpty ? nil : selectedAppConfigs
            updatedConfig.urlConfigs = websiteConfigs.isEmpty ? nil : websiteConfigs
            updatedConfig.useScreenCapture = useScreenCapture
            updatedConfig.autoSendKey = autoSendKey
            updatedConfig.selectedAIProvider = selectedAIProvider
            updatedConfig.selectedAIModel = selectedAIModel
            updatedConfig.isDefault = isDefault
            return updatedConfig
        }
    }

    func saveConfiguration() {
        let config = getConfigForForm()
        let validator = PowerModeValidator(powerModeManager: powerModeManager)
        validationErrors = validator.validateForSave(config: config, mode: mode)

        if !validationErrors.isEmpty {
            showValidationAlert = true
            return
        }

        if isDefault {
            powerModeManager.setAsDefault(configId: config.id, skipSave: true)
        }

        switch mode {
        case .add:
            powerModeManager.addConfiguration(config)
        case .edit:
            powerModeManager.updateConfiguration(config)
        }

        didSaveConfiguration = true
        onDismiss()
    }

    func cleanupUnsavedShortcutIfNeeded() {
        guard case .add = mode, !didSaveConfiguration else {
            return
        }
        ShortcutStore.removeShortcutStorage(for: .powerMode(powerModeConfigId))
    }
}
