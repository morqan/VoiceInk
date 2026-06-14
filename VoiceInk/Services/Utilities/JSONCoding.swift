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
    static func encode(_ dict: [String: Int]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func decode(_ json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return dict
    }
}
