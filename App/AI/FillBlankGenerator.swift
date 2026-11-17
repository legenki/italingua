import Foundation
import FoundationModels

/// One "fill in the missing word" task. The answer always comes from the
/// static vocabulary; the model only writes the surrounding sentence.
nonisolated struct FillBlankExercise: Identifiable, Equatable, Sendable {
    enum Source: Sendable { case model, fallback }

    let id = UUID()
    let wordID: String
    let lessonID: String
    let pos: PartOfSpeech
    /// Sentence with "___" in place of the answer (or just "___" without context).
    let sentence: String
    let answer: String
    /// Russian gloss of the answer, from the content.
    let hintRU: String
    let source: Source

    static let blank = "___"
}

/// What a generator needs to know about the target word.
nonisolated struct TargetWord: Sendable {
    let wordID: String
    let lessonID: String
    let italian: String
    let russian: String
    let pos: PartOfSpeech
    let gender: String?
}

nonisolated protocol FillBlankGenerating: Sendable {
    func makeExercise(for word: TargetWord, lessonTitle: String) async throws -> FillBlankExercise
}

enum FillBlankError: LocalizedError {
    case targetMissing

    var errorDescription: String? {
        "Модель не смогла составить предложение с нужным словом."
    }
}

// MARK: - Foundation Models

@Generable
nonisolated struct GeneratedSentence {
    @Guide(description: "One short, natural Italian sentence of 4 to 12 words for a beginner (CEFR A1). It contains the target expression exactly as given, unchanged.")
    var sentence: String
}

nonisolated struct ModelFillBlankGenerator: FillBlankGenerating {
    var attempts = 3

    // Prompts are in English on purpose: Russian is not guaranteed to be a
    // supported model language, and the Russian hint comes from our content.
    static let instructions = """
        You write example sentences for an Italian course for beginners (CEFR A1).
        Use the present tense and everyday vocabulary. Keep sentences short and natural.
        Never change the form of the target expression: no plural, no other ending, \
        no other tense, no contraction with an article or preposition.
        """

    func makeExercise(for word: TargetWord, lessonTitle: String) async throws -> FillBlankExercise {
        for _ in 0..<attempts {
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = """
                Lesson topic: \(lessonTitle).
                Target expression: "\(word.italian)" (\(Self.describe(word))).
                Write one sentence that contains "\(word.italian)" exactly in this form.
                """
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedSentence.self,
                options: GenerationOptions(temperature: 0.9))
            if let blanked = Self.blank(word.italian, in: response.content.sentence) {
                return FillBlankExercise(wordID: word.wordID, lessonID: word.lessonID, pos: word.pos,
                                         sentence: blanked, answer: word.italian,
                                         hintRU: word.russian, source: .model)
            }
        }
        throw FillBlankError.targetMissing
    }

    static func describe(_ w: TargetWord) -> String {
        switch w.pos {
        case .noun: "noun" + (w.gender.map { ", gender \($0)" } ?? "")
        case .verb: "verb form"
        case .adj: "adjective"
        case .adv: "adverb"
        case .prep: "preposition"
        case .phrase: "fixed expression"
        default: w.pos.rawValue
        }
    }

    /// Replaces the first whole-word occurrence of `target` (case-insensitive,
    /// accent-sensitive) with the blank. Nil if the sentence lacks the target.
    static func blank(_ target: String, in sentence: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: target)
            .replacingOccurrences(of: "'", with: "['’]")
            .replacingOccurrences(of: "’", with: "['’]")
        let pattern = "(?<![\\p{L}])" + escaped + "(?![\\p{L}])"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
              let r = Range(m.range, in: sentence)
        else { return nil }
        return sentence.replacingCharacters(in: r, with: FillBlankExercise.blank)
    }
}

// MARK: - Fallback without the model

/// Used when the model is unavailable or fails: recall the word from its
/// Russian gloss, without a context sentence.
nonisolated struct FallbackFillBlankGenerator: FillBlankGenerating {
    func makeExercise(for word: TargetWord, lessonTitle: String) async throws -> FillBlankExercise {
        FillBlankExercise(wordID: word.wordID, lessonID: word.lessonID, pos: word.pos,
                          sentence: FillBlankExercise.blank, answer: word.italian,
                          hintRU: word.russian, source: .fallback)
    }
}
