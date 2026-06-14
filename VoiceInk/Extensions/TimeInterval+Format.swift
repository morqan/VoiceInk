//
//  TimeInterval+Format.swift
//  VoiceInk
//
//  Shared TimeInterval formatting: `formatTiming()` for durations (ms / s / m) used
//  in history and info panels, and `formattedClock()` for the m:ss player display.
//

import Foundation

extension TimeInterval {
    /// Human duration: "850ms" / "12.5s" / "3m 5s".
    func formatTiming() -> String {
        if self < 1 {
            return String(format: "%.0fms", self * 1000)
        }
        if self < 60 {
            return String(format: "%.1fs", self)
        }
        let minutes = Int(self) / 60
        let seconds = self.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.0fs", minutes, seconds)
    }

    /// Clock display for the audio player: "m:ss".
    func formattedClock() -> String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
