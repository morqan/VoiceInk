//
//  SpeechEmptyState.swift
//  VoiceInk
//
//  Shared empty-state card for the Speech analytics tabs — shown when the
//  selected period has no dictations yet.
//

import SwiftUI

struct SpeechEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            LocalizedText(
                en: "No dictations in this period yet",
                ru: "В этом периоде ещё нет диктовок"
            )
                .font(.system(size: 15, weight: .semibold))
            LocalizedText(
                en: "Speech metrics are recorded after each dictation ≥ 15 words",
                ru: "Метрики записываются после каждой диктовки ≥ 15 слов"
            )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
