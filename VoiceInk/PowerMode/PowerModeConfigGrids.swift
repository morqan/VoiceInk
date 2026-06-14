//
//  PowerModeConfigGrids.swift
//  VoiceInk
//
//  The selected-apps and selected-websites grids for the Power Mode config form.
//  Each owns just its own list binding (display + remove); the add buttons stay in
//  the parent form.
//

import SwiftUI
import AppKit

/// Grid of app icons chosen as triggers, with a remove badge per icon.
struct PowerModeAppGrid: View {
    @Binding var configs: [AppConfig]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 10)], spacing: 10) {
            ForEach(configs) { appConfig in
                ZStack(alignment: .topTrailing) {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appConfig.bundleIdentifier) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 26, height: 26)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                    }

                    Button {
                        configs.removeAll(where: { $0.id == appConfig.id })
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Grid of website-trigger chips, with a remove button per chip.
struct PowerModeWebsiteGrid: View {
    @Binding var configs: [URLConfig]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
            ForEach(configs) { urlConfig in
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text(urlConfig.url)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        configs.removeAll(where: { $0.id == urlConfig.id })
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
        }
        .padding(.vertical, 2)
    }
}
