import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Rules written in the app, as a JSON file for tools/import_rules.py:
/// {"exported_at": "...", "rules": {"a1-01": {"<topic>": "<text>"}}}
nonisolated struct RuleExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(notes: [(lessonID: String, topic: String, text: String)], now: Date = .now) throws {
        var rules: [String: [String: String]] = [:]
        for n in notes { rules[n.lessonID, default: [:]][n.topic] = n.text }
        let payload = Payload(exported_at: ISO8601DateFormatter().string(from: now), rules: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        data = try encoder.encode(payload)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    struct Payload: Codable {
        let exported_at: String
        let rules: [String: [String: String]]
    }
}
