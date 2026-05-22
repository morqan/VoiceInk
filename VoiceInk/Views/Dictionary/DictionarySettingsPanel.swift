import SwiftUI

struct DictionarySettingsPanel: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(tr("Dictionary Settings"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
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
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )

            // Content
            Form {
                Section {
                    LabeledContent(tr("Quick Add to Dictionary")) {
                        ShortcutRecorder(action: .quickAddToDictionary)
                            .controlSize(.small)
                    }
                } header: {
                    Text(tr("Shortcuts"))
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
