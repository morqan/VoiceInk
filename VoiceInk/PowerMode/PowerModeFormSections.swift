//
//  PowerModeFormSections.swift
//  VoiceInk
//
//  The "Trigger Scenarios" (apps + websites) and "Advanced" (default / auto-send /
//  shortcut) sections of the Power Mode form. The icon/website grids live in
//  PowerModeConfigGrids; the app scan in PowerModeAppScanner.
//

import SwiftUI

struct PowerModeTriggerScenariosSection: View {
    @ObservedObject var form: PowerModeFormModel

    var body: some View {
        Section("Trigger Scenarios") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("Applications"))
                    Spacer()
                    AddIconButton(helpText: "Add application") {
                        form.loadInstalledApps()
                        form.isShowingAppPicker = true
                    }
                    .popover(isPresented: $form.isShowingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(
                            installedApps: form.filteredApps,
                            selectedAppConfigs: $form.selectedAppConfigs,
                            searchText: $form.searchText
                        )
                    }
                }

                if form.selectedAppConfigs.isEmpty {
                    Text(tr("No applications added"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    PowerModeAppGrid(configs: $form.selectedAppConfigs)
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Websites"))

                HStack {
                    TextField("Enter website URL", text: $form.newWebsiteURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { form.addWebsite() }

                    AddIconButton(helpText: "Add website", isDisabled: form.newWebsiteURL.isEmpty) {
                        form.addWebsite()
                    }
                }

                if form.websiteConfigs.isEmpty {
                    Text(tr("No websites added"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    PowerModeWebsiteGrid(configs: $form.websiteConfigs)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct PowerModeAdvancedSection: View {
    @ObservedObject var form: PowerModeFormModel

    var body: some View {
        Section("Advanced") {
            Toggle(isOn: $form.isDefault) {
                HStack(spacing: 6) {
                    Text(tr("Set as default"))
                    InfoTip("Default power mode is used when no specific app or website matches are found.")
                }
            }

            Picker(selection: $form.autoSendKey) {
                ForEach(AutoSendKey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("Auto Send"))
                    InfoTip("Automatically presses a key combination after pasting text. Useful for chat applications or forms that use different send shortcuts.")
                }
            }

            HStack {
                Text(tr("Keyboard Shortcut"))
                InfoTip("Assign a unique keyboard shortcut to instantly activate this Power Mode and start recording.")

                Spacer()

                ShortcutRecorder(action: .powerMode(form.powerModeConfigId))
                    .frame(minHeight: 28)
            }
        }
    }
}
