// Translates the course vocabulary into English and Spanish with the on-device
// Apple model (Foundation Models), from the Italian word with its Russian gloss
// as a hint. Output: tools/curation/<LEVEL>.words.json, merged by
// extract_structure.py. Resumable: words already translated are skipped.
//
//   swiftc -parse-as-library tools/translate/translate_words.swift -o /tmp/translate_words
//   /tmp/translate_words A1
import Foundation
import FoundationModels

@Generable struct Pair {
    @Guide(description: "English dictionary translation, 1 to 5 words") var en: String
    @Guide(description: "Spanish dictionary translation, 1 to 5 words") var es: String
}

let instructions = """
    You give short dictionary translations of Italian words and expressions for learners, into English and Spanish.
    Translate the exact Italian form: a conjugated verb stays in that person and tense ("parlo" = "I speak" / "hablo"), \
    an infinitive is "to …" in English and a plain infinitive in Spanish ("parlare" = "to speak" / "hablar"), \
    a plural noun stays plural. Do not add articles that are not in the Italian. \
    The Russian meaning is given only to pick the right sense. Answer with the translations only, no explanations.
    """

func fold(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: "’", with: "'")
        .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it"))
}

func clean(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasSuffix(".") && !t.hasSuffix("...") { t.removeLast() }
    return t.trimmingCharacters(in: CharacterSet(charactersIn: " \"«»“”"))
}

/// Reads "English: pen | Spanish: pluma", "pen | pluma" or markdown variants.
func parsePair(_ raw: String) -> Pair? {
    let text = raw.replacingOccurrences(of: "*", with: "")
    func labeled(_ name: String) -> String? {
        guard let r = text.range(of: name + "[^:\\n]*:\\s*([^|\\n]+)", options: .regularExpression) else { return nil }
        let match = String(text[r])
        return match.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
    }
    if let en = labeled("English"), let es = labeled("Spanish"), !en.isEmpty, !es.isEmpty {
        return Pair(en: en, es: es)
    }
    for line in text.components(separatedBy: "\n") where line.contains("|") {
        let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
           parts[0].lowercased() != "english", !parts[0].allSatisfy({ $0 == "-" }) {
            return Pair(en: parts[0], es: parts[1])
        }
    }
    return nil
}

@main struct Main {
    static func main() async throws {
        let level = CommandLine.arguments.dropFirst().first ?? "A1"
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let content = root.appendingPathComponent("Content/\(level).json")
        let outURL = root.appendingPathComponent("tools/curation/\(level).words.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: content)) as! [String: Any]
        var out = (try? JSONSerialization.jsonObject(with: Data(contentsOf: outURL))) as? [String: Any] ?? [:]
        var words = out["words"] as? [String: [String: String]] ?? [:]
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let lessons = json["lessons"] as! [[String: Any]]
        let all = lessons.flatMap { ($0["vocab"] as! [[String: Any]]) }
        var done = 0, failed = 0
        func save() throws {
            out["_comment"] = "English/Spanish glosses made by the on-device Apple model (translate_words.swift). Fix by hand here if needed."
            out["words"] = words
            let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: outURL)
        }
        for v in all {
            let it = v["it"] as! String, ru = v["ru"] as! String, pos = v["pos"] as? String ?? ""
            let key = fold(it)
            if words[key] != nil { continue }
            var result: Pair?
            for attempt in 0..<2 {
                do {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    result = try await session.respond(
                        to: "Italian (\(pos)): \(it)\nRussian meaning: \(ru)",
                        generating: Pair.self,
                        options: GenerationOptions(temperature: attempt == 0 ? 0 : 0.4)).content
                    break
                } catch {
                    if attempt == 1 { failed += 1; print("FAIL \(it): \(error)") }
                }
            }
            // The relaxed guardrails apply to plain-text answers only: retry as
            // "English | Spanish" text for words the structured request refused.
            if result == nil {
                let session = LanguageModelSession(model: model, instructions: instructions)
                if let text = try? await session.respond(
                    to: "Italian (\(pos)): \(it)\nRussian meaning: \(ru)\nAnswer exactly as: English | Spanish",
                    options: GenerationOptions(temperature: 0)).content {
                    if let pair = parsePair(text) {
                        result = pair
                        failed -= 1
                    }
                }
            }
            if let r = result {
                var es = clean(r.es)
                let en = clean(r.en)
                // The model often writes Spanish infinitives as "a vivir", copying English "to".
                if (it.range(of: "(are|ere|ire|rsi|rre)$", options: .regularExpression) != nil
                    || en.lowercased().hasPrefix("to "))
                    && es.lowercased().hasPrefix("a ")
                    && es.dropFirst(2).range(of: "^\\S+(ar|er|ir|arse|erse|irse)\\b", options: .regularExpression) != nil {
                    es = String(es.dropFirst(2))
                }
                words[key] = ["en": en, "es": es]
                done += 1
                if done % 25 == 0 { try save(); print("\(level): \(words.count)/\(all.count)") }
            }
        }
        try save()
        print("\(level) finished: \(words.count) words, \(failed) failed")
    }
}
