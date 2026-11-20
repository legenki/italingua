import Foundation
import FoundationModels

/// A short Italian text for reading practice.
nonisolated struct ReadingText: Equatable, Sendable {
    var title: String
    var text: String

    /// Sentences for line-by-line listening.
    var sentences: [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return out
    }
}

@Generable
nonisolated struct GeneratedReading {
    @Guide(description: "A short title in Italian")
    var title: String
    @Guide(description: "The text in Italian: 6 to 8 short, connected sentences about one everyday situation")
    var text: String
}

/// Reading texts from the on-device model: a new text on the lesson's words,
/// or someone else's Italian text rewritten for the learner's level.
nonisolated enum ReadingGenerator {
    static func levelRules(_ level: String) -> String {
        level == "A1"
            ? "CEFR A1: present tense only, very short sentences, the most common words"
            : "CEFR A2: short sentences, common words; present, passato prossimo, imperfetto and futuro are fine"
    }

    /// A new text that uses the lesson's words.
    static func lessonText(words: [String], topics: [String], level: String) async throws -> ReadingText {
        let session = LanguageModelSession(
            model: ModelFillBlankGenerator.model,
            instructions: """
                You write easy Italian reading texts for adult learners (\(levelRules(level))). \
                The text is one small story about everyday life, with correct grammar and natural Italian.
                """)
        let prompt = """
            Use as many of these words as fit naturally: \(words.joined(separator: ", ")).
            The grammar of the lesson: \(topics.joined(separator: "; ")).
            """
        let r = try await session.respond(to: prompt, generating: GeneratedReading.self,
                                          options: GenerationOptions(temperature: 0.7)).content
        return ReadingText(title: r.title.trimmingCharacters(in: .whitespacesAndNewlines),
                           text: r.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The learner's own text, rewritten for their level with the same meaning.
    static func adapt(_ original: String, level: String) async throws -> ReadingText {
        let session = LanguageModelSession(
            model: ModelFillBlankGenerator.model,
            instructions: """
                You rewrite Italian texts for adult learners (\(levelRules(level))). \
                Keep the meaning and the facts, drop details that are not needed, \
                use short sentences. Answer with the rewritten Italian text only.
                """)
        let text = try await session.respond(to: "Rewrite this text:\n\(original)",
                                             options: GenerationOptions(temperature: 0.3)).content
        return ReadingText(title: "", text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Course words that occur in the text, for the glossary under it.
    /// Matching is by whole word, ignoring case and accents; longer entries first
    /// so "fare la spesa" wins over "fare".
    static func glossary(for text: String, vocab: [VocabItem]) -> [VocabItem] {
        let tokens = " " + TranslationChecker.words(text).map(TranslationChecker.fold).joined(separator: " ") + " "
        var remaining = tokens
        var seen = Set<String>()

        func normalizedKey(_ italian: String) -> String {
            TranslationChecker.words(italian).map(TranslationChecker.fold).joined(separator: " ")
        }

        func firstRange(of key: String, in haystack: String) -> Range<String.Index>? {
            [" " + key + " ", "'" + key + " "]
                .compactMap { haystack.range(of: $0) }
                .min { $0.lowerBound < $1.lowerBound }
        }

        return vocab
            .filter { $0.pos != .proper && $0.italian.count > 2 }
            .sorted { $0.italian.count > $1.italian.count }
            .filter { item in
                let key = normalizedKey(item.italian)
                guard !key.isEmpty, firstRange(of: key, in: remaining) != nil,
                      seen.insert(TranslationChecker.fold(item.italian)).inserted else { return false }
                while let r = remaining.range(of: " " + key + " ") {
                    remaining.replaceSubrange(r, with: " ")
                }
                while let r = remaining.range(of: "'" + key + " ") {
                    remaining.replaceSubrange(r, with: "' ")
                }
                return true
            }
            .sorted {
                let r0 = firstRange(of: normalizedKey($0.italian), in: tokens)?.lowerBound ?? tokens.endIndex
                let r1 = firstRange(of: normalizedKey($1.italian), in: tokens)?.lowerBound ?? tokens.endIndex
                return r0 < r1
            }
    }
}
