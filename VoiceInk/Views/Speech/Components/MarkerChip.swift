//
//  MarkerChip.swift
//  VoiceInk
//
//  Single marker-phrase chip: shows the phrase, a checkmark if it was used, or a
//  copy-to-pasteboard button if not. Leaf view with its own "copied" state.
//

import SwiftUI
import AppKit

struct MarkerChip: View {
    let usage: VoiceProfileMatcher.MarkerPhraseUsage
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Text(usage.phrase)
                .font(.system(size: 10, weight: .medium))
            if usage.isUsed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            } else {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(usage.phrase, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help(L10n.t(en: "Copy phrase", ru: "Скопировать фразу"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(chipFill)
        )
        .overlay(
            Capsule().strokeBorder(
                usage.isUsed ? Color.clear : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: 1, dash: usage.isUsed ? [] : [3, 2])
            )
        )
        .foregroundStyle(usage.isUsed ? Color.white : Color.secondary)
    }

    private var chipFill: Color {
        usage.isUsed ? Color.indigo : Color.gray.opacity(0.08)
    }
}
