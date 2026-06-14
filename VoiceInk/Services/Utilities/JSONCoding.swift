//
//  JSONCoding.swift
//  VoiceInk
//
//  Single source of truth for the `[String: Int]` JSON (de)serialization used by the
//  string-backed dictionary fields on SpeechMetric (fillers / anglicisms / repetitions
//  / self-corrections). Previously this logic was copy-pasted across SpeechMetric,
//  SpeechMetricsAnalyzer and SpeechMetricRecalcService.
//

import Foundation

enum JSONCoding {
    // Reused across calls — these dictionary fields are decoded on every access
    // (they aren't stored), so allocating a coder each time is pure waste.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode(_ dict: [String: Int]) -> String {
        guard let data = try? encoder.encode(dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func decode(_ json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let dict = try? decoder.decode([String: Int].self, from: data) else {
            return [:]
        }
        return dict
    }
}
