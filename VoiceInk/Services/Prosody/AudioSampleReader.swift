//
//  AudioSampleReader.swift
//  VoiceInk
//
//  Reads raw mono Float samples + sample rate from a recording, for prosody DSP
//  (pitch, pauses, loudness). Unlike the Whisper path it does NOT peak-normalize —
//  loudness and voice-activity need the true amplitude envelope.
//

import Foundation
import AVFoundation

enum AudioSampleReader {

    struct Audio {
        let samples: [Float]
        let sampleRate: Double
    }

    /// Cap analysis to the first 5 minutes — bounds memory/CPU for unusually long
    /// recordings; ordinary dictations are far shorter. Prosody over the opening
    /// minutes is representative.
    private static let maxSeconds: Double = 300

    static func read(url: URL) throws -> Audio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return Audio(samples: [], sampleRate: 0) }

        let cap = AVAudioFramePosition(sampleRate * maxSeconds)
        let frameCount = AVAudioFrameCount(min(file.length, cap))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return Audio(samples: [], sampleRate: sampleRate)
        }

        try file.read(into: buffer, frameCount: frameCount)

        guard let channelData = buffer.floatChannelData else {
            return Audio(samples: [], sampleRate: sampleRate)
        }

        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)

        if channels == 1 {
            let mono = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
            return Audio(samples: mono, sampleRate: sampleRate)
        }

        // Downmix to mono by averaging channels.
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += channelData[channel][frame] }
            mono[frame] = sum / Float(channels)
        }
        return Audio(samples: mono, sampleRate: sampleRate)
    }
}
