// Translates missing English and Spanish glosses in Content/<LEVEL>.json
// with the on-device Apple model (Foundation Models), from the Italian word
// with its Russian gloss as a hint. Resumable: words that already have both
// `en` and `es` are skipped.
//
//   swiftc -parse-as-library tools/translate/translate_words.swift -o /tmp/translate_words
//   /tmp/translate_words A1
import Foundation
import FoundationModels

@Generable struct Pair {
    @Guide(description: "English dictionary translation, 1 to 5 words") var en: String
    @Guide(description: "Spanish dictionary translation, 1 to 5 words") var es: String
}

struct ContentFile: Codable {
    var level: String
    var lessons: [Lesson]

    struct Lesson: Codable {
        var id: String
        var source: Source?
        var title: String
        var grammar: [Grammar]
        var vocab: [Vocab]
        var patterns: [String]
    }
    struct Source: Codable {
        var part: String
        var lesson: Int
    }
    struct Grammar: Codable {
        var topic: String
        var rule_ru: String
        var topic_en: String?
        var topic_es: String?
        var rule_en: String?
        var rule_es: String?
    }
    struct Vocab: Codable {
        var it: String
        var ru: String
        var pos: String
        var gender: String?
        var number: String?
        var stress: String?
        var form_of: String?
        var new: Bool?
        var en: String?
        var es: String?
    }
}

let instructions = """
    You give short dictionary translations of Italian words and expressions for learners, into English and Spanish.
    Translate the exact Italian form: a conjugated verb stays in that person and tense ("parlo" = "I speak" / "hablo"), \
    an infinitive is "to …" in English and a plain infinitive in Spanish ("parlare" = "to speak" / "hablar"), \
    a plural noun stays plural. Do not add articles that are not in the Italian. \
    The Russian meaning is given only to pick the right sense. Answer with the translations only, no explanations.
    """

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
        let contentURL = root.appendingPathComponent("Content/\(level).json")
        var file = try JSONDecoder().decode(ContentFile.self, from: Data(contentsOf: contentURL))
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        func save() throws {
            let data = try encoder.encode(file) + Data("\n".utf8)
            try data.write(to: contentURL)
        }
        var done = 0, failed = 0
        for li in file.lessons.indices {
            for vi in file.lessons[li].vocab.indices {
                let item = file.lessons[li].vocab[vi]
                if !(item.en ?? "").isEmpty, !(item.es ?? "").isEmpty { continue }
                var result: Pair?
                for attempt in 0..<2 {
                    do {
                        let session = LanguageModelSession(model: model, instructions: instructions)
                        result = try await session.respond(
                            to: "Italian (\(item.pos)): \(item.it)\nRussian meaning: \(item.ru)",
                            generating: Pair.self,
                            options: GenerationOptions(temperature: attempt == 0 ? 0 : 0.4)).content
                        break
                    } catch {
                        if attempt == 1 { failed += 1; print("FAIL \(item.it): \(error)") }
                    }
                }
                // The relaxed guardrails apply to plain-text answers only: retry as
                // "English | Spanish" text for words the structured request refused.
                if result == nil {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    if let text = try? await session.respond(
                        to: "Italian (\(item.pos)): \(item.it)\nRussian meaning: \(item.ru)\nAnswer exactly as: English | Spanish",
                        options: GenerationOptions(temperature: 0)).content,
                       let pair = parsePair(text) {
                        result = pair
                        failed -= 1
                    }
                }
                if let r = result {
                    var es = clean(r.es)
                    let en = clean(r.en)
                    // The model often writes Spanish infinitives as "a vivir", copying English "to".
                    if (item.it.range(of: "(are|ere|ire|rsi|rre)$", options: .regularExpression) != nil
                        || en.lowercased().hasPrefix("to "))
                        && es.lowercased().hasPrefix("a ")
                        && es.dropFirst(2).range(of: "^\\S+(ar|er|ir|arse|erse|irse)\\b", options: .regularExpression) != nil {
                        es = String(es.dropFirst(2))
                    }
                    file.lessons[li].vocab[vi].en = en
                    file.lessons[li].vocab[vi].es = es
                    done += 1
                    if done % 25 == 0 { try save(); print("\(level): \(done) translated") }
                }
            }
        }
        try save()
        print("\(level) finished: \(done) translated, \(failed) failed")
    }
}
